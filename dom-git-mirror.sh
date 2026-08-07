#!/bin/bash
############################################################################
# dom-git-mirror.sh - internal git mirror helper (server + client commands)
#
# Copyright Nash!Com, Daniel Nashed 2026 - APACHE 2.0 see LICENSE
############################################################################

set -e

DGM_VERSION="0.10.28"

DGM_HOME="${DGM_HOME:-$HOME/.dom-git-mirror}"

# Client-side cache of repo names, written by "pull --all"/"clone --all"
# so a repo discovered that way is remembered for future plain "pull"
# (see client_repo_names()) -- not sourced like DGM_CONFIG_FILE, just a
# plain newline list read on demand.

DGM_CLIENT_REPOS_FILE="$DGM_HOME/repos"

# Any client-side setting can be persisted here (written by "ca" the first
# time trust is established with a mirror, or by "cfg"). The file itself is
# plain "VAR=value" -- easy to hand-edit -- so instead of complicating the
# file, an explicitly-exported env var is saved off, the file is sourced,
# then the explicit value (if any) is restored -- that's what actually
# guarantees precedence: explicit env var > persisted config > hardcoded
# default, without the file needing "${VAR:-default}" syntax to achieve it.

DGM_CONFIG_FILE="$DGM_HOME/config"
_dgm_url_env="$DGM_URL"
_dgm_clone_dir_env="$DGM_CLONE_DIR"

if [ -f "$DGM_CONFIG_FILE" ]; then
  . "$DGM_CONFIG_FILE"
fi

[ -n "$_dgm_url_env" ]       && DGM_URL="$_dgm_url_env"
[ -n "$_dgm_clone_dir_env" ] && DGM_CLONE_DIR="$_dgm_clone_dir_env"
unset _dgm_url_env _dgm_clone_dir_env

# DGM_HOST is intentionally left unresolved here. It's a server-only
# variable now -- servers default it to their own "hostname -f" (see
# cmd_cert -- needs the real FQDN, not just $HOSTNAME, since that's what
# goes into the cert's CN/SAN). Clients don't use DGM_HOST at all; see
# DGM_URL and require_dgm_url instead.

DGM_BASE_DIR="${DGM_BASE_DIR:-/local/dom-git-mirror}"

# Same idea as DGM_CONFIG_FILE above, but for server-side settings (written
# by "env" the first time it's run). Sourced right after DGM_BASE_DIR
# resolves -- needed to know where to look -- but before the defaults
# below, using the same "preserve explicit env vars across sourcing"
# approach so the .env file stays plain too.

DGM_ENV_FILE="$DGM_BASE_DIR/.env"
_dgm_host_env="$DGM_HOST"
_dgm_http_port_env="$DGM_HTTP_PORT"
_dgm_https_port_env="$DGM_HTTPS_PORT"
_dgm_repos_dir_env="$DGM_REPOS_DIR"
_dgm_ca_name_env="$DGM_CA_NAME"
if [ -f "$DGM_ENV_FILE" ]; then
  . "$DGM_ENV_FILE"
fi
[ -n "$_dgm_host_env" ]       && DGM_HOST="$_dgm_host_env"
[ -n "$_dgm_http_port_env" ]  && DGM_HTTP_PORT="$_dgm_http_port_env"
[ -n "$_dgm_https_port_env" ] && DGM_HTTPS_PORT="$_dgm_https_port_env"
[ -n "$_dgm_repos_dir_env" ]  && DGM_REPOS_DIR="$_dgm_repos_dir_env"
[ -n "$_dgm_ca_name_env" ]    && DGM_CA_NAME="$_dgm_ca_name_env"
unset _dgm_host_env _dgm_http_port_env _dgm_https_port_env _dgm_repos_dir_env _dgm_ca_name_env

DGM_HTTP_PORT="${DGM_HTTP_PORT:-8080}"
DGM_HTTPS_PORT="${DGM_HTTPS_PORT:-8443}"
DGM_REPOS_DIR="${DGM_REPOS_DIR:-/local/git-mirror}"
DGM_CLONE_DIR="${DGM_CLONE_DIR:-/local/github}"
DGM_CA_NAME="${DGM_CA_NAME:-git-mirror-ca}"

DGM_TLS_DIR="${DGM_BASE_DIR}/tls"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# On real Linux/macOS, openssl -subj wants a single leading slash ("/CN=...").
# On Windows Git-Bash/MSYS, that leading slash gets rewritten as a filesystem
# path unless doubled ("//CN=..."). Only double it there -- doubling on real
# Linux openssl drops the field instead of fixing anything.

CN_PREFIX="/"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*) CN_PREFIX="//" ;;
esac

# Known repos, one per line. Two forms:
#   org/repo            -- GitHub shorthand, expands to
#                           https://github.com/org/repo.git; local name is
#                           just "repo" (the part after the last "/").
#   name|url            -- explicit, for any other git host, or to use a
#                           local name that doesn't match the upstream repo.
#
# Precedence: explicit DGM_REPOS env var > $DGM_REPOS_FILE (edited via
# "repos") > this hardcoded default.

DGM_REPOS_DEFAULT="nashcom/domino-startscript
HCL-TECH-SOFTWARE/domino-container"

DGM_REPOS_FILE="$DGM_BASE_DIR/repos.list"
if [ -n "$DGM_REPOS" ]; then
  : # explicit env var already set -- leave it alone
elif [ -f "$DGM_REPOS_FILE" ]; then
  DGM_REPOS="$(cat "$DGM_REPOS_FILE")"
else
  DGM_REPOS="$DGM_REPOS_DEFAULT"
fi

# $1 = one line from $DGM_REPOS -- returns the local name for that entry.
_repo_line_name()
{
  case "$1" in
    *"|"*) echo "${1%%|*}" ;;
    *)     echo "${1##*/}" ;;
  esac
}

# $1 = one line from $DGM_REPOS -- returns the clone URL for that entry.
_repo_line_url()
{
  case "$1" in
    *"|"*) echo "${1#*|}" ;;
    *)     echo "https://github.com/$1.git" ;;
  esac
}

repo_names()
{
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in "#"*) continue ;; esac
    _repo_line_name "$line"
  done <<< "$DGM_REPOS"
}

repo_url()
{
  local name="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in "#"*) continue ;; esac
    if [ "$(_repo_line_name "$line")" = "$name" ]; then
      _repo_line_url "$line"
      return 0
    fi
  done <<< "$DGM_REPOS"
  echo ""
}

build_repo_url()
{
  echo "$DGM_URL/$1.git"
}

url_scheme()
{
  echo "${1%%://*}"
}

url_host()
{
  local rest="${1#*://}"
  rest="${rest%%/*}"
  echo "${rest%%:*}"
}

# Falls back to the scheme's standard port (443/80) if DGM_URL doesn't
# specify one -- matches normal URL conventions (curl, browsers, git all
# do this). A hand-configured URL for a deployment behind a reverse proxy
# on standard ports shouldn't be forced to spell out ":443".

