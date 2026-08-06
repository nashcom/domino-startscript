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

Re-run `mirror` any time to refresh both repos (`git fetch --prune` under the hood once they already exist).

### On a new Domino/build server

One line, no prerequisites beyond `curl`/`bash`/`git`/`openssl` already being present:

```
export DGM_HOST=<mirror-hostname>
curl -fsSL "http://$DGM_HOST:8080/setup.sh" | bash -s -- pull
```

This clones both repos into `/local/github/`, and along the way saves and `chmod`s a local, reusable copy of the
script into that same directory -- so every run after the first is just:

```
/local/github/dom-git-mirror.sh pull
```

The mirror also serves its version as plain text at `/version` (`curl http://$DGM_HOST:8080/version`), and an
inventory of every mirrored repo (branch, last commit time, commit hash -- regenerated on every `mirror`) at
`/status` (pipe-delimited: `name|branch|last_commit|commit_hash`) and `/status.json`. All are plain files in the
same webroot as `/setup.sh`, so no special nginx config is needed for any of them.
`dom-git-mirror.sh update` downloads the mirror's current script and atomically swaps it in for the local copy.

No env var needed at that point either: the first successful run remembers `DGM_HOST` (see "How trust works" below).

## Commands

Run on the mirror host:

| Command                      | Does                                                                                                    |
|------------------------------|---------------------------------------------------------------------------------------------------------|
| `cert`                       | Generate/reuse the micro CA, always refresh the TLS leaf cert. Auto-run by `start` on every invocation. |
| `start` / `stop` / `restart` | Manage the nginx mirror container.                                                                      |
| `status` / `logs`            | Show container status / logs.                                                                           |
| `mirror [name\|url ...]`     | Create/refresh git mirrors. No args = both known repos.                                                 |

Run on any machine pulling from the mirror:

| Command                                       | Does                                                                               |
|-----------------------------------------------|------------------------------------------------------------------------------------|
| `ca`                                          | Fetch/cache the mirror's CA cert; persists config so future runs need no env vars. |
| `pull [name\|url ...] [--http]`               | Clone (if missing) or update repo(s) from the mirror. No args = both known repos.  |
| `clone [name\|url ...] [--dest DIR] [--http]` | Explicit clone, e.g. to a custom destination.                                      |
| `update`                                      | Swap the local dom-git-mirror.sh for the mirror's current version.                 |
| `check`                                       | Compare local checkouts against the mirror's `/status` -- by commit hash, not date. |

Works either side: `ls` lists known repos with branch, last commit time, and commit hash, reading whichever of
`DGM_REPOS_DIR`/`DGM_CLONE_DIR` actually has data.

`check` is the definitive in-sync check: it compares each local checkout's `HEAD` commit hash against the mirror's
`/status` for that repo -- exact match or not, no timestamp normalization involved. It shows both date and hash,
mirror vs. local, so the SYNCED verdict is visually backed by the actual values it's computed from, not just
asserted.

Other: `version` / `--version` / `-v` prints the script version, `help` / `--help` / `-h` prints full usage.

Known repos: `domino-startscript`, `domino-container` (see `DGM_REPOS` in the script to add more -- any git host
works, nothing is GitHub-specific).

## How trust works

The mirror host generates its own private micro CA (`cert`) and signs a leaf TLS certificate with it, covering
`DGM_HOST` plus `localhost`/`127.0.0.1`/`::1`. nginx serves the **full chain** (leaf + CA), not just the leaf.

Clients never need a copy of the CA cert handed to them out of band. `ca` (and `pull`/`clone`, which call it
automatically) opens `openssl s_client -showcerts` against the mirror's HTTPS port, pulls every certificate presented
during the handshake, and keeps whichever one is self-signed (subject == issuer) -- that's the CA. It's cached
locally at `$DGM_HOME/ca.crt` and used as `GIT_SSL_CAINFO` for all subsequent git operations against the mirror.

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

## Directory layout

```text
/local/dom-git-mirror/          DGM_BASE_DIR (server) -- generated config + TLS state
├── tls/
│   ├── ca.key, ca.crt          micro CA -- generated once, reused until explicitly rotated (delete to rotate)
│   ├── tls.key, tls.crt        leaf cert -- refreshed on every "start"/"cert"
│   └── tls-fullchain.crt       leaf + CA, what nginx actually serves
├── nginx.conf                  regenerated from the script's embedded
└── docker-compose.yml          template on every start/stop/status/logs

/local/git-mirror/              DGM_REPOS_DIR (server) -- bare mirrors nginx serves
├── domino-startscript.git/
└── domino-container.git/

/local/github/                  DGM_CLONE_DIR (client) -- actual working checkouts
├── domino-startscript/
├── domino-container/
└── dom-git-mirror.sh           self-installed copy, saved + chmod'd by the first "pull"

~/.dom-git-mirror/               DGM_HOME (client, per-user) -- cached trust + persisted settings
├── ca.crt                      cached mirror CA cert
└── config                      persisted DGM_HOST/ports/etc, written by "ca"
```

`DGM_HOME` is kept separate from `DGM_CLONE_DIR` specifically because git repo ownership needs to stay consistent
across runs; a plain cert/config file has no such constraint, so it's fine to be per-user. All four locations are
plain absolute paths, independent of wherever the *running* `dom-git-mirror.sh` was invoked from -- on the mirror
host, keep it in its own working copy of `domino-startscript`, separate from this generated state.

## Configuration (env vars)

| Var              | Meaning                              | Default                                                       |
|------------------|---------------------------------------|-----------------------------------------------------------------|
| `DGM_HOST`       | Mirror hostname                      | server: `hostname -f` (2s timeout); client: none, must be set |
| `DGM_HTTP_PORT`  | HTTP port                            | `8080`                                                        |
| `DGM_HTTPS_PORT` | HTTPS port                           | `8443`                                                        |
| `DGM_BASE_DIR`   | Server-side state dir (config + TLS) | `/local/dom-git-mirror`                                       |
| `DGM_REPOS_DIR`  | Server-side bare mirrors             | `/local/git-mirror`                                           |
| `DGM_CLONE_DIR`  | Client-side checkout dir             | `/local/github`                                               |
| `DGM_HOME`       | Client-side trust/config dir         | `$HOME/.dom-git-mirror`                                       |
| `DGM_CA_NAME`    | CA common name                       | `git-mirror-ca`                                               |

`DGM_HOST` has no sensible default on a client -- its own hostname is never the mirror's address -- so `ca`/`pull`/
`clone` error out clearly if it isn't set and hasn't been persisted yet. On the server, `cert` resolves it from
`hostname -f` (needs the real FQDN for the cert's CN/SAN to be reachable from outside the host's own view of
itself). Run `./dom-git-mirror.sh help` at any time to see this table populated with both the defaults and whatever
is currently in effect.

