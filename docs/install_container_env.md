---
layout: default
title: Domino Container Environment
nav_order: 7
description: "Install Container Environment for Domino"
has_children: false
---


# Installing a Domino Container Environment with Nash!Com Convenience Script

This guide explains how to install a container-based environment for HCL Domino using a streamlined installation script.
The script automates the setup of a container host with Docker, helpful tools, and key utilities for building and running Domino in containers.


## Overview

The installation script performs the following actions:

1. **Installs Docker** – The recommended container engine using Docker’s [official installation script](https://docs.docker.com/engine/install/).
2. **Installs the Domino Download Script** – A helper script to download HCL Domino software packages.
3. **Installs `dominoctl`** – A control utility to manage Domino containers.
4. **Installs Linux tools** - Installs useful and required Linux tools.


## Prerequisites

- A supported Linux system (Ubuntu/Debian-based, RHEL-based distributions or Alpine).
- Internet access to fetch packages and scripts.
- Root or sudo privileges.


## Installation Command

Run the following command in your terminal to start the installation:

```
curl -sL https://raw.githubusercontent.com/nashcom/domino-startscript/main/install_container_env.sh | bash -
````

**Note**: This script installs software packages and modifies your system. Always review scripts from the internet before running them in production environments.


## What Gets Installed


### Docker

Docker is installed using the official convenience script provided by Docker, which configures the package repository, installs the Docker Engine, and enables the Docker service.


### Domino Download Script

A script that simplifies downloading HCL Domino installation packages. You will need a valid [My HCLSoftware(MHS) Download account](https://my.hcltechsw.com/) account to use this script.


### `dominoctl`

A command-line tool to manage Domino containers, including:

* Starting and stopping Domino containers
* Managing configuration and logs


## After Installation

Once the installation completes:

* Docker should be running and enabled at startup.
* The Domino container GitHub project in **/local/gihub/domino-container**
* You can use the `dominoctl` command to set up and manage Domino containers.
* The Domino download script is available to fetch the required Domino install packages manually or during the container build process.


## Next Steps


### Download Domino Installation Files

The **domdownload** script is in the path and can be just invoked.
To enable software downloads from [MHS]((https://my.hcltechsw.com/)) login into the portal and aquire an API key.
The link is located in the upper right corner when clicking on your account (or invoke the following URL: https://my.hcltechsw.com/tokens).

Apply the token by invoking the following command

```
domdownload -token
```


## Build Your First Domino Container

Switch to the cloned GitHub repository

```
cd /local/github/domino-container
```

Invoke the build menu or specify command-line options (see `./build.sh -?` for details).

```
./build.sh
```

For details see the [Domino Container](https://opensource.hcltechsw.com/domino-container/) documentation page.


### Run and Manage with dominoctl

Create, start, stop, and monitor containers easily.

Invoke the container control command from the path.
The command provides a menu and can also be invoke with explicit command-line options (see `dominoctl -?` for details).

```
dominoctl
```

The script comes with a default configuration.
Review the configuration before starting your first container either from the menu or via `dominoctl cfg`.

For details see the [Domino container control (dominoctl) ](https://nashcom.github.io/domino-startscript/dominoctl/) documentation page.