url_port()
{
  local rest="${1#*://}"
  rest="${rest%%/*}"
  if [ "$rest" = "${rest%%:*}" ]; then
    case "$(url_scheme "$1")" in
      https) echo 443 ;;
      http)  echo 80 ;;
    esac
  else
    echo "${rest#*:}"
  fi
}

dgm_is_https()
{
  case "$DGM_URL" in
    https://*) return 0 ;;
    *)         return 1 ;;
  esac
}

# Builds "scheme://host[:port]", omitting the port when it's already the
# scheme's standard one (443/80) -- the mirror image of url_port()'s
# fallback, so a standard-port deployment doesn't get an unnecessary
# ":443" baked into every generated/guessed URL.

build_url()
{
  local scheme="$1" host="$2" port="$3"
  case "$scheme:$port" in
    https:443|http:80) echo "$scheme://$host" ;;
    *)                 echo "$scheme://$host:$port" ;;
  esac
}

print_delim()
{
  echo "--------------------------------------------------------------------------------"
}

header()
{
  echo
  print_delim
  echo "$1"
  print_delim
  echo
}

log()
{
  echo
  echo "$1"
  echo
}

log_err()
{
  echo >&2
  echo "ERROR: $1" >&2
  echo >&2
}

usage()
{
  header "dom-git-mirror.sh v$DGM_VERSION - Help"

  echo "Usage: dom-git-mirror.sh <command> [args]"
  echo

  local cw=44
  echo "Run on the mirror host:"
  echo
  printf "  %-${cw}s%s\n" "cert" 'Generate/reuse the micro CA, refresh the TLS leaf cert'
  printf "  %-${cw}s%s\n" "start [-ip]" 'Bring the mirror container up (auto-runs "cert" first)'
  printf "  %-${cw}s%s\n" "stop" "Bring the mirror container down"
  printf "  %-${cw}s%s\n" "restart" "Stop then start"
  printf "  %-${cw}s%s\n" "logs" "Show container logs"
  printf "  %-${cw}s%s\n" "mirror [name|url ...]" "Create/refresh git mirrors (default: all known repos)"
  printf "  %-${cw}s%s\n" "env" "Open the persisted server config (\$DGM_BASE_DIR/.env) in \$EDITOR"
  printf "  %-${cw}s%s\n" "repos" "Edit the known repos list (\$DGM_BASE_DIR/repos.list) in \$EDITOR"
  echo

  echo "\"start -ip\" prints the install line using this host's detected IP instead of its hostname --"
  echo "the cert already covers both either way, this only matters for ad-hoc setups with no DNS record."
  echo

  echo "Run on any machine pulling from the mirror:"
  echo
  printf "  %-${cw}s%s\n" "ca" "Fetch/cache the mirror's CA cert (via openssl s_client)"
  printf "  %-${cw}s%s\n" "pull [name|url ...] [--all]" "Clone (if missing) or update repo(s) (default: your known repos)"
  printf "  %-${cw}s%s\n" "clone [name|url ...] [--dest DIR] [--all]" "Explicit clone, e.g. to a custom --dest"
  printf "  %-${cw}s%s\n" "update" "Swap the local script for the mirror's current version"
  printf "  %-${cw}s%s\n" "check" "Compare local checkouts against the mirror's /status by commit hash"
  printf "  %-${cw}s%s\n" "server" "List repos on the mirror, fetched live -- no local checkout needed"
  printf "  %-${cw}s%s\n" "cfg" "Open the persisted client config (\$DGM_HOME/config) in \$EDITOR"
  echo

  echo "\"--all\" fetches the mirror's current repo list live and syncs everything found there --"
  echo "deliberate opt-in, so a repo added server-side doesn't silently show up on a routine pull."
  echo "It also remembers that list (\$DGM_HOME/repos), so it becomes your new default from then on."
  echo

  echo "Works either side:"
  echo
  printf "  %-${cw}s%s\n" "ls" "List known repos with branch, last commit time + hash"
  echo

  echo "Config (mirror host):"
  print_delim
  printf "  %-16s %-26s %-26s\n" "ENV VAR" "DEFAULT" "CURRENT"
  printf "  %-16s %-26s %-26s\n" "DGM_HOST" "<derived from hostname>" "${DGM_HOST:-<not set>}"
  printf "  %-16s %-26s %-26s\n" "DGM_HTTP_PORT" "8080" "$DGM_HTTP_PORT"
  printf "  %-16s %-26s %-26s\n" "DGM_HTTPS_PORT" "8443" "$DGM_HTTPS_PORT"
  printf "  %-16s %-26s %-26s\n" "DGM_BASE_DIR" "/local/dom-git-mirror" "$DGM_BASE_DIR"
  printf "  %-16s %-26s %-26s\n" "DGM_REPOS_DIR" "/local/git-mirror" "$DGM_REPOS_DIR"
  printf "  %-16s %-26s %-26s\n" "DGM_CA_NAME" "git-mirror-ca" "$DGM_CA_NAME"
  echo

  local url="$DGM_URL"
  [ -z "$url" ] && { default_dgm_url || true; url="$DGM_URL"; }

  echo "Config (client):"
  print_delim
  printf "  %-16s %-26s %-26s\n" "ENV VAR" "DEFAULT" "CURRENT"
  printf "  %-16s %-26s %-26s\n" "DGM_URL" "<derived from hostname>" "${url:-<not set>}"
  printf "  %-16s %-26s %-26s\n" "DGM_CLONE_DIR" "/local/github" "$DGM_CLONE_DIR"
  printf "  %-16s %-26s %-26s\n" "DGM_HOME" "\$HOME/.dom-git-mirror" "$DGM_HOME"
  echo

  echo "Known repos:"
  echo
  local name
  for name in $(repo_names); do
    echo "  $name"
  done
  echo

  echo "Install on a new client:"
  echo
  echo "  export DGM_URL=$url; curl -fsSLk \"\$DGM_URL/setup.sh\" | bash -s -- pull"
  echo

  print_delim
  echo
}

# Convention-based fallback: "https://dom-git-mirror.<client's own
# domain>:<https port>". Sets DGM_URL directly; leaves it untouched (and
# returns 1) if no domain can be found, e.g. a bare hostname with no dot.

default_dgm_url()
{
  local fqdn domain
  fqdn="$(timeout 2 hostname -f 2>/dev/null || echo "$HOSTNAME")"
  domain="${fqdn#*.}"

  if [ "$domain" = "$fqdn" ]; then
    return 1
  fi

  DGM_URL="$(build_url https "dom-git-mirror.$domain" "$DGM_HTTPS_PORT")"
}

