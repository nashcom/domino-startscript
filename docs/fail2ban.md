---
layout: default
title: Fail2Ban for Domino 
nav_order: 5
description: "Fail2Ban for Domino"
has_children: false
---

# Fail2Ban for Domino

## Introduction

Blocking IP addresses after a couple of login failures is an effective way to increase security.
[Fail2Ban](https://www.fail2ban.org) has been around for quite a while and is available in may Linux distribution.
It uses iptable firewall rules to block IP addresses once an application has reported login failures.
There are filters for many applications already included.

## How does fail2ban work with Domino?

Domino logs authentication errors in a standardized way for all internet protocols.  
Fail2Ban keeps track of login failures by IP address and uses IPTables rules to block the traffict, after the specified number of login attempts have been reached.

Fail2Ban provides options to specify separate jail configurations per application.  
Usually different applications should block IP addresses directly on all protocols.
This is the default behavior, configured in the example configuration.


Example:

```
[007577:000017-00007F621246D700] 20.03.2022 07:36:42   http: info@acme.net [1.2.3.4] authentication failure using internet password
[007577:000017-00007F621246D700] 20.03.2022 07:36:43   http: IP Address [1.2.3.4] authentication failure using internet password: User is locked out
```

A Domino log filter with a jail configuration for Domino can feed login failures directly into fail2ban.

# Block TLS/SSL errors

Usually TLS connection errors are also an indication of an attack.
Therefore the filter string has been updated to also detect TLS/SSL errors.


```
[003546:000013-00007F12A17E5700] 28.05.2022 00:47:11   TLS/SSL connection 1.2.3.4(50332) -> 111.222.333.444(443) failed with rejected SSLv3 connection
[003546:000013-00007F12A17E5700] 28.05.2022 00:47:20   TLS/SSL connection 1.2.3.4(57820) -> 111.222.333.444(443) failed with no supported ciphers
[003546:000013-00007F12A17E5700] 28.05.2022 00:47:33   TLS/SSL connection 1.2.3.4(40082) -> 111.222.333.444(443) failed with rejected unknown record type

```

## Security scanners might be blocked as well

With this protection enabled, you can't use remote scans to check your server TLS configuration.  
There is a project to scan local servers, which also work for servers which are not exposed externally at all: 

https://github.com/drwetter/testssl.sh

In case you don't want TLS/SSL errors to cause the block count to increase, you can comment out the additional filter line.


## Components

The implementation is based on the following two components

- **domino.conf**
  Domino filter configuration containing the regular search expression

- **jail.local**
  Base configuration, including sshd configuration.
  Either used full configuration or reference for your own configuration

- **domban**
  Fail2Ban for Domino management script
  Installs and manages all fail2ban operations

## Installation

Fail2Ban for Domino is located in `extras/fail2ban`.


To install fail2ban and the Domino integration just launch `./domban install`.  
Installation requires root permissions. Switch to the root user or leverage sudo if permissions are granted for your Linux user.  
The script contains the installation and will also install itself as `usr/bin/domban` to fully mangage fail2ban.

Example:

```
/local/github/domino-startscript/extra/fail2ban/domban install
```

The installation expects the Start Script Log file in the default location.
In case you moved your log, ensure the location in `jail.local` is updated.

To edit the configuration invoke `domban cfg`.

### Verifying the configuration

- Once the environment is setup check first the status of the service via `domban status`
- In case of error check the log file via `domban log`
- Check the status of your Domino jail via `domban`
- Check the status of your SSH jail via `domban ssh`

## Operations

Once installed all operations can be performed invoking the `domban` management script:

- **ssh**  
  Show status of SSH jail

- **unblock IP**  
  Unblock specified IP from Domino and SSH jail

- **cfg**  
  Configure fail2ban jail.local. Default editor: vi. Use e.g. export `EDIT_COMMAND=nano`

- **log [lines]**  
  List fail2ban log (default: last 100 lines)

- **status**  
  Show systemd fail2bank status

- **restart**  
  Restart fail2ban service

- **systemd [cmd]**  
  Pass commands to systemd

- **install [upd]**  
  Install fail2ban and 'domban' script - `upd` overwrites existing `jail.local`

- **test [logfile]**  
  Test Domino fail2ban filter against log - if no log file specified use configured log file


## Exampl Output: Status Domino jail

{: .lh-0 }
```
--------------------------------------------------------------------------------
Status for the jail: domino
|- Filter
|  |- Currently failed: 1
|  |- Total failed:     18
|  `- File list:        /local/log/notes.log
`- Actions
   |- Currently banned: 1
   |- Total banned:     2
   `- Banned IP list:   192.168.007.42
---------------------------------------------------
```
{: .fh-default }

## Help Output

```
Domino Fail2Ban
---------------

Syntax: domban

ssh              Show status of SSH jail (No parameter = show Domino jail)
unblock <IP>     Unblock IP from Domino and SSH jail
cfg              Configure fail2ban jail.local. Editor: vi. Use e.g. export EDIT_COMMAND=nano
log [lines]      List fail2ban log (default: last 100 lines)
status           Show systemd fail2ban status
restart          Restart fail2ban service
systemd [cmd]    Pass commands to systemd
install [upd]    Install fail2ban and 'domban' script - 'upd' overwrites existing 'jail.local'
test [logfile]   Test filter against logfile
-                No parameter shows Domino jail status

selinux          Show SELinux status
selinux logset   Lable start script log file with fail2ban access
selinux logdel   Remove label for start script log
selinux relable  Relable log files

```
