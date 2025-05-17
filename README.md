
# Domino Start Script

[![HCL Domino](https://img.shields.io/badge/HCL-Domino-ffde21?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB2aWV3Qm94PSIwIDAgNzE0LjMzIDcxNC4zMyI+PGRlZnM+PHN0eWxlPi5jbHMtMXtmaWxsOiM5M2EyYWQ7fS5jbHMtMntmaWxsOnVybCgjbGluZWFyLWdyYWRpZW50KTt9PC9zdHlsZT48bGluZWFyR3JhZGllbnQgaWQ9ImxpbmVhci1ncmFkaWVudCIgeDE9Ii0xMjA3LjIiIHkxPSItMTQzIiB4Mj0iLTEwMzguNjYiIHkyPSItMTQzIiBncmFkaWVudFRyYW5zZm9ybT0ibWF0cml4KDEuMDYsIDAuMTMsIC0wLjExLCAwLjk5LCAxMzUzLjcsIDYwMC42MikiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIj48c3RvcCBvZmZzZXQ9IjAiIHN0b3AtY29sb3I9IiNmZmRmNDEiLz48c3RvcCBvZmZzZXQ9IjAuMjYiIHN0b3AtY29sb3I9IiNmZWRjM2QiLz48c3RvcCBvZmZzZXQ9IjAuNSIgc3RvcC1jb2xvcj0iI2ZiZDIzMiIvPjxzdG9wIG9mZnNldD0iMC43NCIgc3RvcC1jb2xvcj0iI2Y2YzExZiIvPjxzdG9wIG9mZnNldD0iMC45NyIgc3RvcC1jb2xvcj0iI2VmYWEwNCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iI2VlYTYwMCIvPjwvbGluZWFyR3JhZGllbnQ+PC9kZWZzPjxnIGlkPSJMYXllcl8zIiBkYXRhLW5hbWU9IkxheWVyIDMiPjxwb2x5Z29uIGNsYXNzPSJjbHMtMSIgcG9pbnRzPSI0MzcuNDYgMjgzLjI4IDMzNi40NiA1MDYuNjkgMjExLjY4IDUwNy40NSAzNjYuOTIgMTYyLjYxIDQzNy40NiAyODMuMjgiLz48cG9seWdvbiBjbGFzcz0iY2xzLTEiIHBvaW50cz0iNjQwLjU5IDMwNC4xIDUyOS4wMiA1NTEuOTYgMzUzLjYzIDU2Ni42MiA1NDIuMzIgMTQ3LjcxIDY0MC41OSAzMDQuMSIvPjxwb2x5Z29uIGNsYXNzPSJjbHMtMiIgcG9pbnRzPSIyNzMuMTkgMjY1LjM3IDE5MC4xMSA0NTAuMDYgNzMuNzQgNDM5LjI4IDE5NC4zMiAxNzEuMzMgMjczLjE5IDI2NS4zNyIvPjwvZz48L3N2Zz4K
)](https://www.hcl-software.com/domino)
[![HCL Ambassador](https://img.shields.io/static/v1?label=HCL&message=Ambassador&color=006CB7&labelColor=DDDDDD&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMjYuMjQgODYuMjgiPjxkZWZzPjxzdHlsZT4uY2xzLTF7ZmlsbDojMDA2Y2I3O308L3N0eWxlPjwvZGVmcz48ZyBpZD0iTGF5ZXJfMiIgZGF0YS1uYW1lPSJMYXllciAyIj48ZyBpZD0iRWJlbmVfMSIgZGF0YS1uYW1lPSJFYmVuZSAxIj48cG9seWdvbiBjbGFzcz0iY2xzLTEiIHBvaW50cz0iMTI2LjI0IDQzLjE0IDkxLjY4IDQzLjE0IDcyLjIgODYuMjggMTA2Ljc2IDg2LjI4IDEyNi4yNCA0My4xNCIvPjxwb2x5Z29uIGNsYXNzPSJjbHMtMSIgcG9pbnRzPSIwIDQzLjE0IDM0LjU2IDQzLjE0IDU0LjA0IDg2LjI4IDE5LjQ4IDg2LjI4IDAgNDMuMTQiLz48cG9seWdvbiBjbGFzcz0iY2xzLTEiIHBvaW50cz0iNjMuMTIgMCA0My42NCA0My4xNCA2My4xMiA4Ni4yOCA4Mi42IDQzLjE0IDYzLjEyIDAiLz48L2c+PC9nPjwvc3ZnPg==)](https://www.hcl-software.com/about/hcl-ambassadors)
[![Nash!Com Blog](https://img.shields.io/badge/Blog-Nash!Com-blue)](https://blog.nashcom.de)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://github.com/nashcom/buil-test/blob/main/LICENSE)

The Domino cross platform start/stop and diagnostic script has been written to unify and simplify running Domino on Linux and UNIX.
The start script is designed to be "one-stop shopping" for all kind of operations done on the Linux/UNIX prompt. The script can start and stop the server, provides an interactive console and run NSD in different flavors.

This script is designed to run with a dedicated user for each partition. Out of the box the script is configured to use the "notes" user/group and the standard directories for binaries (/opt/hcl/domino) and the data directory (/local/notesdata). You should setup all settings in the script configuration file.

Out of the box the script is configured to use the "notes" user/group and the standard
directories for binaries (/opt/hcl/domino) and the data directory (/local/notesdata).
You should setup all settings in the script configuration file.

Note: Linux systemd requires root permissions for start/stop.
One way to accomplish this is to grant "sudo" permissions for the "rc_domino" script.
See the "Enable Startup with sudo" section for details.


[The Start Script GitHub page](https://nashcom.github.io/domino-startscript/) contains the full documentation for the Start Script.



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
- **install_scripts** writes all required files into the right locations with the right owner and permissions.
- The next command enables the service (systemd)
- And finally the server is started

Example:

```
tar -xzf domino-startscript_v3.8.0.taz
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

For a detailed documentation check the GitHub page linked on the top right corner of this page.

