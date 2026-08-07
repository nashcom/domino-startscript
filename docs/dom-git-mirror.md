---
layout: default
title: Git Mirror
nav_order: 9
description: "Internal Git mirror for restricted networks"
has_children: false
---

# dom-git-mirror

Consume GitHub repositories from air-gapped or firewalled internal networks.

One host with outbound access mirrors `domino-startscript` and `domino-container` over a private, TLS-secured
internal connection. Every other server pulls from that mirror instead of GitHub, with no internet access required.

One script provides both sides: it stands up the mirror service and is also the client tool every downstream server
uses to pull from it. There is nothing else to deploy -- `dom-git-mirror.sh` generates its own nginx config,
docker-compose definition, and private CA at runtime.

```text
                            Internet

                   +-----------------------+
                   |        GitHub         |
                   +-----------+-----------+
                               |
                               | HTTPS
                               v
                   +-----------------------+
                   |  Customer HTTP Proxy  |
                   +-----------+-----------+
                               |
                               | HTTPS / controlled outbound access
                               v

+-----------------------------------------------------------------------------------+
|                                Customer Network                                   |
|                                                                                   |
|                    +---------------------------------------+                      |
|                    |         dom-git-mirror host           |                      |
|                    |                                       |                      |
|                    |  +-------------------------------+    |                      |
|                    |  |   dom-git-mirror.sh mirror    |    |                      |
|                    |  +---------------+---------------+    |                      |
|                    |                  |                    |                      |
|                    |                  v                    |                      |
|                    |  +-------------------------------+    |                      |
|                    |  |       Bare Git Mirrors        |    |                      |
|                    |  +---------------+---------------+    |                      |
|                    |                  |                    |                      |
|                    |                  v                    |                      |
|                    |  +-------------------------------+    |                      |
|                    |  |      nginx HTTP / HTTPS       |    |                      |
|                    |  +---------------+---------------+    |                      |
|                    +------------------|--------------------+                      |
|                                       |                                           |
|                                       | Internal HTTP / HTTPS                     |
|                                       |                                           |
|                    +------------------+------------------+                        |
|                    |                                     |                        |
|                    v                                     v                        |
|      +-------------------------------+   +-------------------------------+        |
|      |     Domino / Build Server     |   |     Domino / Build Server     |        |
|      |                               |   |                               |        |
|      |   dom-git-mirror.sh pull      |   |   dom-git-mirror.sh pull      |        |
|      |               |               |   |               |               |        |
|      |               v               |   |               v               |        |
|      |        /local/github/         |   |        /local/github/         |        |
|      +-------------------------------+   +-------------------------------+        |
|                                                                                   |
+-----------------------------------------------------------------------------------+

```


## Requirements

- `docker` and `docker compose` (mirror host only)
- `openssl`, `git`, `bash`, `curl` (both sides)
- Outbound HTTPS to GitHub from the mirror host only (for `mirror`) -- downstream servers never need it. If that
  goes through a proxy, standard `http_proxy`/`https_proxy` env vars work as usual; `mirror` is just plain `git`
  underneath, nothing proxy-aware needs to be built into the script itself.

## Quick start

### On the mirror host

```
./dom-git-mirror.sh start     # generates/refreshes the CA+cert, mirrors known repos if none exist yet, brings up nginx
./dom-git-mirror.sh mirror    # clones domino-startscript + domino-container from GitHub (or refreshes them)
```

`start` finishes by printing a ready-to-copy install line for new clients, using the server's actual resolved
hostname (the same one baked into the TLS cert) -- no need to work it out separately.

Re-run `mirror` any time to refresh both repos (`git fetch --prune` under the hood once they already exist).

### On a new Domino/build server

One line, no prerequisites beyond `curl`/`bash`/`git`/`openssl` already being present. If your internal DNS resolves
`dom-git-mirror.<your domain>` to the mirror host, you don't even need the `export` -- it's guessed automatically:

```
export DGM_URL=https://<mirror-hostname>:8443
curl -fsSLk "$DGM_URL/setup.sh" | bash -s -- pull
```

The bootstrap `curl` above still needs an explicit address -- it has to know where to download the script from in
the first place. Automatic `DGM_URL` discovery kicks in once `dom-git-mirror.sh` is actually running on the client,
e.g. on every `pull` after this first one, so the `export` really is a one-time thing even without DNS convention.

