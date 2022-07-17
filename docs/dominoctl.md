---
layout: default
title: Domino container control
nav_order: 5
description: "Domino container control (dominoctl)"
has_children: false
---

# Domino container control (domctl)

**dominoctl** provides commands and operations for Domino on Docker and Podman.
For running a single Domino instance on a Docker or Podman host, this script is one-stop shopping for all operations.
From start/stop to configuration and the life time of the container all all szenarios are covered.
Most of the standard commands are very similar to the Domino start script.
The container control script works hand in hand with the Domino start script, which is running inside the container.


## Install dominoctl

Switch to the start-script directory and run the install script.

```
./install_dominoctl
```

## Quick configuration

- To get your server up and running, ensure you have a container image defined and available on your machine.
- When running on Docker make sure the Docker service is running.

### Edit the configuration of your container by invoking the cfg command:

 Edit your container configuration and ensure at least the following settings are specified:

- CONTAINER_IMAGE
- CONTAINER_NAME
- CONTAINER_VOLUMES

See full list of all configurations options below. 

```
dominoctl cfg
```

### Start your container

Finally start your container. For the first start will run a new container. If the container is already present, the container is started.

```
dominoctl start
```


## Podman support

**dominoctl** automatically detects Docker and Podman run-time environments to use the right commands.
In contrast to Docker, Podman is daemon-less and needs a separate service to start.
The project comes with a systemd script, which is automatically installed and leveraged by **dominoctl**.

### Configure your server using a OneTouch setup template for the first server or an additional server

```
dominoctl setup
```

### Run your container

```
dominoctl run
```


# Command reference

## Start/stop

### start
Start an existing container (the 'live' option shows start script output)

### stop
Stop container (the 'live' option Show start script output)

### restart
Restart or start the server

## Status/info commands

### status
Show container status (running, exited, notexisting)

### statusd
Show the systemd status

### about|about+
Show machine info. With 'About' or 'about+' also show info from https://ipinfo.io/

### info
Show status and basic information about container and image

### inspect
Show detailed information about container and image

### port
Show used tcp/ip ports for container

## Container operations

### console
Open Domino console inside the container

### logs
Show container logs (output from entry point script/start script)

### attach
Attach to entrypoint script

### domino
Pass a command to the start script (e.g. domino nsd)

### bash [root]
Invoke a bash in the running container. optionally run as root instead of notes user

### remove|rm
Remove the container (if not running)

### removeimage|rmi
Remove the currently configured image (you have to remove the container first)

## Container configuration

### config|cfg
Edit configuration

### setup
Create JSON configuration for container auto configuraiton

### update
Update the container if referenced image has changed (stops Domino, stops the container, runs a new image)

## Container commands

### pull
Pull current image (e.g for update)

### install
Install Podman

### load
Load HCL Domino Docker image

### build
Build a current image -- even image tags might not have changed to ensure OS patches are installed

### restartpolicy
Update restart policy for existing container (e.g. : no | on-failure | always | unless-stopped)

### enable|on
Enable systemd service for Podman

### disable|off
Disable systemd service for Podman

### clean
Cleanup container and systemd if configured

### env
Edit environment file

### version
Show script version information

# Configuration settings

## CONTAINER_NAME

Defines the name of the container.  
The container name is used to reference the container by name instead of using the container ID.

```
CONTAINER_NAME=domino
```

## CONTAINER_IMAGE

Container image used by the container.  
By default, the build script used the name **hclcom/domino:latest**

```
CONTAINER_IMAGE=hclcom/domino:latest
```

## CONTAINER_HOSTNAME

Defines the container hostname.
If not set, the machine's hostname is used by default.


```
CONTAINER_HOSTNAME=domino.acme.loc
```

## DOMINO_SHUTDOWN_TIMEOUT

By default, the Docker kills the container processes after 10 seconds.  
Domino requires a longer shutdown interval than 10 seconds.
If not specified the container timeout is set to 120 seconds by the script.

```
DOMINO_SHUTDOWN_TIMEOUT=180
```

## CONTAINER_NETWORK_NAME

This variable defines the container hostname.  
Using the host network is the best choice for a single Domino container running in a container.  
In this case, you don't need to expose individual ports.  
But this will make all ports inside the container available on the Linux host.

In addition, if the firewall is running, you have to open ports individually.  
On the other side, the host network doesn't use network address translation.  
The host network configuration allows seeing external IP addresses 1:1 inside the container.  
This is important for IP address logging.

```
CONTAINER_NETWORK_NAME=host
```


## CONTAINER_PORTS

If not specifying the host network, ports need to be exported explicitly.  
Ports you export from your container are automatically added to your host firewall, which makes them available externally.

Example for container network

```
CONTAINER_PORTS="-p 1352:1352 -p 80:80 -p 443:443"
```

## CONTAINER_VOLUMES

Volumes store persistent data for containers.  
The volume definition is used to map physical volumes or container volumes.

Container volume

```
CONTAINER_VOLUMES="-v local-domino:/local"
```

Physical volumes

```
CONTAINER_VOLUMES="-v /local/notesdata:/local/notesdata -v /local/translog:/local/translog -v /local/daos:/local/daos "
```

## CONTAINER_ENV_FILE

An environment file is used for the first container start (run) to pass setup parameters.  
The new configuration uses a JSON OneTouch automation setup. Just run domino_container setup.

Examples:

```
CONTAINER_ENV_FILE=env_container
CONTAINER_ENV_FILE=env_container_domino12
```

## CONTAINER_RESTART_POLICY

By default, the Docker daemon does not start containers automatically.  
The Docker Restart policy defines if and when containers are started or restarted.  
This option allows setting the restart policy.

```
CONTAINER_RESTART_POLICY=unless-stopped
CONTAINER_RESTART_POLICY=on-failure:3
```

## BORG_BACKUP

The Domino Community container supports a Borg Backup using an optional build option.  
For Domino V12 Borg Backup restore support the FUSE device is required.  
This option enables the FUSE device when running the container.

```
BORG_BACKUP=yes
```

## EDIT_COMMAND

By default **vi** is used for all edit operations.  
The configuration option allows switching to a different editor.

```
EDIT_COMMAND=nano
```