# Fast, bounded-timeout reachability probe for a URL that might be wrong
# -- deliberately doesn't go through curl_mirror/ensure_ca, since that
# calls "openssl s_client" (fetch_ca_openssl), which has no timeout of
# its own and could hang on an unreachable host, exactly what this
# function exists to avoid. Verifies against the cached CA when one
# already exists (the common case, zero extra risk); "-k" only applies
# to the genuinely-first-contact case, where nothing is established yet
# and this is a probe of an untrusted, possibly-wrong address anyway.

check_dgm_url()
{
  if dgm_is_https && [ -f "$DGM_HOME/ca.crt" ]; then
    curl -fsSL --cacert "$DGM_HOME/ca.crt" --connect-timeout 3 --max-time 5 "$1/version" </dev/null 2>/dev/null
  else
    curl -fsSLk --connect-timeout 3 --max-time 5 "$1/version" </dev/null 2>/dev/null
  fi
}

# Fetches a path under $DGM_URL, always verified -- never "-k". For
# https this calls ensure_ca itself (establishing trust via TOFU if this
# is genuinely the first contact ever, otherwise just reusing the cached
# CA for free) so every data fetch in the script is either verified or
# genuinely can't be yet, never silently unverified. $2, if given, is a
# file to save to ("-o"); otherwise the content goes to stdout.

curl_mirror()
{
  local path="$1" out="$2" ca_file=""
  dgm_is_https && ca_file="$(ensure_ca)"

  if [ -n "$out" ]; then
    if [ -n "$ca_file" ]; then
      curl -fsSL --cacert "$ca_file" "$DGM_URL$path" -o "$out" </dev/null 2>/dev/null
    else
      curl -fsSL "$DGM_URL$path" -o "$out" </dev/null 2>/dev/null
    fi
  else
    if [ -n "$ca_file" ]; then
      curl -fsSL --cacert "$ca_file" "$DGM_URL$path" </dev/null 2>/dev/null
    else
      curl -fsSL "$DGM_URL$path" </dev/null 2>/dev/null
    fi
  fi
}

# Live repo names from the mirror's own /status (same data "check" already
# fetches -- name is the first pipe-delimited field of each line). Used
# only for "--all", a deliberate opt-in -- routine "pull"/"clone" with no
# args keeps using the client's own known-repos table, so a repo added
# server-side doesn't silently start showing up on every client's next
# routine run.

remote_repo_names()
{
  curl_mirror "/status" | awk -F'|' '{print $1}'
}

# The client's own known-repo names for "pull"/"clone" (no args), "ls",
# and "check": the cache written by a previous "--all" if it exists,
# otherwise whatever repo_names() currently resolves to (hardcoded
# default, or the server's repos.list if this happens to also be a
# mirror host).

client_repo_names()
{
  if [ -f "$DGM_CLIENT_REPOS_FILE" ]; then
    cat "$DGM_CLIENT_REPOS_FILE"
  else
    repo_names
  fi
}

require_dgm_url()
{
  if [ -z "$DGM_URL" ]; then
    default_dgm_url || true
  fi

  if [ -z "$DGM_URL" ]; then
    local msg
    msg="$(printf 'DGM_URL is not set and no default could be determined.\nThere is no default for a client -- your own hostname is never the mirror address, and "dom-git-mirror.<your domain>" could not be guessed either (no domain on this host).\nSet it explicitly, e.g.: DGM_URL=https://<mirror-host>:8443 %s %s\nOnce set, running "ca" will remember it in %s for future runs.' "$0" "$*" "$DGM_CONFIG_FILE")"
    log_err "$msg"
    exit 1
  fi

  if ! check_dgm_url "$DGM_URL" >/dev/null; then
    local msg
    msg="$(printf 'Could not reach %s/version.\nEither the mirror is down, or the URL is wrong.\nSet DGM_URL explicitly if needed, e.g.: DGM_URL=https://<mirror-host>:8443 %s %s' "$DGM_URL" "$0" "$*")"
    log_err "$msg"
    exit 1
  fi
}

show_cert()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  local SAN_LINE=$(openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | grep -E 'DNS:|IP Address:' | xargs )
  local SAN_DNS=$(echo "$SAN_LINE" | tr ',' '\n' | sed 's/^ *//' | grep '^DNS:' | sed 's/^DNS://' | paste -sd'~' - | sed 's/~/, /g')
  local SAN_IP=$(echo "$SAN_LINE" | tr ',' '\n' | sed 's/^ *//' | grep '^IP Address:' | sed 's/^IP Address://' | paste -sd'~' - | sed 's/~/, /g')
  local SUBJECT=$(openssl x509 -in "$1" -noout -subject | cut -d '=' -f 2- )
  local ISSUER=$(openssl x509 -in "$1" -noout -issuer | cut -d '=' -f 2- )
  local EXPIRATION=$(openssl x509 -in "$1" -noout -enddate | cut -d '=' -f 2- )
  local FINGERPRINT=$(openssl x509 -in "$1" -noout -fingerprint | cut -d '=' -f 2- )
  local SERIAL=$(openssl x509 -in "$1" -noout -serial | cut -d '=' -f 2- )

  echo
  [ -n "$SAN_DNS" ] && printf "%-14s: %s\n" "SAN (DNS)" "$SAN_DNS"
  [ -n "$SAN_IP" ] && printf "%-14s: %s\n" "SAN (IP)" "$SAN_IP"
  if [ "$SUBJECT" = "$ISSUER" ]; then
    printf "%-14s: %s\n" "CA Root" "$SUBJECT"
  else
    printf "%-14s: %s\n" "Subject" "$SUBJECT"
    printf "%-14s: %s\n" "Issuer" "$ISSUER"
  fi
  printf "%-14s: %s\n" "Expiration" "$EXPIRATION"
  printf "%-14s: %s\n" "Fingerprint" "$FINGERPRINT"
  printf "%-14s: %s\n" "Serial" "$SERIAL"
  printf "%-14s: %s\n" "File" "$1"
  echo
}

cmd_cfg()
{
  mkdir -p "$DGM_HOME"

  if [ ! -f "$DGM_CONFIG_FILE" ]; then
    cat > "$DGM_CONFIG_FILE" <<EOF
# dom-git-mirror client config -- uncomment a line to override its default.
# "ca" also rewrites DGM_URL below once trust is established with a
# mirror, so anything left commented here just falls back to that. An
# explicitly-exported env var always wins over whatever is set here, for
# a single run -- e.g. "DGM_URL=... ./dom-git-mirror.sh pull".
#
# DGM_URL has no default unless "https://dom-git-mirror.<your domain>:$DGM_HTTPS_PORT"
# resolves -- see "help" for what was guessed, if anything. Must include
# an explicit scheme and port, e.g. https://mirror.example.com:8443
# DGM_URL=${DGM_URL}
# DGM_CLONE_DIR=${DGM_CLONE_DIR}
EOF
  fi

  header "Editing Config: $DGM_CONFIG_FILE"

  local editor="${EDITOR:-vi}"
  "$editor" "$DGM_CONFIG_FILE"
}

