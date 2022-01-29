---
layout: default
title: Known Issues
nav_order: 5
description: "Known Issues"
parent: "Domino Start Script"
has_children: false
---

# Known Issues

## Hex Messages instead of Log Messages

In some cases when you start the Domino server with my start script you see hex codes instead of log message.

The output looks similar to this instead of real log messages.

```
01.03.2015 12:42:00 07:92: 0A:0A
01.03.2015 12:42:00 03:51: 07:92
```

Here is the background about what happens:

Domino uses string resources for error messages on Windows which are linked into the binary.  
On Linux/UNIX there are normally no string resources and Domino uses the res files created on Windows in combination which code that reads those string resources for error output.

In theory there could be separate version of res files for each language and there used to be res files which have been language dependent.

So there is code in place in Domino to check for the locale and find the right language for error message.

But there are no localized resources for the error codes any more since Domino ships as English version with localized language packs (not containing res files any more).

This means there is only one set of res Files in English containing all the error text for the core code (a file called strings.res) and one per server tasks using string resources.

So string resources contain all the error texts and if Domino does not found the res files the server will only log the error codes instead.

By default the res files should be installed into the standard local of the server called `C`.  
In some cases the installer does copy the res files into a locale specific directory. For example `../res/de_DE` for German.

The start script usually sets the locale of the server. For example to LANG=de_DE or LANG=en_US.  
If this locale is different than the locale you installed the server with, the Domino server will not find the res files in those cases.

The right location for the res files would be for example on Linux:

```
 /opt/hcl/domino/notes/latest/linux/res/C/strings.res
```

But in some cases it looks like this

```
 /opt/hcl/domino/notes/latest/linux/res/de_DE/strings.res
```

The solution for this issue is to move the de_DE directory to C (e.g. `mv de_DE C`) and your server will find the res files independent of the locale configured on the server.

You could create a sym link for your locale. This will ensure it works also with all add-on applications and in upgrade scenarios.

```
cd /opt/hcl/domino/notes/latest/linux/res
ln -s de_DE.UTF-8 C
ln -s en_US.UTF-8 C
```

In some cases when the installer created the directory for a specific locale, you should make sure that you also have directory or sym link to a directory for C. So the `ln -s` command would have the opposite order.

## Long user name issues

Some Linux/UNIX commands by default only show the names of a user if the name is 8 chars or lower.  
Some other commands like ipcs start truncating user-names in display after 10 chars.

It is highly recommended to use 8 chars or less for all user-names on Linux/UNIX!

## Domino SIGHUB Issue

The Domino JVM has a known limitation when handling the SIGHUB signal on some platforms.  
Normally the Domino Server does ignore this signal. But the JVM might crash when receiving the signal. Starting the server via nohub does not solve the issue.

The only two known working configurations are:

- Invoke the bash before starting the server

- Start server always with "su - " (switch user) even if you are already  running with the right user. The su command will start the server in it's own process tree and the SIGHUB signal is not send to the Domino processes.

  Note: The start-script does always switch to the Domino server user for the "start" and "restart" commands.  
  For other commands no "su -" is needed to enforce the environment.  
  Switching the user from a non-system account (e.g. root) will always prompt for password -- even when switching to the same UNIX user.