This clones both repos into `/local/github/`, and along the way saves and `chmod`s a local, reusable copy of the
script into that same directory -- so every run after the first is just:

```
/local/github/dom-git-mirror.sh pull
```

The mirror also serves its version as plain text at `/version` (`curl -k "$DGM_URL/version"`), and an
inventory of every mirrored repo (branch, last commit time, commit hash -- regenerated on every `mirror`) at
`/status` (pipe-delimited: `name|branch|last_commit|commit_hash`) and `/status.json`. All are plain files in the
same webroot as `/setup.sh`, so no special nginx config is needed for any of them.
`dom-git-mirror.sh update` downloads the mirror's current script and atomically swaps it in for the local copy.

No env var needed at that point either: the first successful run remembers `DGM_URL` (see "How trust works" below).

## Commands

Run on the mirror host:

| Command                      | Does                                                                                                    |
|------------------------------|---------------------------------------------------------------------------------------------------------|
| `cert`                       | Generate/reuse the micro CA, always refresh the TLS leaf cert. Auto-run by `start` on every invocation. |
| `start [-ip]` / `stop` / `restart` | Manage the nginx mirror container.                                                                |
| `logs`                       | Show container logs.                                                                                    |
| `mirror [name\|url ...]`     | Create/refresh git mirrors. No args = both known repos.                                                 |
| `env`                        | Open the persisted server config in `$EDITOR`.                                                          |
| `repos`                      | Edit the known repos list in `$EDITOR`.                                                                 |

`-ip` on `start` prints the "Install on a new client" line using this host's detected primary IP instead of its
hostname. The cert already covers both (`localhost`/`127.0.0.1`/`::1`/default-route IP are always in the SAN
alongside the hostname), so this doesn't change what's trusted -- it only matters for ad-hoc setups with no DNS
record for the mirror, where printing the hostname would give a new client an address it can't actually resolve.

Run on any machine pulling from the mirror:

| Command                               | Does                                                                                |
|----------------------------------------|--------------------------------------------------------------------------------------|
| `ca`                                   | Fetch/cache the mirror's CA cert; persists config so future runs need no env vars.  |
| `pull [name\|url ...] [--all]`         | Clone (if missing) or update repo(s) from the mirror. No args = your known repos.   |
| `clone [name\|url ...] [--dest DIR] [--all]` | Explicit clone, e.g. to a custom destination.                                 |
| `update`                               | Swap the local dom-git-mirror.sh for the mirror's current version.                  |
| `check`                                | Compare local checkouts against the mirror's `/status` -- by commit hash, not date. |
| `server`                               | List repos on the mirror, fetched live -- no local checkout needed.                 |
| `cfg`                                  | Open the persisted client config in `$EDITOR`.                                      |

`DGM_URL`'s scheme decides the mode: `https://` uses the CA-trust flow below, `http://` skips it entirely --
there's no separate flag for this anymore, the URL already says which one you mean.

`repos`, `--all`, and the known-repos list format are covered in "Managing the repo list" below.

Works either side: `ls` lists known repos with branch, last commit time, and commit hash, reading whichever of
`DGM_REPOS_DIR`/`DGM_CLONE_DIR` actually has data.

`check` is the definitive in-sync check: it compares each local checkout's `HEAD` commit hash against the mirror's
`/status` for that repo -- exact match or not, no timestamp normalization involved. It shows both date and hash,
mirror vs. local, so the SYNCED verdict is visually backed by the actual values it's computed from, not just
asserted.

Other: `version` / `--version` / `-v` prints the script version, `help` / `--help` / `-h` prints full usage.

## How trust works

The mirror host generates its own private micro CA (`cert`) and signs a leaf TLS certificate with it, covering
`DGM_HOST`, `localhost`/`127.0.0.1`/`::1`, and the host's default-route IP (v4 and v6, whichever `ip route get`
resolves) -- deliberately not every IP on every interface, so Docker's own bridge networks and similar noise don't
end up in the SAN. This is deliberately an ad-hoc-friendly tool -- there's often no DNS record for the mirror at
all, so clients may well connect via a raw IP rather than a hostname; the cert needs to validate correctly for
whichever address actually
gets used, not just the one it happened to be generated with. nginx serves the **full chain** (leaf + CA), not just
the leaf.