cmd_env()
{
  mkdir -p "$DGM_BASE_DIR"

  if [ ! -f "$DGM_ENV_FILE" ]; then
    local host="${DGM_HOST:-$(timeout 2 hostname -f 2>/dev/null || echo "$HOSTNAME")}"
    cat > "$DGM_ENV_FILE" <<EOF
# dom-git-mirror server config -- uncomment a line to override its default.
# "cert" resolves DGM_HOST from "hostname -f" if not set here or via env
# var. An explicitly-exported env var always wins over whatever is set
# here, for a single run -- e.g. "DGM_HOST=... ./dom-git-mirror.sh cert".
#
# DGM_HOST=${host}
# DGM_HTTP_PORT=${DGM_HTTP_PORT}
# DGM_HTTPS_PORT=${DGM_HTTPS_PORT}
# DGM_REPOS_DIR=${DGM_REPOS_DIR}
# DGM_CA_NAME=${DGM_CA_NAME}
EOF
  fi

  header "Editing Server Config: $DGM_ENV_FILE"

  local editor="${EDITOR:-vi}"
  "$editor" "$DGM_ENV_FILE"
}

cmd_repos()
{
  mkdir -p "$DGM_BASE_DIR"

  if [ ! -f "$DGM_REPOS_FILE" ]; then
    cat > "$DGM_REPOS_FILE" <<EOF
# dom-git-mirror known repos, one per line -- edit this list to change
# what "mirror" fetches and what "pull"/"clone" accept by name. Two forms:
#
# org/repo    -- GitHub shorthand, expands to https://github.com/org/repo.git;
#                local name is just "repo" (the part after the last "/").
# name|url    -- explicit, for any other git host, or a local name that
#                doesn't match the upstream repo name.
#
$DGM_REPOS
EOF
  fi

  header "Editing Known Repos: $DGM_REPOS_FILE"

  local editor="${EDITOR:-vi}"
  "$editor" "$DGM_REPOS_FILE"
}

# This host's default-route IP(s) (v4 and v6), so the cert validates
# correctly if a client connects via the server's real LAN address
# instead of a hostname -- deliberately not every IP on every interface,
# just the one actually used for outbound traffic. Avoids picking up
# noise like Docker's own bridge networks (e.g. 172.17.0.1), which
# "hostname -I" would otherwise include. "ip route get" only consults the
# routing table, no packets sent, so this works even with no real
# internet route as long as a default route exists (the normal case even
# on an air-gapped network). Falls back to nothing (not an error) if "ip"
# isn't available or there's no default route at all -- the cert still
# works via DGM_HOST/localhost/127.0.0.1, just without the extra IP.
local_ips()
{
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'
  ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'
}

# Populated by "cert -ip"/"start -ip" so the resolved address is a real,
# reusable variable instead of an anonymous "local_ips | head -1"
# scattered wherever it's needed. Empty until resolve_primary_ip runs.
DGM_PRIMARY_IP=""

resolve_primary_ip()
{
  DGM_PRIMARY_IP="$(local_ips | head -1)"
}

# True if $1 looks like an IP address (v4 dotted-quad, or contains a
# colon for v6) rather than a hostname -- used to tag SAN entries with
# the correct type ("IP:" vs "DNS:"), since a DNS-type SAN entry
# containing an IP string wouldn't actually match a client connecting by
# that IP.
is_ip_address()
{
  case "$1" in
    *:*)                        return 0 ;;
    [0-9]*.[0-9]*.[0-9]*.[0-9]*) return 0 ;;
    *)                          return 1 ;;
  esac
}

cmd_cert()
{
  header "Generating TLS Certificate"

  # Server-only default: needs the real FQDN (not just $HOSTNAME) so the
  # cert's CN/SAN is actually reachable by clients outside this host's own
  # local view of itself. Bounded with timeout since "-f" does a DNS
  # lookup that can otherwise hang on a misconfigured resolver.

  DGM_HOST="${DGM_HOST:-$(timeout 2 hostname -f 2>/dev/null || echo "$HOSTNAME")}"

  local out_dir="$DGM_TLS_DIR"
  local ca_key="$out_dir/ca.key"
  local ca_cert="$out_dir/ca.crt"
  local leaf_key="$out_dir/tls.key"
  local leaf_cert="$out_dir/tls.crt"
  local fullchain="$out_dir/tls-fullchain.crt"
  local ca_days=3650
  local leaf_days=365

  mkdir -p "$out_dir"

  if [ -f "$ca_key" ] && [ -f "$ca_cert" ]; then
    log "Reusing existing CA ($ca_cert) -- delete it first to rotate the CA itself"
  else
    log "Generating micro CA ($ca_days days) -- $ca_cert"
    openssl ecparam -name prime256v1 -genkey -noout -out "$ca_key"
    openssl req -x509 -new \
      -key "$ca_key" \
      -out "$ca_cert" \
      -days "$ca_days" \
      -subj "${CN_PREFIX}CN=$DGM_CA_NAME" \
      -addext "basicConstraints=critical,CA:true" \
      -addext "keyUsage=critical,keyCertSign,cRLSign"
  fi

  log "Generating leaf cert ($leaf_days days), signed by the CA -- $leaf_cert"
  openssl ecparam -name prime256v1 -genkey -noout -out "$leaf_key"

  local san
  if is_ip_address "$DGM_HOST"; then
    san="IP:$DGM_HOST"
  else
    san="DNS:$DGM_HOST"
  fi
  [ "$DGM_HOST" != "localhost" ]  && san="$san,DNS:localhost"
  [ "$DGM_HOST" != "::1" ]        && san="$san,IP:::1"
  [ "$DGM_HOST" != "127.0.0.1" ]  && san="$san,IP:127.0.0.1"

  local ip
  for ip in $(local_ips); do
    san="$san,IP:$ip"
  done

  openssl req -new \
    -key "$leaf_key" \
    -subj "${CN_PREFIX}CN=$DGM_HOST" \
    -out "$out_dir/tls.csr" \
    -addext "subjectAltName=$san" \
    -addext "basicConstraints=CA:false" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=serverAuth"

  openssl x509 -req \
    -in "$out_dir/tls.csr" \
    -CA "$ca_cert" \
    -CAkey "$ca_key" \
    -CAcreateserial \
    -out "$leaf_cert" \
    -days "$leaf_days" \
    -copy_extensions copy

  rm -f "$out_dir/tls.csr" "$out_dir/ca.srl"

  log "Writing full chain (leaf + CA) -- $fullchain"
  cat "$leaf_cert" "$ca_cert" > "$fullchain"

  chmod 600 "$ca_key" "$leaf_key"
  chmod 644 "$ca_cert" "$leaf_cert" "$fullchain"
  log "Done."

  header "TLS Leaf Certificate"
  show_cert "$leaf_cert"
}

# ---- server: config generation (docker-compose.yml + nginx.conf) ----

