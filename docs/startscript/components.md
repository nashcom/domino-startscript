---
layout: default
title: Components of the Script
nav_order: 4
description: "Details about the components of the script"
parent: "Domino Start Script"
has_children: false
---

# Components of the Script

## rc_domino

  This shell script has two main purposes

- Have a basic entry point per instance to include it in "rc" run-level
  scripts for automatic startup of the Domino partition
  You need one script per Domino partition or a symbolic link
  with a unique name per Domino partition.

- Switch to the right user and call the `rc_domino_script`.

  Notes:

- If the user does not change or you invoke it as root you will not
  be prompted for a password. Else the shell prompts for the Notes
  UNIX user password.

- The script contains the location of the `rc_domino_script`.
  You have to specify the location in `DOMINO_START_SCRIPT`
  (default is /opt/nashcom/startscript/rc_domino_script).
  It is not recommended to change this default location because of systemd configuration.

## rc_domino_script

  This shell script contains

- Implementation of the shell logic and helper functions.
- General configuration of the script.
- The configuration per Domino server specified by notes Linux/UNIX user.
  You have to add more configurations depending on your Domino partition setup.
  This is now optional and we recommend using the rc_domino_config_xxx files

## rc_domino_config / rc_domino_config_xxx

- This file is located by default in /etc/sysconfig and should be used as an external configuration (outside the script itself).

- By default the script searches for a name in the format rc_domino_config_xxx (e.g. for the `notes` user rc_domino_config_notes)
where xxx is the UNIX user name of the Domino server.

- The default name of the script shipped is rc_domino_config but you can add also a specific configuration file for your partition.

The config files are used in the following order to allow flexible configurations:

- First the default config-file is loaded if exists (by default: `/etc/sysconfig/rc_domino_config`)
- In the next step the server specific config-file (by default: `/etc/sysconfig/rc_domino_config_notes` ) is included.
- The server specific config file can add or overwrite configuration parameters.

This allows very flexible configuration. You can specify global parameters in the default config file and have specific config files per Domino partition.  
So you can now use both config files in combination or just one of them.

Note: On AIX this directory is not standard but you can create it or if really needed change the location the script.

Usually there is one configuration file per Domino partition and the last part of the name
determines the partition it is used for.

Examples:

```
rc_domino_config_notes
rc_domino_config_notes1
rc_domino_config_notes2
...
```

If this file exists for a partition those parameters are used for server start script configuration.

This way you can completely separate configuration and script logic.  
You could give even write permissions to Domino admins to allow them to change the start-up script configuration.

This file only needs to be readable in contrast to `rc_domino` and `rc_domino_script` which need to be executable.

## systemd service file: domino.service

Starting with CentOS 7 RHEL 7 and SLES 12 systemd is used to start/stop services.  
The domino.service file contains the configuration for the service.  
The variables used (Linux user name and script location) have to match your configuration.  
Configuration for the domino.service file is described in the previous section.  
Each Domino partition needs a separate service file.  
See configuration details in section "Domino Start Script systemd Support"

## domino_docker_entrypoint.sh Docker entry point script

This script can be used as the standard entry point for your Domino Docker container.  
It takes care of your Domino Server start/stop operations.  
See details in the Docker section.
