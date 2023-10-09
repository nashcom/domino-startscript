
# Introduction

The Domino cross platform start/stop and diagnostic script has been written
to unify and simplify running Domino on Linux and UNIX. The start script
is designed to be "one-stop shopping" for all kind of operations done on the
Linux/UNIX prompt. The script can start and stop the server, provides an interactive
console and run NSD in different flavors.

This script is designed to run with a dedicated user for each partition.
Out of the box the script is configured to use the "notes" user/group and the standard
directories for binaries (/opt/hcl/domino) and the data directory (/local/notesdata).
You should setup all settings in the script configuration file.

Note: Linux systemd (CentOS 7 RHEL 7/ SLES 12) requires root permissions for start/stop.
One way to accomplish this is to grant "sudo" permissions for the "rc_domino" script.
See the "Enable Startup with sudo" section for details.

# Simple Configuration

If you configure your Domino environment with the standard path names
and users names, you can use this standard configuration and install script.

The default configuration is

```
User : notes
Group: notes
Binary Directory: /opt/hcl/domino
Data Directory  : /local/notesdata
```

The standard configuration is highly recommended. This will make your life easier for installing the server.
You can change the data directory in the rc_domino_config file.
But the binary location and the notes:notes user and group should stay the same.

I would stay with the standard /local/notesdata. This could be a spearate mount-point.
And you could also use the following directory structure for the other directories.

```
/local/translog
/local/nif
/local/daos
```

Each of them could be a separate file-system/disk.

If you have the standard environemnt you just have to untar the start-script files and start the install_script.
It copies all the scripts and configuration and after installation you can use the "domino" command for everything.
The script is pre-configured and will work for older versions with init.d and also with the newer systemd.

- The first command untars the files
- The install_scripts writes all required files into the right locations with the right owner and permissions.
- The next command enables the service (works for init.d and systemd)
- And finally the server is started

```
tar -xzf domino-startscript_v3.7.3.taz
cd domino-startscript
./install_script
```

```
domino service on
domino start
```

Other useful commands

```
domino status
domino statusd
domino console
```