# Generated into $DGM_BASE_DIR at runtime so this script is the only file
# that needs to be deployed -- nothing else to ship or lose track of.

write_config_files()
{
  mkdir -p "$DGM_BASE_DIR"

  cat > "$DGM_BASE_DIR/nginx.conf" <<'EOF'
events {
}

http {
    server {
        listen 443 ssl;
        server_name _;

        ssl_certificate     /etc/nginx/tls/tls-fullchain.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;

        root /usr/share/nginx/html;

        location / {
            autoindex off;

            limit_except GET HEAD {
                deny all;
            }
        }

        location = /setup.sh {
            alias /usr/share/nginx/html/dom-git-mirror.sh;
        }
    }

    server {
        listen 80;
        server_name _;

        root /usr/share/nginx/html;

        location / {
            autoindex off;

            limit_except GET HEAD {
                deny all;
            }
        }

        location = /setup.sh {
            alias /usr/share/nginx/html/dom-git-mirror.sh;
        }
    }
}
EOF

  cat > "$DGM_BASE_DIR/docker-compose.yml" <<EOF
services:
  nginx:
    image: nginx:alpine
    container_name: git-mirror
    restart: always

    ports:
      - "${DGM_HTTP_PORT}:80"
      - "${DGM_HTTPS_PORT}:443"

    volumes:
      - ${DGM_REPOS_DIR}:/usr/share/nginx/html:ro
      - ${DGM_BASE_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${DGM_TLS_DIR}:/etc/nginx/tls:ro
EOF
}

# ---- server: container lifecycle ----

cmd_start()
{
  require_docker

  header "Starting Mirror Server"

  local use_ip=0
  [ "$1" = "-ip" ] && use_ip=1

  cmd_cert
  write_config_files
  mkdir -p "$DGM_REPOS_DIR"

  if [ -z "$(ls -A "$DGM_REPOS_DIR" 2>/dev/null)" ]; then
    log "No mirrors found under $DGM_REPOS_DIR -- mirroring known repos now"
    cmd_mirror
  fi

  # Serve the currently running copy at /setup.sh so clients have a single
  # file to bootstrap from (e.g. "curl .../setup.sh | DGM_URL=<url> bash
  # -s -- pull"). Intentionally left byte-identical to the source, not
  # baked with this host's identity.

  cp "$SCRIPT_DIR/dom-git-mirror.sh" "$DGM_REPOS_DIR/dom-git-mirror.sh"

  # Plain-text version endpoint, so anyone (or "update") can check what
  # the mirror is currently serving without downloading the whole script.

  echo "$DGM_VERSION" > "$DGM_REPOS_DIR/version"

  # Force a fresh container so nginx re-reads its config -- "up -d" on an
  # already-running container with the same compose service definition
  # won't pick up nginx.conf edits on its own, since nginx only loads it
  # once at process start.

  ( cd "$DGM_BASE_DIR" && docker compose down )
  ( cd "$DGM_BASE_DIR" && docker compose up -d )
  sleep 2
  echo
  ( cd "$DGM_BASE_DIR" && docker compose logs )
  echo

  local install_host="$DGM_HOST"
  if [ "$use_ip" = "1" ]; then
    resolve_primary_ip
    if [ -n "$DGM_PRIMARY_IP" ]; then
      install_host="$DGM_PRIMARY_IP"
    else
      log_err "Could not detect a primary IP (no default route?) -- using hostname instead."
    fi
  fi

  header "Mirror Ready (v$DGM_VERSION)"
  echo "Install on a new client:"
  echo
  echo "  export DGM_URL=$(build_url https "$install_host" "$DGM_HTTPS_PORT"); curl -fsSLk \"\$DGM_URL/setup.sh\" | bash -s -- pull"
  echo
}

cmd_stop()
{
  require_docker

  header "Stopping Mirror Server"

  write_config_files
  ( cd "$DGM_BASE_DIR" && docker compose down )
}

cmd_restart()
{
  cmd_stop
  cmd_start
}

cmd_logs()
{
  require_docker

  header "Container Logs"

  write_config_files
  ( cd "$DGM_BASE_DIR" && docker compose logs -f )
}

# ---- repo inventory (works on either side, whichever has data) ----

last_commit_date()
{
  git -C "$1" log -1 --format=%cd --date=iso-strict 2>/dev/null
}

repo_branch()
{
  git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null
}

commit_hash()
{
  git -C "$1" rev-parse HEAD 2>/dev/null
}

# Per-repo inventory: works on whichever side actually has data -- server
# bare mirrors under $DGM_REPOS_DIR, client checkouts under $DGM_CLONE_DIR,
# or both if this happens to be run somewhere with both present.
# $1 = base dir holding the repos, $2 = suffix on each repo's dir name
# (".git" for server bare mirrors, "" for client working checkouts).
# Prints nothing if no repo in that location actually exists (caller
# decides whether that means "skip this section" or "nothing at all").
# Aligned columns -- for human eyes ("ls"), not for parsing.

build_status_text()
{
  local base_dir="$1" suffix="$2" names="$3"
  local name repo hash any=0

  for name in $names; do
    repo="$base_dir/$name$suffix"
    if [ -d "$repo" ]; then
      if [ "$any" = "0" ]; then
        printf "%-24s%-14s%-27s%s\n" "NAME" "BRANCH" "LAST COMMIT" "HASH"
        echo
      fi
      hash="$(commit_hash "$repo")"
      printf "%-24s%-14s%-27s%s\n" "$name" "$(repo_branch "$repo")" "$(last_commit_date "$repo")" "${hash:0:10}"
      any=1
    fi
  done
}

# Same idea, but pipe-delimited (name|branch|last_commit|hash) -- for
# parsing (served at /status), not for eyes. Full hash (not abbreviated) --
# "check" needs an exact match, not just enough to look right in a table.

build_status_pipe()
{
  local base_dir="$1" suffix="$2"
  local name repo

  for name in $(repo_names); do
    repo="$base_dir/$name$suffix"
    if [ -d "$repo" ]; then
      echo "$name|$(repo_branch "$repo")|$(last_commit_date "$repo")|$(commit_hash "$repo")"
    fi
  done
}

cmd_ls()
{
  header "Known Repositories (v$DGM_VERSION)"

  local text found=0

  text="$(build_status_text "$DGM_REPOS_DIR" ".git" "$(repo_names)")"
  if [ -n "$text" ]; then
    echo "Server mirrors ($DGM_REPOS_DIR):"
    echo
    echo "$text" | sed 's/^/  /'
    echo
    found=1
  fi

  text="$(build_status_text "$DGM_CLONE_DIR" "" "$(client_repo_names)")"
  if [ -n "$text" ]; then
    echo "Local checkouts ($DGM_CLONE_DIR):"
    echo
    echo "$text" | sed 's/^/  /'
    echo
    found=1
  fi

  if [ "$found" = "0" ]; then
    log "No known repos found under $DGM_REPOS_DIR or $DGM_CLONE_DIR."
  fi
}

# Compares local checkouts against the mirror's own /status (fetched live
# and verified against the trusted CA) by commit hash -- exact match or
# not, no timestamp normalization involved. Only makes sense client-side:
# the server has no visibility into what any given client has checked
# out, so this can't live in "ls" on that side. Shows both date and hash
# per side, so the SYNCED verdict is visually backed by the actual values
# it's computed from, not just asserted.

cmd_check()
{
  require_dgm_url check

  header "Checking Local Repos Against Mirror (v$DGM_VERSION)"

  local remote
  remote="$(curl_mirror "/status")"

  if [ -z "$remote" ]; then
    log_err "Could not fetch status from $DGM_URL/status"
    exit 1
  fi

  local name any=0
  for name in $(client_repo_names); do
    local dir="$DGM_CLONE_DIR/$name"
    if [ -d "$dir" ]; then
      if [ "$any" = "0" ]; then
        printf "%-24s%-27s%-27s%-13s%-13s%s\n" "NAME" "MIRROR DATE" "LOCAL DATE" "MIRROR HASH" "LOCAL HASH" "SYNCED"
        echo
      fi
      local local_date remote_date local_hash remote_hash synced
      local_date="$(last_commit_date "$dir")"
      local_hash="$(commit_hash "$dir")"
      remote_date="$(echo "$remote" | awk -F'|' -v n="$name" '$1==n {print $3}')"
      remote_hash="$(echo "$remote" | awk -F'|' -v n="$name" '$1==n {print $4}')"

      if [ -z "$remote_hash" ]; then
        synced="unknown -- not on mirror"
      elif [ "$local_hash" = "$remote_hash" ]; then
        synced="yes"
      else
        synced="NO -- run pull"
      fi

      printf "%-24s%-27s%-27s%-13s%-13s%s\n" "$name" "${remote_date:-?}" "$local_date" "${remote_hash:+${remote_hash:0:10}}" "${local_hash:0:10}" "$synced"
      any=1
    fi
  done

  if [ "$any" = "0" ]; then
    log "No local checkouts found under $DGM_CLONE_DIR -- nothing to check."
  fi

  echo
}

# Shows what the mirror actually has, fetched live from its own /status --
# no local disk access needed, so this works from any client, not just on
# the mirror host itself (where "ls" already shows the same thing locally).

cmd_server()
{
  require_dgm_url server

  header "Repositories on the Mirror (v$DGM_VERSION)"

  local remote
  remote="$(curl_mirror "/status")"

  if [ -z "$remote" ]; then
    log_err "Could not fetch status from $DGM_URL/status"
    exit 1
  fi

  printf "%-24s%-14s%-27s%s\n" "NAME" "BRANCH" "LAST COMMIT" "HASH"
  echo
  local name branch last_commit hash
  while IFS='|' read -r name branch last_commit hash; do
    [ -z "$name" ] && continue
    printf "%-24s%-14s%-27s%s\n" "$name" "$branch" "$last_commit" "${hash:0:10}"
  done <<< "$remote"

  echo
}

# ---- server: mirror (create/refresh bare mirrors from GitHub) ----

mirror_one()
{
  local url="$1"
  local name
  name="$(basename "$url")"
  local repo="$DGM_REPOS_DIR/$name"

  header "Mirroring: $name"

  mkdir -p "$DGM_REPOS_DIR"

  if [ ! -d "$repo" ]; then
    log "Creating mirror: $url"
    git clone --mirror "$url" "$repo"
  else
    if ! git -C "$repo" rev-parse --is-bare-repository >/dev/null 2>&1; then
      log_err "Not a git repository: $repo -- remove it manually and re-run"
      return 1
    fi
    log "Updating mirror: $url"
    git -C "$repo" fetch --prune
  fi

  log "Updating dumb HTTP metadata"
  git -C "$repo" update-server-info

  log "Mirror ready: $repo (last commit: $(last_commit_date "$repo"))"
}

cmd_mirror()
{
  if [ "$#" -eq 0 ]; then
    local name
    for name in $(repo_names); do
      mirror_one "$(repo_url "$name")"
    done
  else
    local arg url
    for arg in "$@"; do
      url="$(repo_url "$arg")"
      [ -z "$url" ] && url="$arg"
      mirror_one "$url"
    done
  fi

  write_status_file
}

# $1 = base dir holding the repos, $2 = suffix on each repo's dir name
# (".git" for server bare mirrors, "" for client working checkouts).
# Regenerates the full inventory (all known repos, not just whichever
# subset was just mirrored) so it's always complete and current -- served
# at /status.json the same way "version" is served at /version.

build_status_json()
{
  local base_dir="$1" suffix="$2"
  local name repo branch commit hash
  local entries=()

  for name in $(repo_names); do
    repo="$base_dir/$name$suffix"
    if [ -d "$repo" ]; then
      branch="$(repo_branch "$repo")"
      commit="$(last_commit_date "$repo")"
      hash="$(commit_hash "$repo")"
      entries+=("\"$name\": {\"branch\": \"$branch\", \"last_commit\": \"$commit\", \"commit_hash\": \"$hash\"}")
    fi
  done

  echo "{"
  local i last=$((${#entries[@]} - 1))
  for i in "${!entries[@]}"; do
    if [ "$i" -eq "$last" ]; then
      echo "  ${entries[$i]}"
    else
      echo "  ${entries[$i]},"
    fi
  done
  echo "}"
}

write_status_file()
{
  build_status_json "$DGM_REPOS_DIR" ".git" > "$DGM_REPOS_DIR/status.json"
  build_status_pipe "$DGM_REPOS_DIR" ".git" > "$DGM_REPOS_DIR/status"
}

require_docker()
{
  if ! command -v docker >/dev/null 2>&1; then
    log_err "docker is not installed on this host.
This command manages the nginx mirror container and only makes sense on the mirror host itself, not a client."
    exit 1
  fi
}

# ---- client: ca ----

fetch_ca_openssl()
{
  local host port tmp
  host="$(url_host "$DGM_URL")"
  port="$(url_port "$DGM_URL")"
  tmp="$(mktemp)"
  if ! openssl s_client -connect "$host:$port" -servername "$host" -showcerts </dev/null 2>/dev/null > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  local in_cert=0 cert="" found="" subj issuer
  while IFS= read -r line; do
    case "$line" in
      "-----BEGIN CERTIFICATE-----")
        in_cert=1
        cert="$line"
        ;;
      "-----END CERTIFICATE-----")
        cert="$cert
$line"
        in_cert=0
        subj="$(echo "$cert" | openssl x509 -noout -subject 2>/dev/null)"
        issuer="$(echo "$cert" | openssl x509 -noout -issuer 2>/dev/null)"
        if [ -n "$subj" ] && [ "${subj#subject=}" = "${issuer#issuer=}" ]; then
          found="$cert"
        fi
        ;;
      *)
        [ "$in_cert" -eq 1 ] && cert="$cert
$line"
        ;;
    esac
  done < "$tmp"
  rm -f "$tmp"

  [ -z "$found" ] && return 1
  echo "$found"
}

write_client_config()
{
  mkdir -p "$DGM_HOME"
  {
    echo "DGM_URL=$DGM_URL"
    echo "DGM_CLONE_DIR=$DGM_CLONE_DIR"
  } > "$DGM_CONFIG_FILE"
  log "Saved current config to $DGM_CONFIG_FILE"
}

# cmd_ca never silently overwrites a CA that's already cached and trusted.
# - No cached CA yet (first trust): TOFU -- save it, show it. Nothing to
#   protect yet, so no gate and no temp file needed.
# - Cached CA matches what's presented now: no-op.
# - Cached CA differs from what's presented now: this is the one case
#   that's actually dangerous (MITM, or a legitimate but unannounced CA
#   rotation) -- always a hard stop unless -y or an explicit interactive
#   "yes". This is also the only case that needs a temp file, since the
#   existing cached CA must be compared against before it's overwritten.
# This function is only ever called two ways: explicitly via the "ca"
# command (may hit any of the three cases above), or automatically from
# ensure_ca() when NO CA is cached yet (the first case only) -- so a
# "pull"/"clone" can never silently walk into a mismatch on its own.

cmd_ca()
{
  local auto_yes=0
  case "$1" in
    -y|--yes) auto_yes=1 ;;
  esac

  require_dgm_url ca

  if ! dgm_is_https; then
    header "CA Trust"
    log "DGM_URL is http:// -- no CA needed for this mode."
    return 0
  fi

  header "Fetching Mirror CA Certificate"

  mkdir -p "$DGM_HOME"
  local out="$DGM_HOME/ca.crt"
  local cert=""

  cert="$(fetch_ca_openssl || true)"

  if [ -z "$cert" ]; then
    log_err "Failed to retrieve CA certificate from $DGM_URL via openssl"
    exit 1
  fi

  if [ -f "$out" ]; then

    # show_cert reads its argument multiple times (SAN, subject, issuer,
    # etc. are each a separate "openssl x509 -in ..." call), so comparing
    # against the newly presented cert needs a real file, not a pipe/fd.

    local presented_file existing_fp new_fp
    presented_file="$(mktemp "${TMPDIR:-/tmp}/dom-git-mirror-ca.XXXXXX")"
    echo "$cert" > "$presented_file"

    existing_fp="$(openssl x509 -noout -fingerprint -in "$out" 2>/dev/null)"
    new_fp="$(openssl x509 -noout -fingerprint -in "$presented_file" 2>/dev/null)"

    if [ "$existing_fp" = "$new_fp" ]; then
      log "CA presented by $DGM_URL matches the already-cached CA -- no change."
      header "Cached CA Certificate (unchanged)"
      show_cert "$out"
      rm -f "$presented_file"
      return 0
    fi

    local msg
    msg="$(printf 'The CA presented by %s does NOT match the cached CA at %s.\nThis means either the CA was legitimately rotated on the mirror, or this connection is being intercepted.\nCached CA fingerprint:\n  %s' "$DGM_URL" "$out" "$existing_fp")"
    log_err "$msg"
    header "Presented CA Certificate (MISMATCH -- not yet trusted)" >&2
    show_cert "$presented_file" >&2

    if [ "$auto_yes" != "1" ]; then
      if [ -t 0 ]; then
        local reply
        printf "Replace the cached CA with this one? Type 'yes' to confirm: "
        read -r reply
        if [ "$reply" != "yes" ]; then
          log_err "Not trusting the new CA. Aborting."
          rm -f "$presented_file"
          exit 1
        fi
      else
        log_err "Refusing to replace a cached CA non-interactively without -y. Aborting."
        rm -f "$presented_file"
        exit 1
      fi
    fi

    if ! mv "$presented_file" "$out"; then
      log_err "Failed to save CA certificate to $out"
      rm -f "$presented_file"
      exit 1
    fi
  else

    # First trust: TOFU. Save it directly, show it, then give anyone
    # watching a brief window to Ctrl+C before moving on -- there's
    # usually no TTY to prompt on ("curl | bash -s -- pull"), but a timed
    # pause still gives a real chance to notice and react. This is a
    # friendly heads-up, not a hard transactional gate (that's what the
    # mismatch case above is for) -- skipped entirely with -y.

    if ! echo "$cert" > "$out"; then
      log_err "Failed to save CA certificate to $out"
      exit 1
    fi
    show_cert "$out"

    if [ "$auto_yes" != "1" ]; then
      log "Trusting this CA in 10s -- Ctrl+C now to stop if you don't agree."
      sleep 10
    fi
  fi

  log "CA certificate saved to $out"

  write_client_config
}

