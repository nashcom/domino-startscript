---
layout: default
title: Quickstart
nav_order: 1
description: "Quickstart Installation"
parent: "Domino Start Script"
has_children: false
---

# Quickstart Installation

## Download the start script tar file

Check the [Release Page](https://github.com/nashcom/domino-startscript/releases) for the current version.  
You can either download the start script tar file manually or leverage for example curl for automated downloads.

Example to download the latest version directly to a Linux machine:

```
curl -L $(curl -sL https://raw.githubusercontent.com/nashcom/domino-startscript/main/latest.txt) -o domino-startscript_latest.tar
```

## Extract the tar file

```
tar -xf domino-startscript_latest.tar
```

## Use install script for automated installation

The Domino Start Script comes with an installation script, which installs automatically using the most common defaults.

Switch to the start script directory and run the install script.  
Note: The install script can also be used to update existing scripts.

```
cd domino-startscript
./install_script
```
Once successfully completed, the `domino` command is available for all operations for your Domino server.
