---
layout: default
title: Containers Without Internet
nav_order: 10
description: "Corporate architecture for building and running containers without direct Internet access"
has_children: false
---

# Building and Running Containers Without Direct Internet Access

**TL;DR**

* Replace external dependencies (Git, OCI images, Ubuntu packages, vendor software) with internal equivalents — see [Architecture Overview](#architecture-overview).
* Split responsibilities into synchronization, build, and runtime zones so only synchronization ever touches the Internet — see [Synchronization, Build and Runtime](#synchronization-build-and-runtime).

Container environments often assume that servers can directly access Internet resources such as [GitHub](https://github.com/), public container registries, Linux package repositories, and software download portals.
This assumption does not work well in most corporate environments, where build and runtime servers might have restricted Internet access, require complex proxy configurations, or have no Internet connectivity at all.

Instead of configuring every server and every build process to access external services through a proxy, a cleaner approach is to provide all required resources through internal corporate services.
The goal of this architecture is simple:

> **Build and runtime servers should only need access to internal corporate services. They should not require direct Internet access or an Internet proxy.**

This document describes the components required to implement such an environment and uses an [HCL Domino](https://www.hcl-software.com/domino) container deployment as a practical example.
The same concepts apply to many other containerized applications.

## Contents

- [Architecture Overview](#architecture-overview)
- [External Dependencies](#external-dependencies)
- [Git Repositories](#git-repositories)
- [Container Images](#container-images)
- [Prebuilt Third-Party Images](#prebuilt-third-party-images)
- [Ubuntu Package Mirror](#ubuntu-package-mirror)
- [Corporate Ubuntu Base Image](#corporate-ubuntu-base-image)
- [Build Proxy Configuration](#build-proxy-configuration)
- [Corporate Root Certificates](#corporate-root-certificates)
- [Vendor Software Installation Media](#vendor-software-installation-media)
- [Three Container Deployment Cases](#three-container-deployment-cases)
- [HCL Domino Example](#hcl-domino-example)
- [Build Server Requirements](#build-server-requirements)
- [Runtime Server Requirements](#runtime-server-requirements)
- [Synchronization, Build and Runtime](#synchronization-build-and-runtime)
- [Why Not Just Configure an Internet Proxy?](#why-not-just-configure-an-internet-proxy)
- [Reproducibility](#reproducibility)
- [Security Benefits](#security-benefits)
- [Air-Gapped Environments](#air-gapped-environments)
- [Recommended Corporate Model](#recommended-corporate-model)
- [Summary](#summary)

## Architecture Overview

A container build can depend on several completely different types of external resources:

* Git repositories
* OCI/container images
* Operating system packages
* Vendor software installation media

Each external dependency should have an internal equivalent.

```text
                              INTERNET
                                 |
                    controlled synchronization
                                 |
       +-----------------+-------+-------+-----------------+
       |                 |               |                 |
       v                 v               v                 v
    GitHub          OCI Registries     Ubuntu          MyHCL Software
       |                 |            Repositories         (MHS)
       |                 |               |                 |
       v                 v               v                 v
 Gitea Mirror /        Harbor        Ubuntu Mirror    Download Server
 dom-git-mirror
       |                 |               |                 |
       +-----------------+-------+-------+-----------------+
                                 |
                         CORPORATE NETWORK
                                 |
                    +------------+------------+
                    |                         |
                    v                         v
                Build Server              Runtime Server
                    |                         |
                    | no Internet             | no Internet
                    | no Internet proxy       | no Internet proxy
                    |                         |
                    v                         v
              Internal resources         Internal images
```

The build server is where this actually matters most.
Without this architecture, it is the server that would otherwise need direct or proxied Internet access — to clone Git repositories, pull base images, install packages, and download vendor software.

With internal services in place, it draws on those same resources internally instead.
The runtime server is usually much simpler from a software-supply perspective: it primarily needs the finished image from Harbor rather than access to build-time sources.
The systems synchronizing external resources into the corporate network are the only ones that need controlled Internet access at all.

## External Dependencies

The first step is to identify everything a container build obtains from outside the organization.
For a typical project these dependencies fall into four main categories.

| External dependency          | Internal service                 |
| ---------------------------- | -------------------------------- |
| Git repositories             | Gitea mirror or `dom-git-mirror` |
| OCI/container images         | Harbor                           |
| [Ubuntu](https://ubuntu.com/) packages | Internal Ubuntu mirror           |
| Vendor installation software | Internal download server         |

Normal infrastructure services such as DNS, NTP and PKI should also be available internally.
The important architectural principle is that the build system consumes only these internal services.

## Git Repositories

Container projects often depend on source code or configuration stored in public Git repositories.
A build server should not have to clone those repositories directly from GitHub.
Instead, repositories can be synchronized into the corporate network.

```text
GitHub
   |
   v
Internal Git Mirror
   |
   v
Build Server
```

There are several ways to implement this.

### Gitea

Organizations already operating [Gitea](https://docs.gitea.com/) can use its repository mirroring functionality.
This provides a full internal Git service and is a good solution when many repositories, developers, or projects need internal Git access.

The resulting build process uses only the internal Git service. For example:

```text
https://git.example.com/project/repository.git
```

instead of:

```text
https://github.com/organization/repository.git
```

Gitea can also store container images (Gitea Packages), which is enough for small environments.
It is storage only, though — there is no pull-through/proxy mode, so images have to be pushed in deliberately.
See [Container Images](#container-images) below for how that compares to Harbor.

### dom-git-mirror

For environments that only need to make a small number of public Git repositories available internally, deploying a complete Git platform might be unnecessary.
[`dom-git-mirror`](dom-git-mirror/dom-git-mirror.md) provides a lightweight alternative.

It periodically mirrors configured GitHub repositories and makes them available through an internal HTTP/HTTPS server.
This can be particularly useful for infrastructure repositories such as:

```text
domino-container
domino-startscript
```

If an organization already operates Gitea, [GitLab](https://about.gitlab.com/), or another suitable Git platform, that existing infrastructure should normally be used.
`dom-git-mirror` is intended for environments where a small and simple Git mirror is sufficient.

## Container Images

Container builds and runtime environments commonly obtain images from public OCI registries. Examples include:

```text
Docker Hub
GitHub Container Registry
Vendor registries
```

Corporate environments should normally use an internal OCI registry. Which one depends on scale, the same way [Git Repositories](#git-repositories) distinguishes a full platform from a lightweight mirror.

### Harbor

[Harbor](https://goharbor.io/docs/) is a common and well-supported choice whenever a proper internal registry is needed.

```text
Public OCI Registries
         |
         v
       Harbor
         |
      +--+------------------+
      |                     |
      v                     v
 Build Server          Runtime Server
      |
      | internally built images
      +-----------> Harbor
```

Harbor performs two important functions: it provides internally controlled copies of external images, and it stores images built by the organization.
The runtime environment therefore only needs access to Harbor, for example:

```text
registry.example.com/library/ubuntu:26.04
registry.example.com/domino/domino:14.5.1
```

The runtime server does not need access to [Docker Hub](https://hub.docker.com/), [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), or any other external OCI registry.
Harbor's **Proxy Cache** project type can also act as a pull-through cache for an upstream registry: the first pull fetches and caches the image, later pulls are served locally.
This is usually enough on its own and avoids adding a separate proxy tool. Organizations that already
run [Sonatype Nexus Repository](https://www.sonatype.com/products/sonatype-nexus-repository) for other artifact types can use its Docker/OCI proxy repositories for the same purpose instead of introducing Harbor.

### Gitea (Small Environments)

Smaller environments that already run Gitea for source and only need a handful of images do not necessarily need to stand up Harbor as well.
Gitea Packages can serve as the registry directly, but it has no pull-through/proxy mode, so the required images
(a corporate Ubuntu base, the Domino image, perhaps one or two more) are pulled on the build host, tested, and pushed to Gitea only when needed:

```text
docker pull ubuntu:26.04
# test the image on the build host
docker tag ubuntu:26.04 git.example.com/library/ubuntu:26.04
docker push git.example.com/library/ubuntu:26.04
```

This trades away Harbor's proxy cache, vulnerability scanning, and content-trust automation, but for a handful of static images
that is often no real loss — it is the same manual curation already used for [vendor installation media](#vendor-software-installation-media) elsewhere in this document.
An organization that outgrows a handful of images, or that needs scanning and signing, should move to Harbor.

## Prebuilt Third-Party Images

Many applications already provide ready-to-run container images. In this case there is no reason for the runtime server to access the Internet.
The image is transferred or synchronized into Harbor once.

```text
Vendor OCI Registry
         |
         v
 Corporate Harbor
         |
         v
   Runtime Server
```

There is no application build process, and therefore also no dependency on Git repositories or Ubuntu package mirrors during deployment.
This is the simplest case. The organization controls which external image versions are imported into Harbor, and runtime servers consume only those approved internal images.

## Ubuntu Package Mirror

Container builds frequently contain commands such as:

```dockerfile
RUN apt-get update && \
    apt-get install -y curl unzip ...
```

Even if the source repository and base image are available internally, this command normally contacts public Ubuntu repositories, for example:

```text
archive.ubuntu.com
security.ubuntu.com
```

A corporate build environment should instead provide an internal Ubuntu mirror.

```text
Ubuntu Repositories
        |
        v
Corporate Ubuntu Mirror
        |
        v
   Build Server
```

The build process must therefore support replacing the default Ubuntu repository configuration with the corporate mirror, and this should be an explicit configuration option.
Hijacking public Ubuntu DNS names and resolving them to an internal server is generally not a good solution and might not even be possible in many corporate environments.
The build should explicitly know that it is using a corporate repository.

## Corporate Ubuntu Base Image

Organizations developing multiple container applications should consider maintaining their own corporate Ubuntu base image. Instead of every application starting with:

```dockerfile
FROM ubuntu:26.04
```

applications could use:

```dockerfile
FROM registry.example.com/base/ubuntu:26.04
```

The corporate base image can contain organization-specific configuration such as:

* Corporate trusted root certificates
* Internal Ubuntu repository configuration
* Standard operating system configuration
* Required security settings
* Other corporate baseline configuration

The model then becomes:

```text
Official Ubuntu Image
         |
         v
Corporate Ubuntu Base Image <---- Corporate Root CA
         ^
         |
   Ubuntu Mirror
         |
         v
       Harbor
         |
         v
 Application Build
         |
         v
       Harbor
```

This creates a useful organizational boundary: the infrastructure or platform team owns the corporate base image,
and application teams build on top of it without needing to implement the same corporate repository and certificate configuration independently.

## Build Proxy Configuration

Proxy configuration is different from repository and certificate configuration.
A proxy normally belongs to the **build environment**, not to the resulting container image.

If Internet access through a proxy is required during a synchronization or build stage, proxy information should therefore normally be supplied as build-time environment information.
Typical variables include:

```text
HTTP_PROXY
HTTPS_PROXY
NO_PROXY
```

Proxy information should generally not be permanently embedded into a container image.
More importantly, the architecture described in this document attempts to eliminate the need for an Internet proxy on application build systems altogether.

> Once all required resources are available internally, the application build server should not require an Internet proxy.

## Corporate Root Certificates

Corporate environments often use an internal PKI or TLS inspection infrastructure, so container builds need a supported mechanism for adding trusted corporate root certificates.
There are two common approaches.

### Corporate Base Image

The preferred general solution is to include the corporate trust anchors in the organization-maintained base image.
Applications inheriting from that image automatically use the corporate trust configuration.

### Project-Provided Trust Configuration

Projects that build directly from a standard Ubuntu image should provide a documented mechanism for adding corporate trusted root certificates.
A project intended to operate in corporate environments should therefore ideally provide configuration for both:

* Internal Ubuntu mirrors
* Additional trusted root certificates

This allows the project to operate in restricted corporate environments even when the organization does not maintain its own Ubuntu base image.

## Vendor Software Installation Media

Some container images cannot be built entirely from publicly available resources: commercial software often requires separately downloaded installation packages, and HCL Domino is an example.

The Domino installation software is obtained through **[MyHCL Software (MHS)](https://my.hcltechsw.com/)**.
A restricted build server should not need direct access to MHS — instead, the required software should be downloaded through an approved system and made available through an internal download server.

```text
MyHCL Software (MHS)
         |
         v
   Download Server
         |
         v
 Domino Build Server
```

The download server does not replace the customer's HCL software entitlement.
It provides a controlled mechanism for transferring software the organization is entitled to use into the internal build environment.
The customer still obtains and uses Domino according to their HCL entitlement — the internal download infrastructure only changes how the installation media reaches the build environment.

## Three Container Deployment Cases

It is useful to distinguish three fundamentally different situations.

### 1. Prebuilt Third-Party Image

The vendor already provides the finished container image.

```text
Vendor Registry
      |
      v
    Harbor
      |
      v
Runtime Server
```

No application build is required. The image is imported into Harbor and deployed from there, and the runtime server requires no Internet connectivity.

### 2. Internally Developed Application

The organization builds its own application. The preferred approach is to use the corporate base image.

```text
Corporate Ubuntu Base Image
             |
             v
      Application Build
             |
             v
           Harbor
             |
             v
       Runtime Server
```

The corporate base image already contains the organization's package repository and trust configuration.

### 3. Project Builds From a Standard Ubuntu Image

Some external projects provide a container build but expect to start with a standard Ubuntu image.
In this case the project should support the corporate environment explicitly.

```text
Ubuntu Base Image --------+
                          |
Internal Ubuntu Mirror ---+
                          |
Corporate Root CA --------+---> Application Build
                          |
Internal Git -------------+
                                  |
                                  v
                                Harbor
```

At minimum, such a project should provide mechanisms for:

* Selecting an internal Ubuntu mirror
* Adding trusted corporate root certificates
* Selecting internal OCI image sources where required

This allows the project to integrate into corporate infrastructure without requiring DNS tricks or hard-coded Internet access.

## HCL Domino Example

HCL Domino provides a useful real-world example because building a Domino container image involves several different types of resources.
A corporate Domino build can use:

* An internal Git service for the Domino container repositories
* Harbor for base images and resulting Domino images
* An internal Ubuntu mirror for operating system packages
* An internal download server for Domino installation media obtained from MyHCL Software

```text
 Internal Git --------------------+
 Gitea / dom-git-mirror           |
                                  |
 Harbor --------------------------+
 Base Images                      |
                                  |
 Ubuntu Mirror -------------------+----> Domino Container Build
                                  |                |
 Download Server -----------------+                |
 Domino software from MHS                          |
                                                   v
                                          Domino Container Image
                                                   |
                                                   v
                                                Harbor
                                                   |
                                                   v
                                          Domino Runtime Server
```

The Domino build server does not need to know how those resources originally entered the organization — it only knows about internal services.

## Build Server Requirements

With all required infrastructure in place, the build server only needs access to a small set of internal services.

```text
                     Build Server
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
    Internal Git        Harbor       Ubuntu Mirror
          |
          |
          +-------------------------------+
                                          |
                                          v
                                  Download Server

Additional infrastructure:

    Corporate DNS
    Corporate NTP
    Corporate PKI
```

It does **not** require access to:

```text
GitHub
Docker Hub
GitHub Container Registry
archive.ubuntu.com
security.ubuntu.com
MyHCL Software
Internet proxy
general Internet access
```

This dramatically simplifies firewall and proxy requirements.

## Runtime Server Requirements

The runtime environment is even simpler.
Once the application image has been built and published to Harbor, most build-time infrastructure is no longer required.

```text
                         Harbor
                            |
                            v
                    Runtime Server
                     /     |     \
                    /      |      \
                   v       v       v
                 DNS      NTP     PKI
```

The runtime server does not need access to:

```text
GitHub
Internal Git
Ubuntu Mirror
MyHCL Software
Download Server
Docker Hub
Public OCI registries
Internet proxy
```

It primarily needs Harbor plus whatever internal application services the workload itself requires.
This separation also reduces the attack surface of production systems.

## Synchronization, Build and Runtime

The architecture can be divided into three security zones or responsibilities.

```text
                        INTERNET
                           |
                           v
                +----------------------+
                | Synchronization      |
                |                      |
                | Git                  |
                | OCI images           |
                | Ubuntu packages      |
                | Vendor software      |
                +----------+-----------+
                           |
                           v
                +----------------------+
                | Build Environment    |
                |                      |
                | No Internet          |
                | No Internet proxy    |
                +----------+-----------+
                           |
                           v
                       Harbor
                           |
                           v
                +----------------------+
                | Runtime Environment  |
                |                      |
                | No Internet          |
                | No Internet proxy    |
                +----------------------+
```

### Synchronization Layer

This layer is responsible for bringing approved external resources into the organization, and it might have controlled Internet or proxy access. Examples include:

* Git repository synchronization
* OCI image synchronization
* Ubuntu repository synchronization
* MyHCL Software downloads

This is where Internet connectivity belongs.

### Build Environment

The build environment consumes only internal resources.
It does not require Internet access, and it produces organization-approved container images and publishes them to Harbor.

### Runtime Environment

The runtime environment consumes approved images from Harbor.
It has no reason to access source repositories, public package repositories, software portals, or public OCI registries. This creates a clear supply-chain boundary.

## Why Not Just Configure an Internet Proxy?

A common solution is to give every build server access to an Internet proxy.
That works, but it moves Internet dependency into every build environment. Each build then potentially needs to understand:

* Proxy configuration
* Proxy authentication
* TLS inspection
* Corporate trusted root certificates
* External repository availability
* External registry availability
* Firewall rules

It also means that an external change or outage can unexpectedly break an internal build.

The traditional model looks like this:

```text
                  Build Server
                       |
                       v
                Corporate Proxy
                       |
       +---------------+---------------+
       |               |               |
       v               v               v
    GitHub         Docker Hub         Ubuntu
                                       ...
```

Using internal services changes the model:

```text
                  Build Server
                       |
       +---------------+---------------+
       |               |               |
       v               v               v
 Internal Git        Harbor       Ubuntu Mirror
                                       |
                                       v
                                Download Server
```

The build server doesn't need to understand how any of those resources reached the corporate network.
This is simpler, more deterministic, and easier to secure.

## Reproducibility

An additional advantage of internal mirrors and registries is reproducibility: a build should not unexpectedly change because an external image, repository, or package changed.
Organizations can control:

* Which Git revisions are available
* Which OCI images are approved
* Which Ubuntu packages are available
* Which vendor software versions are available

This also makes it possible to rebuild older application versions without depending on external services still providing exactly the same resources.
Where practical, builds should reference explicit versions, tags, or image digests rather than floating versions such as `latest`.

## Security Benefits

Removing direct Internet access from build and runtime servers provides several security advantages.

### Reduced Attack Surface

Production systems do not need general outbound Internet connectivity.
A compromised runtime container cannot simply use the host's normal Internet path because there does not need to be one.

### Controlled Software Ingress

External software enters the organization through known synchronization points, which makes it much easier to define and audit where software comes from.

### Centralized Scanning

Harbor and other internal infrastructure can scan or validate artifacts before they are used.
This includes vulnerability scanning (for example [Trivy](https://trivy.dev/)) and image signing or content trust
(for example [Cosign](https://docs.sigstore.dev/cosign/overview/) or [Notation](https://notaryproject.dev/)), so images are both checked and provenance-verifiable before they ever reach a runtime server.

### Better Auditing

The organization can identify which external resources have been imported and which internal systems consume them.

### Separation of Responsibilities

Platform teams can manage base images, package mirrors, registries and trust configuration independently from application teams.

### Smaller Firewall Rules

Build and runtime systems only need access to known internal services instead of broad Internet destinations.

## Air-Gapped Environments

The architecture described here does not require the environment to be completely air-gapped.
In many organizations, synchronization systems have controlled outbound Internet access while build and runtime environments do not.
However, the same architecture also works in a truly air-gapped environment — the only difference is how resources enter the corporate environment.

A connected environment might use:

```text
Internet
   |
   v
Controlled Synchronization
   |
   v
Corporate Network
```

A truly air-gapped environment might use:

```text
Internet Environment
        |
        | approved export
        |
        v
  Transfer Process
        |
        | approved import
        |
        v
Air-Gapped Environment
```

Git repositories, OCI images, Ubuntu packages and vendor installation media are transferred through the organization's approved mechanism.
Once those resources are available internally, the build and runtime architecture remains exactly the same. For this reason:

> **Air-gapped operation is a special case of this architecture, not the primary design assumption.**

The more general objective is to eliminate direct Internet dependencies from build and runtime systems.

## Recommended Corporate Model

A mature corporate container environment can provide four fundamental internal software supply services:

```text
                  CORPORATE SOFTWARE SERVICES

             +-----------------------------+
             |                             |
             |  Git       Source code      |
             |                             |
             |  Harbor    OCI images       |
             |                             |
             |  Mirror    OS packages      |
             |                             |
             |  Download  Vendor software  |
             |                             |
             +--------------+--------------+
                            |
                            v
                     Build Systems
                            |
                            v
                         Harbor
                            |
                            v
                     Runtime Systems
```

Organizations developing their own Linux-based applications should additionally consider maintaining a corporate base image:

```text
               Corporate Ubuntu Base Image
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
   Corporate CA       APT Mirror       Baseline
                           |
                           v
                 Application Images
```

This keeps corporate infrastructure policy out of individual application projects.

## Summary

The objective is not to find increasingly complicated ways to give every container build Internet access — it is to **remove the requirement for Internet access from build and runtime systems**.
The major external dependencies can be replaced with internal corporate services:

| Requirement               | Corporate solution                    |
| ------------------------- | ------------------------------------- |
| Source repositories       | Gitea / Git mirror / `dom-git-mirror` |
| Container images          | Harbor                                |
| Ubuntu packages           | Ubuntu mirror                         |
| Vendor installation media | Internal download server              |
| Corporate trust           | Corporate PKI / corporate base image  |
| Name resolution           | Corporate DNS                         |
| Time synchronization      | Corporate NTP                         |

For HCL Domino specifically, that means Git, Harbor, the Ubuntu mirror and MHS downloads all feed a single build step that publishes to Harbor, exactly as shown earlier in [HCL Domino Example](#hcl-domino-example).

* The build server does not require direct Internet access.
* The runtime server does not require direct Internet access.
* Neither server needs an Internet proxy.
* External connectivity is concentrated in a small number of controlled synchronization services.
* This provides a cleaner, more secure and more reproducible foundation for building and running containerized applications in corporate environments.

## References

* [GitHub](https://github.com/) — public Git hosting and source of the repositories this architecture mirrors internally
* [Gitea](https://docs.gitea.com/) — self-hosted Git service, repository mirroring, container package registry
* [GitLab](https://about.gitlab.com/) — self-hosted or SaaS Git platform, an alternative to Gitea
* [dom-git-mirror](dom-git-mirror/dom-git-mirror.md) — lightweight internal Git mirror for a small number of repositories
* [Docker Hub](https://hub.docker.com/) — public OCI registry commonly used as an image source
* [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) — public OCI registry commonly used as an image source
* [Harbor](https://goharbor.io/docs/) — OCI registry, replication, proxy cache, vulnerability scanning, content trust
* [Sonatype Nexus Repository](https://www.sonatype.com/products/sonatype-nexus-repository) — artifact repository with Docker/OCI proxy repositories
* [Ubuntu](https://ubuntu.com/) — base OS distribution used throughout the examples
* [Trivy](https://trivy.dev/) — vulnerability scanner used by Harbor and standalone
* [Cosign](https://docs.sigstore.dev/cosign/overview/) / [Notation](https://notaryproject.dev/) — container image signing and content trust
* [HCL Domino](https://www.hcl-software.com/domino) — product page
* [MyHCL Software (MHS)](https://my.hcltechsw.com/) — HCL's licensed software download portal
* [Domino Start Script](https://nashcom.github.io/domino-startscript/) — documentation ([repository](https://github.com/nashcom/domino-startscript/))
* [Domino Container Project](https://opensource.hcltechsw.com/domino-container/) — documentation ([repository](https://github.com/HCL-TECH-SOFTWARE/domino-container))