ensure_ca()
{
  local ca_file="$DGM_HOME/ca.crt"
  if [ ! -f "$ca_file" ]; then

    # This only ever hits cmd_ca's first-trust (TOFU) path -- there's no
    # existing CA yet for it to compare against, so it just shows it and
    # pauses briefly (Ctrl+C to abort) rather than blocking on a typed
    # prompt, since there's usually no TTY here to prompt on anyway.

    cmd_ca >&2
  fi

  # Deliberately does NOT auto-regenerate a missing config file just
  # because the CA happens to be cached: the same trusted CA can be
  # legitimately reached via more than one address (real hostname,
  # 127.0.0.1, localhost -- all in the cert's SAN), so silently persisting
  # "whatever DGM_URL happened to be this run" would overwrite a real
  # saved mirror address with a one-off/loopback value. Config is only
  # ever written by a deliberate "ca" run or "cfg".

  echo "$ca_file"
}

# ---- client: clone / pull ----

ensure_local_script()
{
  local dest="$DGM_CLONE_DIR/dom-git-mirror.sh"
  if [ -f "$dest" ]; then
    return 0
  fi

  mkdir -p "$DGM_CLONE_DIR"

  # curl_mirror establishes/verifies the CA itself (see its own comment)
  # -- by the time this fetch happens, trust is already real, not "-k".
  # It also already redirects stdin from /dev/null (needed here for the
  # same reason it always is: when this whole script is itself running
  # via "curl ... | bash -s -- pull", stdin is the *same pipe* bash is
  # still reading the rest of this script from -- without that, curl can
  # consume bytes meant for later commands and silently truncate
  # execution right here).

  if curl_mirror "/setup.sh" "$dest"; then
    chmod 755 "$dest"
    log "Saved a local copy of dom-git-mirror.sh to $dest"
  else
    rm -f "$dest"
  fi
}