Clients never need a copy of the CA cert handed to them out of band. `ca` (and `pull`/`clone`, which call it
automatically) opens `openssl s_client -showcerts` against the mirror's HTTPS port, pulls every certificate presented
during the handshake, and keeps whichever one is self-signed (subject == issuer) -- that's the CA. It's cached
locally at `$DGM_HOME/ca.crt` and used both as `GIT_SSL_CAINFO` for git operations and as `curl`'s `--cacert` for
every other fetch against the mirror (`/status` for `check`/`server`/`--all`, `/setup.sh` for the initial install and
`update`) -- nothing talks to the mirror over HTTPS unverified once a CA is cached. The one deliberate exception is
the very first bootstrap download itself (`curl .../setup.sh | bash -s -- pull` on a brand-new client) -- there's
genuinely no CA to verify against yet at that point, so that one connection is trust-on-first-use by necessity.

There is no static `/ca.crt` file served anywhere -- the cert is pulled live from the TLS connection itself, every
time it needs to be (re)fetched.

**This is trust-on-first-use (TOFU), not out-of-band-verified trust.** A client trusts whatever CA the configured
mirror presents on that first connection. What that first connection actually does, in order:

1. **No CA cached yet** -- the cert is fetched, saved, and shown (subject, fingerprint, expiration, etc.), then
   there's a 10-second pause ("Ctrl+C now to stop if you don't agree") before moving on. This is a heads-up, not a
   hard gate -- there's nothing cached yet to protect, and most runs have no TTY to prompt on (e.g.
   `curl | bash -s -- pull`) so blocking on typed input isn't an option.
2. **Cached CA matches what's presented now** -- no-op.
3. **Cached CA differs from what's presented now** -- this is the case that actually matters: either the mirror's
   CA was legitimately rotated, or this connection is being intercepted. It's always a hard stop -- an explicit
   `-y`/`--yes`, or a typed `yes` if interactive -- never a silent overwrite. Critically, `pull`/`clone`'s automatic
   CA fetch can only ever hit case 1: it only fetches when no CA is cached at all, so a routine `pull` can never
   silently walk into overwriting an already-trusted CA as a side effect.

For environments that need stronger assurance on that first connection, compare the fingerprint shown by `ca`
against the fingerprint shown on the mirror host itself (`show_cert`), out of band.

## Managing the repo list

The known-repos list (`domino-startscript`/`domino-container` by default) drives what `mirror` fetches on the server
and what `pull`/`clone` accept by name on either side.

**Format** -- one entry per line, two forms:

- `org/repo` -- GitHub shorthand, expands to `https://github.com/org/repo.git`; the local name is just the part
  after the last `/` (e.g. `nashcom/domino-startscript` becomes `domino-startscript`).
- `name|url` -- explicit, for any other git host, or to use a local name that doesn't match the upstream repo name.

Lines starting with `#` are comments and ignored.

**On the mirror host:** run `repos` to edit the list directly (`$DGM_BASE_DIR/repos.list`, opens in `$EDITOR`) --
created pre-populated with whatever the current list is. Unlike `cfg`/`env`, whose seed templates are all commented
out, this one starts active: a repo list is one cohesive thing to edit, not a set of independent overridable
defaults. Precedence: explicit `DGM_REPOS` env var > `repos.list` if present > the hardcoded default (the original
two repos). Changing the list doesn't retroactively mirror anything -- run `mirror` afterward to actually fetch any
newly-added entries.

**On a client:** a genuinely separate client has no access to the server's `repos.list` -- it only knows its own
local table (whatever shipped with its copy of the script) until it asks. `pull --all` / `clone --all` fetch the
mirror's *current* list live from `/status` and sync everything found there, including repos the client has never
seen before. This is deliberately opt-in: plain `pull`/`clone` (no args) never silently expands to whatever the
server currently has, so a repo added server-side doesn't unexpectedly start showing up on every client's next
routine run. `--all` also saves the discovered list to `$DGM_HOME/repos`, so it becomes the client's new default from
then on -- one `--all` run, then plain `pull` picks up the new repo without needing `--all` again.

`server` also fetches from `/status` live, purely for inspection -- no local checkout or disk access needed, and it
doesn't touch or update the client's own known-repos list the way `--all` does.

