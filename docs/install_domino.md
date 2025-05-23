---
layout: default
title: Domino One-Touch Installer 
nav_order: 3
description: "Domino V14 automated Installation on Linux"
has_children: false
---

# Domino V14 Installation

The following short instruction helps you to install HCL Domino V14 on your Linux box.  
It will help you to perform all essential steps to be up and running.  

Leveraging the Nash!Com Domino start script, Domino can be automatically started with an automatically installed `systemd` service.  
The start script is around since the first Domino on Linux version and is provided by Daniel Nashed free of charge.  
The start script allows you to start/stop the server and also provides options for configuration, logging, troubleshooting and maintenance.

There is also an automated one touch installation script available performing all the following installation steps for you.  
The following describes all the manual steps the installation script would perform automatically for you.

A very fast way to install your Domino server would be the following installation script, which is now part of the start script repository.
The following steps provide a manual way to perform similar operations as a documentation which steps to perform.

```
curl -sL https://raw.githubusercontent.com/nashcom/domino-startscript/main/install_domino.sh | bash -
```

## Update Linux

First of all you should update your Linux server to the latest software level in your current major version.
In contrast to Windows this is a very straightforward and fast operation.

The packet manager takes care of downloading and installing the latest software for you.

```
yum -y update
```

Depending which packages are updated you might want to reboot the machine once.

```
reboot
```

## Install Linux software

Domino requires the following software installed.

- The Domino installer uses Perl. The smallest package you can install are the `perl-libs`.
- Domino comes with the "Notes System Diagnostics" (NSD) tool, which leverages the GNU debugger (gdb).
  It is used to annotate the call-stacks of your Domino server's processes.

```
yum -y install gdb perl-libs tar
```

## Install Extra Packages for Enterprise Linux repository

Some additonal software is not available in the standard package repository of RedHat Linux.  
To be able to install additional software, you have to first install the `Extra Packages for Enterprise Linux repository` (EPEL).

```
yum -y install epel-release
```

## Install additional system tools

```
yum -y install sysstat bind-utils net-tools
```

## Install additional useful software

- **git**  
  Git is often used to download (clone) existing GitHub projects and is a conventient way to download and keep those projects in sync
- **jq**  
  JQ is the tool to work with JSON data. It is also used in many scripts.
- **ncdu**  
  To find out about your disk space is very useful. You can browse directories to see how much space is used in which directory

```
yum -y install jq git ncdu
```

## Create notes appliction user

Domino installation requires the **root** user and all Dominio binaries are owned by the root to ensure the integrity of the Domino software.  
At run-time Domino uses an unprivileged user, which owns all data files.  

On Linux each other has a primary group it belongs to. So you should create a corresponding group along with the user.

The standard name and group used is `notes:notes`.
It is strongly recommended to stay with the defaults provided. It simplifies your environment and ensures additional software installes seamless.  

```
useradd notes -U -m
```

In case your user should login directly, you can set a password.  

```
passwd notes
```

## Create directory structure for Domino data

The only required directory is the data directory. However in larger infrastructures separating the different parts of your Domino server data. 
Standardizing on the following file system structure. 

In larger environments all those directories would leverage a separate mount point.  
For small environments a single `/local` mount point should be sufficient.

It is strongly recommended to have at least one separate file-system (mount point e.g. /local) separating data from your system data.  
For a very small test server creating a separate file-system isn't required.  
You can always introduce additional file-systems leveraging mount-points for each of the directories later without changing the directoy structure.

- *translog*  Transaction log data should be always placed outside your data directory
- *daos*  In case DAOS is used it is also strongly recommended to place the DAOS repository also outside the data directory

```
mkdir -p /local/notesdata
mkdir -p /local/translog
mkdir -p /local/nif
mkdir -p /local/ft
mkdir -p /local/daos
```

Ensure the your Domino application user `notes` is the owner of all directories containing Domino data.

```
chown -R notes:notes /local
```

## Download the Domino web kit from MyHCL Software portal (MHS)

Domino as a commercial software product is currently only available via the MyHCL Software portal (MHS) software portal.  
An account and an active subscription is required to download current Domino software.  

The entry point for the download portal: [https://my.hcltechsw.com/](https://my.hcltechsw.com/).

There is a new Domino download script, which is also part of this repository.
It can be used to download Domino and companion products automatically from MHS.

The download script requires an API key, which can also be downloaded from the portal.
Refere to the Domino download documentation for details.

The following example uses Domino V14.0 `Domino_14.0_Linux_English.tar`.  
The automated installer comes with a list of current software packages and points you to the right download file.

Create an directory and download the software

```
mkdir -p /local/software
cd /local/software
```

Extract the Domino server web kit

```
tar xf Domino_14.0_Linux_English.tar
```

Switch to the extracted directory

```
cd linux64
```

## Install Domino with default options using silent install

Domino comes with a silent installation option. When installing a Domino server into the recommended standard directory structure with the standard user, a silent install will perform the installation for you.  
The default settings are already setup in the silent installer configuration file.

Depending on your server server, the installation can take a couple of minutes.

```
./install -f responseFile/installer.properties -i silent

```

## Set security limits

Domino is usually started leveraging a `systemd` services which sets security limits for the Domino server as part of the systemd script configuration.  
The security limits below are used for manual operations when starting the server processes on command line (e.g. off-line maintenance with DBMT).

Increase the number of open files for your Domino server to at least `80000` adding the following lines to your `/etc/security/limits.conf` file:

```
notes  hard    nofile  80000
notes  soft    nofile  80000
```

## Install Nash!Com Domino on Linux start script

The start script comes with an install script.  After downloading and extracting the tar file, just run the install script.  
the install script takes care of creating and updating the the start script.  
By default existing configuration files are not updated.  Only the script itself is updated.  


Switch back to the software directory

```
cd /local/software
```

Download the latest version of the Domino Start script from the offical GitHub repository [release page](https://github.com/nashcom/domino-startscript/releases).

If you want to download the software directly to your Linux machine, Curl is a very convenient way to download software.

Example for Version 3.7.0

```
curl -sLO https://github.com/nashcom/domino-startscript/releases/download/v3.7.0/domino-startscript_v3.7.0.taz
```

Extract the downloaded tar file

```
tar -xf domino-startscript_v3.7.0.taz
cd domino-startscript
```

Run the start script installation script

```
./install_script
```

## Firewall configuration

Linux comes with `firewalld` which should be enabled for all of your servers.  
This section describes the steps to expose the TCP/IP ports used by Domino.  

### Create a new NRPC firewall rule

The Domino NRPC protocol is not listed among the well known application ports.  
Instead of just specifying the port with it's port number, you can add a XML file to define your service.  
The start script already contains the XML file in the `extra` directory, which can be copied to your firewalld configuration.

```
cp /local/software/domino-startscript/extra/firewalld/nrpc.xml /etc/firewalld/services/
```

### Open ports NRPC, HTTP, HTTPS and SMTP

```
firewall-cmd --zone=public --permanent --add-service={nrpc,http,https,smtp}
```

Reload the firewall configuration

```
firewall-cmd --reload
```

### Check your exposed ports

Check your current configuration

```
firewall-cmd --list-services
```

### Updating Dominio

The install script is mainly intended to setup a new server. It is built based on the Domino Container image installer.
In a container software is installed from scratch. In a native installation the installation can be updated by removing the binary directory `/opt/hcl/domino`.
This will also ensure a clean update of your server.
Fixpack updates should be performed manually. The automated install will always install the full release along with fixpack and interim fix.

Starting with Domino 14.5 AutoInstall allows to automate installation on Windows and Linux.
