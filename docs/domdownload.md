---
layout: default
title: Domino Download Script
nav_order: 7
description: "Domino Download Script"
has_children: false
---

# Introduction

HCL Domino V14 introduces a new "autoupdate" functionality to automatically download software controlled by a modern Notes UI directly into a domain wide replicated database.
The new functionality in Domino leverages the new [My HCL Software download portal](https://my.hcltechsw.com/) with a new download API.

My HCL Software download portal will replace the existing Flexnet download functionality.
The new offering is dramatically easier, faster to navigate and provides a more modern interface.
It is the new recommended browser based download functionality operating with the same credentials used for Flexnet download.
Log into https://my.hcltechsw.com/ to browser and download all software you are entitled to.

The Domino Download Script combines components from both offerings to provide a complementary command-line download interface, which can be used for automation flows:

- Domino AutoUpdate product information (product.jwt) to identify the latest software versions
- Domino AutoUpdate software information (software.jwt) to provide web-kit information
- My HCL Software download portal functionality to automatically download selected software

The script is also leveraged in the container build script in the [HCL Domino Container Community project](https://opensource.hcltechsw.com/domino-container/).


# Functionality

- Navigate the My HCL Software via command line to download or list software
- Navigate the [autoupdate.jwt](https://ds_infolib.hcltechsw.com/software.jwt) data to download or list software
- Determine the latest version of a product via [product.jwt](https://ds_infolib.hcltechsw.com/software.jwt).
- "**local mode**": Download software from an own internal server leveraging software.jwt.
  Can be also downloaded manually in an air gapped environment.
- Generate a curl command-line with an authenticated redirect instead of downloading (-curl option)

# How to get started

Download the script and make it executable via `chmod +x domdownload.sh` and run the script.

The script is part of the Domino start script repository and can be installed directly from there using the `install` option once you cloned the Start Script repository using git. 
The install option installs the script to `/usr/local/bin/domdownload`.

- The script prompts for missing components and also ask for accessing the internet once
- At first start a default configuration with the most commonly used options is written
- For details about supported commands invoke the script's help functionality by specifying `-help`
- By default My HCL Download portal data is used to navigate
- Specify `-autoupdate` to use AutoUpdate data for the download menu instead of My HCL Software portal navigation
- To only list download information specify the `-info` option


# Supported environments

- Linux distributions (tested: Redhat/CentOS 8/9 and clones, Ubuntu 22.04, VMware Photon OS 5 and SUSE Linux 15.x)
- MacOS
- GitBash on Windows (part of the standard Git client)


# Implementation details

The functionality is implemented in a bash script.
Most of the components used are installed by default already. The JQ package needs to be added on most cases and is required for JSON parsing. The script assists to install missing packages.
For HTTPS requests the [Curl package is used](https://curl.se/). Curl should be installed in most environments already.

- **JSON/JWT** data is cached to avoid the round trip. The data is automatically refreshed periodically
- Configuration data is stored in a configuration file.
- All files are stored in `.DominoDownload` in the home directory of the current user
- If `.DominoDownload` directory exists in the current directory, the local configuration is used instead
- The download token is stored in a local file and automatically refreshed
- All data is stored in the .DominoDownload located in the home directory of the current user
- To support multiple configurations the script also supports a .DominoDownload directory in the current work directory to override the user based configuration.
- All downloads are validating the SHA256 checksum
- Existing downloads are detected and not overwritten unless -force option is specified


# My HCL Software Download Token

Production and software information can be queried without authentication.
For Download a My HCL Software download token is required. It can be requested directly from https://my.hcltechsw.com/tokens
The token is a rotating refresh token, which is stored locally by the script.
