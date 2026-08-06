#!/bin/bash
############################################################################
# dom-git-mirror.sh - internal git mirror helper (server + client commands)
#
# Copyright Nash!Com, Daniel Nashed 2026 - APACHE 2.0 see LICENSE
############################################################################

set -e

DGM_VERSION="0.9.11"

# Per-user client state: cached CA cert + persisted config. Kept separate
# from DGM_CLONE_DIR (the shared git checkouts) specifically because git
# repo ownership needs to stay consistent across runs -- a plain config/
# cert file has no such constraint, so it's fine per-user.

DGM_HOME="${DGM_HOME:-$HOME/.dom-git-mirror}"

# Any client-side setting can be persisted here (written by "ca" the first
# time trust is established with a mirror). Sourced early, before any of
# the defaults below, so precedence is: explicit env var > persisted
# config > hardcoded default.

DGM_CONFIG_FILE="$DGM_HOME/config"
if [ -f "$DGM_CONFIG_FILE" ]; then
  . "$DGM_CONFIG_FILE"
fi

# DGM_HOST is intentionally left unresolved here. Servers default to their
# own "hostname -f" (see cmd_cert -- needs the real FQDN, not just
# $HOSTNAME, since that's what goes into the cert's CN/SAN). Clients have
# no sensible default at all -- their own hostname is never the mirror's
# address -- so it must be set explicitly, or persisted via a prior "ca"
# run (see require_dgm_host).

DGM_HTTP_PORT="${DGM_HTTP_PORT:-8080}"
DGM_HTTPS_PORT="${DGM_HTTPS_PORT:-8443}"
DGM_BASE_DIR="${DGM_BASE_DIR:-/local/dom-git-mirror}"
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

# Known repos: "name=url" per line, any git host -- nothing here is
# GitHub-specific, "git clone --mirror" works the same against any of
# them. Add a repo by adding a line; no other change needed anywhere.
DGM_REPOS="domino-startscript=https://github.com/nashcom/domino-startscript.git
domino-container=https://github.com/HCL-TECH-SOFTWARE/domino-container.git"

repo_names()
{
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "${line%%=*}"
  done <<< "$DGM_REPOS"
}

