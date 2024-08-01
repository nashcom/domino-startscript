---
layout: default
title: One-Touch Domino Setup
nav_order: 4
description: "One-Touch Domino setup support for automated setup"
has_children: false
---

# One-touch Domino Setup Support

Use the `domino setup` command to setup variables for a first server before you start your server.

Domino V12 introduced a new automated setup/configuration option.
One-touch Domino setup is a cross platform way to setup your Domino server.

You can either use

- environment variables
- a JSON file

Environment variable based setup allows you to set the most important server configuration options.
The JSON based setup provides many more options including creating databases, documents and modifying the server document.

The start script supports both methods and comes with default and sample configurations you can modify for your needs.

The new OneTouchSetup directory contains configuration templates for first server and additional server setups.

The new functionality provides a easy to use new `setup` command, which automatically creates a sample configuration for your.

When you use the install script, all the files are automatically copied to the `/opt/nashcom/startscript/OneTouchSetup` directory.

A new command `setup` allows you to configure the One-touch setup Domino configuration.

The following setup command options are available:

```
setup            edits an existing One Touch config file or creates a 1st server ENV file
setup env 1      creates and edits a first server ENV file
setup env 2      creates and edits an additional server ENV file
setup json 1     creates and edits a first server JSON file
setup json 2     creates and edits an additional server JSON file
```

```
setup log        lists the One Touch setup log file
setup log edit   edits the One Touch setup log file
```

The `setup` command creates the following files:

```
local/notesdata/DominoAutoConfig.json
local/notesdata/DominoAutoConfig.env
```

If present during first server start, the start script leverages One-touch Domino setup.
If both files are present the JSON configuration is preferred.

Refer to the [Domino OTS documentation](https://help.hcltechsw.com/domino/12.0.0/admin/wn_one-touch_domino_setup.html) for details.


## Setup files deleted after configuration

After setup is executed the ENV file is automatically removed, because it can contain sensitive information.
Specially for testing ensure to copy the files before starting your server.

For timing reasons the JSON file is not deleted by the start script.
But on successful setup One-touch Domino setup deletes the JSON file as well.