## Directory layout

```text
/local/dom-git-mirror/          DGM_BASE_DIR (server) -- generated config + TLS state
├── .env                        persisted server settings, written by "env"
├── repos.list                  known repos list, written by "repos"
├── tls/
│   ├── ca.key, ca.crt          micro CA -- generated once, reused until explicitly rotated (delete to rotate)
│   ├── tls.key, tls.crt        leaf cert -- refreshed on every "start"/"cert"
│   └── tls-fullchain.crt       leaf + CA, what nginx actually serves
├── nginx.conf                  regenerated from the script's embedded
└── docker-compose.yml          template on every start/stop/logs

/local/git-mirror/              DGM_REPOS_DIR (server) -- bare mirrors nginx serves
├── domino-startscript.git/
└── domino-container.git/

/local/github/                  DGM_CLONE_DIR (client) -- actual working checkouts
├── domino-startscript/
├── domino-container/
└── dom-git-mirror.sh           self-installed copy, saved + chmod'd by the first "pull"

~/.dom-git-mirror/               DGM_HOME (client, per-user) -- cached trust + persisted settings
├── ca.crt                      cached mirror CA cert
├── config                      persisted DGM_URL/DGM_CLONE_DIR, written by "ca" (or "cfg")
└── repos                       known repo names, written by "pull --all"/"clone --all"
```

`DGM_HOME` is kept separate from `DGM_CLONE_DIR` specifically because git repo ownership needs to stay consistent
across runs; a plain cert/config file has no such constraint, so it's fine to be per-user. All four locations are
plain absolute paths, independent of wherever the *running* `dom-git-mirror.sh` was invoked from -- on the mirror
host, keep it in its own working copy of `domino-startscript`, separate from this generated state.

## Configuration (env vars)

Server-side (mirror host only):

| Var              | Meaning                                      | Default                     |
|-------------------|-------------------------------------------------|---------------------------------|
| `DGM_HOST`       | Mirror hostname, goes into the cert's CN/SAN | `hostname -f` (2s timeout)  |
| `DGM_HTTP_PORT`  | HTTP port                                    | `8080`                      |
| `DGM_HTTPS_PORT` | HTTPS port                                   | `8443`                      |
| `DGM_BASE_DIR`   | Server-side state dir (config + TLS)         | `/local/dom-git-mirror`     |
| `DGM_REPOS_DIR`  | Server-side bare mirrors                     | `/local/git-mirror`         |
| `DGM_CA_NAME`    | CA common name                               | `git-mirror-ca`             |
| `DGM_REPOS`      | Known repos list, one per line               | `repos.list` if present, else the two defaults below |

Client-side (any machine pulling from the mirror):

| Var             | Meaning                                | Default                                                                       |
|------------------|-------------------------------------------|------------------------------------------------------------------------------|
| `DGM_URL`       | Full mirror URL, scheme + host + port  | `https://dom-git-mirror.<your domain>:8443` if that resolves, else must be set |
| `DGM_CLONE_DIR` | Client-side checkout dir               | `/local/github`                                                               |
| `DGM_HOME`      | Client-side trust/config dir           | `$HOME/.dom-git-mirror`                                                       |

`DGM_URL` must include an explicit scheme (`https://` or `http://`); the port can be omitted if it's the scheme's
standard one (`443`/`80`), same as any normal URL -- otherwise spell it out, e.g. `https://mirror.example.com:8443`.
If it isn't set and can't be guessed (no domain on this host), `ca`/`pull`/`clone`/`update`/`check` all error out
clearly rather than guessing wrong or hanging. Run `./dom-git-mirror.sh help` at any time to see both tables
populated with the defaults and whatever is currently in effect.

## Notices

`check`'s SYNCED verdict compares commit hashes only -- it doesn't currently compare branches. A fresh `clone`/`pull`
always lands on the same branch as the mirror (git follows the mirror's `HEAD`, same as cloning any repo normally),
so this only matters if a checkout is later switched to a different branch by hand (`git checkout <other-branch>`
inside `$DGM_CLONE_DIR/<repo>`). In that case `check` will report a hash mismatch as `NO -- run pull`, which isn't
quite accurate -- the checkout isn't behind, it's just tracking a different branch than the mirror's default.