# Swaps the local dom-git-mirror.sh for whatever the mirror is currently
# serving: download to a temp file first, then move it over the target --
# "mv" onto an existing file is an atomic rename, so there's never a
# moment where $dest is missing or half-written.

cmd_update()
{
  require_dgm_url update

  header "Updating dom-git-mirror.sh"

  local dest="$DGM_CLONE_DIR/dom-git-mirror.sh"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/dom-git-mirror-update.XXXXXX")"

  if ! curl_mirror "/setup.sh" "$tmp"; then
    log_err "Failed to download the latest script from $DGM_URL"
    rm -f "$tmp"
    exit 1
  fi

  local remote_version msg
  remote_version="$(grep -m1 '^DGM_VERSION=' "$tmp" | cut -d'"' -f2)"
  msg="$(printf '%-16s: %s\n%-16s: %s' "Current version" "$DGM_VERSION" "Server version" "${remote_version:-unknown}")"
  log "$msg"

  if [ "$remote_version" = "$DGM_VERSION" ]; then
    log "Already up to date."
    rm -f "$tmp"
    return 0
  fi

  chmod 755 "$tmp"
  mkdir -p "$DGM_CLONE_DIR"
  mv "$tmp" "$dest"
  log "Updated $DGM_VERSION -> $remote_version"
}