repo_url()
{
  local name="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      "$name="*) echo "${line#*=}"; return 0 ;;
    esac
  done <<< "$DGM_REPOS"
  echo ""
}

build_repo_url()
{
  local name="$1"
  local scheme="https"
  local port="$DGM_HTTPS_PORT"
  if [ "$USE_HTTP" = "1" ]; then
    scheme="http"
    port="$DGM_HTTP_PORT"
  fi
  echo "$scheme://$DGM_HOST:$port/$name.git"
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
  printf "  %-${cw}s%s\n" "start" 'Bring the mirror container up (auto-runs "cert" first)'
  printf "  %-${cw}s%s\n" "stop" "Bring the mirror container down"
  printf "  %-${cw}s%s\n" "restart" "Stop then start"
  printf "  %-${cw}s%s\n" "status" "Show container status"
  printf "  %-${cw}s%s\n" "logs" "Show container logs"
  printf "  %-${cw}s%s\n" "mirror [name|url ...]" "Create/refresh git mirrors (default: all known repos)"
  echo

  echo "Run on any machine pulling from the mirror:"
  echo
  printf "  %-${cw}s%s\n" "ca" "Fetch/cache the mirror's CA cert (via openssl s_client)"
  printf "  %-${cw}s%s\n" "pull [name|url ...] [--http]" "Clone (if missing) or update repo(s) (default: all known repos)"
  printf "  %-${cw}s%s\n" "clone [name|url ...] [--dest DIR] [--http]" "Explicit clone, e.g. to a custom --dest"
  printf "  %-${cw}s%s\n" "update" "Swap the local script for the mirror's current version"
  printf "  %-${cw}s%s\n" "check" "Compare local checkouts against the mirror's /status by commit hash"
  echo

  echo "Works either side:"
  echo
  printf "  %-${cw}s%s\n" "ls" "List known repos with branch, last commit time + hash"
  echo

  echo "Known repos:"
  echo
  echo "  $(repo_names | tr '\n' ' ')"
  echo

  echo "Config:"
  print_delim
  printf "  %-16s %-26s %-26s\n" "ENV VAR" "DEFAULT" "CURRENT"
  printf "  %-16s %-26s %-26s\n" "DGM_HOST" "hostname -f (server only)" "${DGM_HOST:-<not set>}"
  printf "  %-16s %-26s %-26s\n" "DGM_HTTP_PORT" "8080" "$DGM_HTTP_PORT"
  printf "  %-16s %-26s %-26s\n" "DGM_HTTPS_PORT" "8443" "$DGM_HTTPS_PORT"
  printf "  %-16s %-26s %-26s\n" "DGM_BASE_DIR" "/local/dom-git-mirror" "$DGM_BASE_DIR"
  printf "  %-16s %-26s %-26s\n" "DGM_REPOS_DIR" "/local/git-mirror" "$DGM_REPOS_DIR"
  printf "  %-16s %-26s %-26s\n" "DGM_CLONE_DIR" "/local/github" "$DGM_CLONE_DIR"
  printf "  %-16s %-26s %-26s\n" "DGM_HOME" "\$HOME/.dom-git-mirror" "$DGM_HOME"
  printf "  %-16s %-26s %-26s\n" "DGM_CA_NAME" "git-mirror-ca" "$DGM_CA_NAME"
  echo

  local display_host="${DGM_HOST:-$(timeout 2 hostname -f 2>/dev/null || echo "$HOSTNAME")}"
  echo "Install on a new client:"
  echo
  echo "  export DGM_HOST=$display_host; curl -fsSL \"http://\$DGM_HOST:$DGM_HTTP_PORT/setup.sh\" | bash -s -- pull"
  echo

  print_delim
  echo
}

# ---- server: cert ----

show_cert()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  local SAN=$(openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | grep -E 'DNS:|IP Address:' | xargs )
  local SUBJECT=$(openssl x509 -in "$1" -noout -subject | cut -d '=' -f 2- )
  local ISSUER=$(openssl x509 -in "$1" -noout -issuer | cut -d '=' -f 2- )
  local EXPIRATION=$(openssl x509 -in "$1" -noout -enddate | cut -d '=' -f 2- )
  local FINGERPRINT=$(openssl x509 -in "$1" -noout -fingerprint | cut -d '=' -f 2- )
  local SERIAL=$(openssl x509 -in "$1" -noout -serial | cut -d '=' -f 2- )

  echo
  [ -n "$SAN" ] && printf "%-14s: %s\n" "SAN" "$SAN"
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

  local san="DNS:$DGM_HOST"
  [ "$DGM_HOST" != "localhost" ]  && san="$san,DNS:localhost"
  [ "$DGM_HOST" != "127.0.0.1" ]  && san="$san,IP:127.0.0.1"
  [ "$DGM_HOST" != "::1" ]        && san="$san,IP:::1"

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

  cmd_cert
  write_config_files
  mkdir -p "$DGM_REPOS_DIR"

  if [ -z "$(ls -A "$DGM_REPOS_DIR" 2>/dev/null)" ]; then
    log "No mirrors found under $DGM_REPOS_DIR -- mirroring known repos now"
    cmd_mirror
  fi

  # Serve the currently running copy at /setup.sh so clients have a single
  # file to bootstrap from (e.g. "curl .../setup.sh | DGM_HOST=<host> bash
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

cmd_status()
{
  require_docker

  write_config_files
  ( cd "$DGM_BASE_DIR" && docker compose ps )
}

cmd_logs()
{
  require_docker

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
  local base_dir="$1" suffix="$2"
  local name repo hash any=0

  for name in $(repo_names); do
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
  header "Known Repositories"

  local text found=0

  text="$(build_status_text "$DGM_REPOS_DIR" ".git")"
  if [ -n "$text" ]; then
    echo "Server mirrors ($DGM_REPOS_DIR):"
    echo
    echo "$text" | sed 's/^/  /'
    echo
    found=1
  fi

  text="$(build_status_text "$DGM_CLONE_DIR" "")"
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

# Compares local checkouts against the mirror's own /status (fetched live,
# plain HTTP -- it's a static file, no CA needed) by commit hash -- exact
# match or not, no timestamp normalization involved. Only makes sense
# client-side: the server has no visibility into what any given client has
# checked out, so this can't live in "ls"/"status" on that side. Shows both
# date and hash per side, so the SYNCED verdict is visually backed by the
# actual values it's computed from, not just asserted.
cmd_check()
{
  require_dgm_host check

  header "Checking Local Repos Against Mirror"

  local remote
  remote="$(curl -fsSL "http://$DGM_HOST:$DGM_HTTP_PORT/status" </dev/null 2>/dev/null)"

  if [ -z "$remote" ]; then
    log_err "Could not fetch status from $DGM_HOST:$DGM_HTTP_PORT/status"
    exit 1
  fi

  local name any=0
  for name in $(repo_names); do
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

require_dgm_host()
{
  if [ -z "$DGM_HOST" ]; then
    local msg
    msg="$(printf 'DGM_HOST is not set.\nThere is no default for a client -- your own hostname is never the mirror address.\nSet it explicitly, e.g.: DGM_HOST=<mirror-host> %s %s\nOnce set, running "ca" will remember it in %s for future runs.' "$0" "$*" "$DGM_CONFIG_FILE")"
    log_err "$msg"
    exit 1
  fi
}

fetch_ca_openssl()
{
  local tmp
  tmp="$(mktemp)"
  if ! openssl s_client -connect "$DGM_HOST:$DGM_HTTPS_PORT" -servername "$DGM_HOST" -showcerts </dev/null 2>/dev/null > "$tmp"; then
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
    echo "DGM_HOST=$DGM_HOST"
    echo "DGM_HTTP_PORT=$DGM_HTTP_PORT"
    echo "DGM_HTTPS_PORT=$DGM_HTTPS_PORT"
    echo "DGM_CLONE_DIR=$DGM_CLONE_DIR"
    echo "DGM_CA_NAME=$DGM_CA_NAME"
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

  require_dgm_host ca

  header "Fetching Mirror CA Certificate"

  mkdir -p "$DGM_HOME"
  local out="$DGM_HOME/ca.crt"
  local cert=""

  cert="$(fetch_ca_openssl || true)"

  if [ -z "$cert" ]; then
    log_err "Failed to retrieve CA certificate from $DGM_HOST:$DGM_HTTPS_PORT via openssl"
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
      log "CA presented by $DGM_HOST:$DGM_HTTPS_PORT matches the already-cached CA -- no change."
      header "Cached CA Certificate (unchanged)"
      show_cert "$out"
      rm -f "$presented_file"
      return 0
    fi

    local msg
    msg="$(printf 'The CA presented by %s:%s does NOT match the cached CA at %s.\nThis means either the CA was legitimately rotated on the mirror, or this connection is being intercepted.\nCached CA fingerprint:\n  %s' "$DGM_HOST" "$DGM_HTTPS_PORT" "$out" "$existing_fp")"
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
  elif [ ! -f "$DGM_CONFIG_FILE" ]; then
    # CA is already trusted -- just regenerate the persisted config,
    # never re-fetch/re-check the CA itself as a side effect of this.
    write_client_config >&2
  fi
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
  # </dev/null: don't let curl inherit our stdin. When this whole script is
  # itself running via "curl ... | bash -s -- pull", stdin is the *same
  # pipe* bash is still reading the rest of this script from -- without
  # this, curl can consume bytes meant for later commands and silently
  # truncate execution right here.
  if curl -fsSL "http://$DGM_HOST:$DGM_HTTP_PORT/setup.sh" -o "$dest" </dev/null 2>/dev/null; then
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
  require_dgm_host update

  header "Updating dom-git-mirror.sh"

  local dest="$DGM_CLONE_DIR/dom-git-mirror.sh"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/dom-git-mirror-update.XXXXXX")"

  if ! curl -fsSL "http://$DGM_HOST:$DGM_HTTP_PORT/setup.sh" -o "$tmp" </dev/null 2>/dev/null; then
    log_err "Failed to download the latest script from $DGM_HOST:$DGM_HTTP_PORT"
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
  if [ "$use_ca" = "1" ] && [ "$USE_HTTP" != "1" ]; then
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
  require_dgm_host clone

  USE_HTTP=0
  local dest="" args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --http) USE_HTTP=1 ;;
      --dest) dest="$2"; shift ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  # Establish CA trust once, up front -- before any cloning starts -- so
  # it doesn't appear awkwardly nested inside the first repo's "Cloning:"
  # block. Only if we'll actually need it: --http never does, and a
  # clone of only raw URLs (no known repo names) doesn't either.
  if [ "$USE_HTTP" != "1" ]; then
    local needs_ca=0
    if [ "${#args[@]}" -eq 0 ]; then
      needs_ca=1
    else
      local a
      for a in "${args[@]}"; do
        [ -n "$(repo_url "$a")" ] && needs_ca=1
      done
    fi
    [ "$needs_ca" = "1" ] && ensure_ca >/dev/null
  fi

  if [ "${#args[@]}" -eq 0 ]; then
    local name
    for name in $(repo_names); do
      clone_one "$(build_repo_url "$name")" "$dest" 1
    done
  else
    local arg url use_ca
    for arg in "${args[@]}"; do
      if [ -n "$(repo_url "$arg")" ]; then
        url="$(build_repo_url "$arg")"
        use_ca=1
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
    clone_one "$(build_repo_url "$name")" "$dir" 1
    return
  fi

  local url
  url="$(build_repo_url "$name")"

  header "Pulling: $dir"

  if [ "$USE_HTTP" != "1" ]; then
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

  require_dgm_host pull

  ensure_local_script

  USE_HTTP=0
  local args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --http) USE_HTTP=1 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  # Establish CA trust once, up front -- before any pulling/cloning
  # starts -- so it doesn't appear awkwardly nested inside the first
  # repo's own header.
  [ "$USE_HTTP" != "1" ] && ensure_ca >/dev/null

  if [ "${#args[@]}" -eq 0 ]; then
    local name
    for name in $(repo_names); do
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
    status)  cmd_status "$@" ;;
    logs)    cmd_logs "$@" ;;
    mirror)  cmd_mirror "$@" ;;
    ca)      cmd_ca "$@" ;;
    clone)   cmd_clone "$@" ;;
    pull)    cmd_pull "$@" ;;
    update)  cmd_update "$@" ;;
    ls)      cmd_ls "$@" ;;
    check)   cmd_check "$@" ;;
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

