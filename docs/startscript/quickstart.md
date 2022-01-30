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

Example to download the file directly to a Linux machine:

```
curl -LO https://github.com/nashcom/domino-startscript/releases/download/v3.7.0/domino-startscript_v3.7.0.tar
```

## Extract the tar file

```
tar -xvf domino-startscript_v3.7.0.tar
```

## Use install script for automated installation

The Domino Start Script comes with an installation script, which installs automatically using the most common defaults.

Switch to the start script directory and run the install script.  
Note: The install script can also be used to update existing scripts.

```
cd domino-startscript
./install_script
```
Once successfully completed, the `domino` command is available for all further operations.
