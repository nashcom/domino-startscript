---
layout: default
title: "Domino Start Script"
nav_order: 1
description: "Start Script for HCL Domino on Linux and AIX"
has_children: true
---

[Quickstart](https://nashcom.github.io/domino-startscript/startscript/quickstart){: .btn }
[View it on GitHub](https://github.com/nashcom/domino-startscript){: .btn }

---

# Introduction

[The Domino cross platform start/stop and diagnostic script](https://github.com/nashcom/domino-startscript)
has been designed to unify and simplify running Domino on Linux and UNIX.
The start script is designed to be "one-stop shopping" for all kind of operations performed on the Linux/UNIX prompt. 
The script can start and stop the server, provides an interactive console and run NSD in different flavors.
It ensures that the environment is always setup correct and supports multiple partitions.

This script is designed to run with a dedicated user for each partition.
It is already configured for the default user "notes" user and group (notes:notes).
Binary are assumed to be in`/opt/hcl/domino`, the data directory is assumed in `/local/notesdata`.
Settings are configured in `/etc/sysconfig/rc_domino_config`.

# Standard installation and configuration

If you configure your Domino environment with the standard path names
and users names, you can use this standard configuration and install script.

```
User : notes
Group: notes
Binary Directory: /opt/hcl/domino
Data Directory  : /local/notesdata
```

The standard configuration is highly recommended. This will make your life easier for installing the server.
You can change the data directory in the rc_domino_config file.
But the binary location and the notes:notes user and group should stay the same.

You should stay with the standard `/local/notesdata`. This could be a separate mount-point.
And you could also use the following directory structure for the other directories.

```
/local/translog
/local/nif
/local/daos
```

Each of the directories could be a separate file-system/disk.

If you have the standard environment you just have to untar the start-script files and start the install_script.
It copies all the scripts and configuration and after installation you can use the "domino" command for everything.

- The first command untars the files
- The install_scripts writes all required files into the right locations with the right owner and permissions.
- The next command enables the service (works for init.d and systemd)
- And finally the server is started


## Download the start script tar file

Check the [Release Page](https://github.com/nashcom/domino-startscript/releases) for the current version.  
You can either download the start script tar file manually or leverage for example curl for automated downloads.

Example to download the file directly to a Linux machine:

```
curl -LO https://github.com/nashcom/domino-startscript/releases/download/v3.7.0/domino-startscript_v3.7.0.tar
```

## Extract the tar file


```
tar -xf domino-startscript_v3.7.0.tar
```

Tip: You can download the latest version using a special curl command:

```
curl -L $(curl -sL https://raw.githubusercontent.com/nashcom/domino-startscript/main/latest.txt) -o domino-startscript_latest.tar
```

## Use install script for automated installation

The Domino Start Script comes with an installation script, which installs automatically using the most common defaults.

Switch to the start script directory and run the `install script`.  
Note: The install script can also be used to update existing scripts.

```
cd domino-startscript
./install_script
```

The Domino service is automatically enabled by the start script installer.  
Once successfully completed, the `domino` command is available for all operations for your Domino server.

```
domino start
domino stop
domino status
domino statusd
```

Launch the Domino server live console

```
domino console
```

See the [commands section](https://nashcom.github.io/domino-startscript/startscript/commands) for a full list of commands.

## Systemd

[systemd](https://systemd.io/) is used on all current Linux distributions to start services.

Systemd requires root permissions for start/stop.
One way to accomplish this is to grant `sudo` permissions for the "rc_domino" script.

## Enable Startup with sudo

If you never looked into sudo, here is a simple configuration that allow you to run the start script with root permissions.
Basically this allows the notes user to run the /etc/init.d/rc_domino as root.
This avoids switching to the root user.

visudo

Add the following lines to the sudoers file

```
%notes  ALL= NOPASSWD: /etc/init.d/rc_domino *, /usr/bin/domino *
```

This allows you to to run the start script in the following way from your notes user.

```
sudo /etc/init.d/rc_domino ..
```

# Manual Configuration

## 1. Copy Script Files

- Copy the script rc_domino_script into your Nash!Com start script directory /opt/nashcom/startscript
- Copy rc_domino into /etc/init.d

- For systemd copy the domino.service file to /etc/systemd/system  
  And ensure that rc_domino contains the right location for the service file  
  configured in the top section of your rc_domino file -> `DOMINO_SYSTEMD_NAME=domino.service`.

## 2. Ensure the script files are executable by the notes user

Example:

 ```
chmod 755 /opt/nashcom/startscript/rc_domino_script
chmod 755 /etc/init.d/rc_domino
 ```

## 3. Check Configuration

Ensure that your UNIX/Linux user name matches the one in the configuration part
of the Domino server. Default is  `notes`.

For systemd ensure the configuration of the domino.service file is matching and
specially if it contains the right user name and path to the rc_domino_script.
And also the right path for the "PIDFile"
(See "Special platform considerations --> systemd (CentOS 7 RHEL 7/ SLES 12 or higher)"  for details).

# Special platform considerations AIX

For AIX change first line of the scripts from `#!/bin/bash` to `#!/bin/ksh`

AIX uses `ksh` instead of `sh/bash`.
The implementation of the shells differs in some ways on different platforms.
Make sure you change this line in `rc_domino` and `rc_domino_script`

On AIX you can use the mkitab to include rc_domino in the right run-level
Example:

```
mkitab domino:2:once:"/etc/rc_domino start
```

# Additional Options

You can disable starting the Domino server temporary by creating a file in the data-directory named `domino_disabled`.  
If the file exists when the start script is called, the Domino server is not started.

# Differences between Platforms

The two scripts use the Korn-Shell `/bin/ksh` on AIX.  
On Linux the script needs uses `/bin/sh` / `/bin/bash`.

Edit the first line of the script according to your platform

```
Linux: "#!/bin/sh"
AIX: "#!/bin/ksh"
```

# Tuning your OS-level Environment for Domino

Tuning your OS-platform is pretty much depending the flavor and version of UNIX/Linux you are running.  
You have to tune the security settings for your Domino UNIX user, change system kernel parameters and other system parameters.

The start script queries the environment of the UNIX notes user and the basic information like ulimit output when the server is started.

The script only sets up the tuning parameters specified in the UNIX user environment. There is a section per platform to specify OS environment tuning parameters.

## Linux

You have to increase the number of open files that the server can open.  
Those file handles are required for files/databases and also for TCP/IP sockets.  
The default is too low and you have to increase the limits.

Note: No change is required if you system already has higher default values.

Using the ulimit command is not a solution. Settings the security limits via root before switching to the notes user executing the start script via "su -" does not work any more.  
And it would also not be the recommended way.

su leverages the pam_limits.so module to set the security limits when the user switches.

So you have to increase the limits by modifying `/etc/security/limits.conf`

You should add a statement like this to `/etc/security/limits.conf`

```
* soft nofile 80000
* hard nofile 80000
```

# systemd Configuration

This configuration is not needed to start servers with systemd.  
systemd does set the limits explicitly when starting the Domino server.  
The number of open files is the only setting that needs to be changed via `LimitNOFILE=80000` in the domino.service file.

```
export NOTES_SHARED_DPOOLSIZE=20971520
```

Specifies a larger Shared DPOOL size to ensure proper memory utilization.

Detailed tuning is not part of this documentation. If you need platform specify tuning feel free to contact
domino_unix@nashcom.de

## Implementation Details

The main reason for having two scripts is the need to switch to a different user. Only outside the script the user can be changed using the 'su' command and starting another script. On some platforms like Linux you have to ensure that su does change the limits of the current user by adding the pam limits module in the su configuration.

In the first implementation of the script the configuration per user was specified in the first part of the script and passed by parameter to the main script. This approach was quite limited because every additional parameter
needed to be specified separately at the right position in the argument list.

Inheriting the environment variables was not possible because the su command does discard all variables when specifying the "-" option which is needed to setup the environment for the new user.  
Therefore the beginning of the main script contains configuration parameters for each Domino partition specified by UNIX user name for each partition.


### Starting, Stopping and getting the Status

```
systemctl start domino.service
systemctl stop domino.service
systemctl status domino.service
```

### Enabling and Disabling the Service

```
systemctl enable domino.service
systemctl disable domino.service
```

The service file itself is be located in `/etc/systemd/system`.

You have to install a service file per Domino partition. When you copy the file you have to make sure to have the right settings.

- ExecStart/ExecStop needs the right location for the rc_domino_script (still usually the Domino program directory)
- Set the right user account name for your Domino server (usually "notes").

The following example is what will ship with the start script and which needs to be copied to `/etc/systemd/system` before it can be enabled or started.

### Systemd service file shipped with the start script

```
[Unit]
Description=HCL Domino Server
After=syslog.target network.target

[Service]
Type=forking
User=notes
LimitNOFILE=65535
PIDFile=/local/notesdata/domino.pid
ExecStart=/opt/nashcom/startscript/rc_domino_script start
ExecStop=/opt/nashcom/startscript/rc_domino_script stop
TimeoutSec=100
TimeoutStopSec=300
KillMode=none
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
```

The rc_domino script can be still used for all commands.  
This includes starting and stopping Domino as a service (only "restart live" option is not implemented).  
You can continue to have rc_domino with the same or different names in the `/etc/init.d` directory or put it into any other location. It remains the central entry point for all operations.

But the domino.service can also be started and stopped using "systemctl". rc_domino uses the configured name of the domino.service (in the header section of `rc_domino script`).

systemd operations need root permissions. So it would be best to either start rc_domino for start/stop operations with root.
One way to accomplish using root permissions is to allow sudo for the `rc_domino script`.

The configuration in `/etc/sysconfig/rc_domino_config` (or whatever your user name is) will remain the same and will still be read by `rc_domino_script`.

The only difference is that the `rc_domino_script` is invoked by the systemd service instead of the `rc_domino` script for start/stop operations.

When invoking start/stop live operations a combination of systemd commands and the existing `rc_domino_script` logic is used.

## systemd status command

The output from the systemd status command provides much more information than just if the service is started.

Therefore when using systemd the rc_domino script has a new command to show the systemd status output.
The new command is `statusd`

## Manually install script installation?

- Copy `rc_domino`, `rc_domino_script` and `rc_domino_config` to the right locations
- Copy domino.service to `/etc/systemd/system`.
- Make the ### Changes according to your environment
- Enable the service via `systemctl enable domino.service` and have it started/stopped automatically
  or start/stop it either via systemd command or via `rc_domino` script commands.
- rc_domino script contains the name of the systemd service.
  If you change the name or have multiple partitions you need to change the names accordingly

## How does it work?

- Machine startup  
When the machine is started systemd will automatically start the domino.service.  
The `domino.service` invokes the `rc_domino_script` (main script logic).  
`rc_domino_script` will read `rc_domino_config`.

- Start/Stop via rc_domino
 When `rc_domino start` is invoked the script will invoke the service via systemctl start/stop domino.service.

- Other script operations
Other operations like `monitor` will continue unchanged and invoke the `rc_domino_script`.