clone_one()
{
  local url="$1" dest="$2" use_ca="$3"

  if [ -z "$dest" ]; then
    dest="$DGM_CLONE_DIR/$(basename "$url" .git)"
  fi

  header "Cloning: $dest"

  mkdir -p "$(dirname "$dest")"

  # --progress: git suppresses its normal progress output when it detects
  # it's not attached to a real TTY (e.g. running via "curl | bash"),
  # which otherwise looks like a silent hang during the clone.
  # </dev/null: same reasoning as ensure_local_script's curl call -- don't
  # let git inherit stdin that may still be feeding the rest of this
  # script when run via "curl ... | bash -s -- pull".

  if [ "$use_ca" = "1" ]; then
    local ca_file
    ca_file="$(ensure_ca)"
    GIT_SSL_CAINFO="$ca_file" git clone --progress "$url" "$dest" </dev/null
  else
    git clone --progress "$url" "$dest" </dev/null
  fi

  log "Cloned $dest (last commit: $(last_commit_date "$dest"))"
}

cmd_clone()
{
  require_dgm_url clone

  local dest="" all=0 args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dest) dest="$2"; shift ;;
      --all) all=1 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  local use_ca_default=0
  dgm_is_https && use_ca_default=1

  # Establish CA trust once, up front -- before any cloning starts -- so
  # it doesn't appear awkwardly nested inside the first repo's "Cloning:"
  # block. Only if we'll actually need it: http:// never does, and a
  # clone of only raw URLs (no known repo names) doesn't either.

  if dgm_is_https; then
    local needs_ca=0
    if [ "$all" = "1" ] || [ "${#args[@]}" -eq 0 ]; then
      needs_ca=1
    else
      local a
      for a in "${args[@]}"; do
        [ -n "$(repo_url "$a")" ] && needs_ca=1
      done
    fi
    [ "$needs_ca" = "1" ] && ensure_ca >/dev/null
  fi

  if [ "$all" = "1" ]; then
    local names
    names="$(remote_repo_names)"
    if [ -z "$names" ]; then
      log_err "Could not fetch repo list from $DGM_URL/status"
      exit 1
    fi
    mkdir -p "$DGM_HOME"
    echo "$names" > "$DGM_CLIENT_REPOS_FILE"
    local name
    for name in $names; do
      clone_one "$(build_repo_url "$name")" "$dest" "$use_ca_default"
    done

  elif [ "${#args[@]}" -eq 0 ]; then
    local name
    for name in $(client_repo_names); do
      clone_one "$(build_repo_url "$name")" "$dest" "$use_ca_default"
    done

  else
    local arg url use_ca
    for arg in "${args[@]}"; do
      if [ -n "$(repo_url "$arg")" ]; then
        url="$(build_repo_url "$arg")"
        use_ca="$use_ca_default"
      else
        url="$arg"
        use_ca=0
      fi
      clone_one "$url" "$dest" "$use_ca"
    done
  fi

  echo
}

pull_one()
{
  local name="$1"
  local dir="$DGM_CLONE_DIR/$name"

  if [ ! -d "$dir" ]; then
    local use_ca_default=0
    dgm_is_https && use_ca_default=1
    clone_one "$(build_repo_url "$name")" "$dir" "$use_ca_default"
    return
  fi

  local url
  url="$(build_repo_url "$name")"

  header "Pulling: $dir"

  if dgm_is_https; then
    local ca_file
    ca_file="$(ensure_ca)"
    ( cd "$dir" && GIT_SSL_CAINFO="$ca_file" git pull --progress "$url" </dev/null )
  else
    ( cd "$dir" && git pull --progress "$url" </dev/null )
  fi

  log "Pulled $dir (last commit: $(last_commit_date "$dir"))"
}

cmd_pull()
{
  if [ -f "$DGM_CLONE_DIR/dom-git-mirror.sh" ]; then
    header "Updating dom-git-mirror"
  else
    header "Installing dom-git-mirror"
  fi

  require_dgm_url pull

  ensure_local_script

  local all=0
  local args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  # Establish CA trust once, up front -- before any pulling/cloning
  # starts -- so it doesn't appear awkwardly nested inside the first
  # repo's own header.

  dgm_is_https && ensure_ca >/dev/null

  if [ "$all" = "1" ]; then
    local names
    names="$(remote_repo_names)"
    if [ -z "$names" ]; then
      log_err "Could not fetch repo list from $DGM_URL/status"
      exit 1
    fi
    mkdir -p "$DGM_HOME"
    echo "$names" > "$DGM_CLIENT_REPOS_FILE"
    local name
    for name in $names; do
      pull_one "$name"
    done
  elif [ "${#args[@]}" -eq 0 ]; then
    local name
    for name in $(client_repo_names); do
      pull_one "$name"
    done
  else
    local name
    for name in "${args[@]}"; do
      pull_one "$name"
    done
  fi

  echo
}

# ---- dispatch ----

main()
{
  local cmd="$1"
  [ "$#" -gt 0 ] && shift

  case "$cmd" in
    cert)    cmd_cert "$@" ;;
    start)   cmd_start "$@" ;;
    stop)    cmd_stop "$@" ;;
    restart) cmd_restart "$@" ;;
    logs)    cmd_logs "$@" ;;
    mirror)  cmd_mirror "$@" ;;
    ca)      cmd_ca "$@" ;;
    clone)   cmd_clone "$@" ;;
    pull)    cmd_pull "$@" ;;
    update)  cmd_update "$@" ;;
    ls)      cmd_ls "$@" ;;
    check)   cmd_check "$@" ;;
    server)  cmd_server "$@" ;;
    cfg)     cmd_cfg "$@" ;;
    env)     cmd_env "$@" ;;
    repos)   cmd_repos "$@" ;;
    version|--version|-v) echo "dom-git-mirror.sh v$DGM_VERSION" ;;
    help|--help|-h|"") usage ;;
    *)
      log_err "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
