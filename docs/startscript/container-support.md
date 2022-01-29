---
layout: default
title: Domino Container/Docker Support
nav_order: 6
description: "Domino Container/Docker Support for Docker/Podman & Kubernetes environments"
parent: "Domino Start Script"
has_children: false
---

# Domino Container/Docker Support

This start script supports Domino on Docker and other container environments like Podman.
The configuration differs from classical way to run the start script.
The install_script and also the start script detects a Docker configuration.
And will work according the the requirements of a Docker environment.

For Domino on Docker a separate entry point is needed to start the server.
Images derived from CentOS 7.4 and higher are supported.

A Docker image doesn't have a full systemd implementation and start/stop cannot be implemented leveraging systemd.
Therefore the start script comes with a separate Docker entry point script `domino_docker_entrypoint.sh`
The script can be used in your Docker build script and you can include the start script into your own Docker images.

The entry point script takes care of start and stop of the server by invoking the rc_domino_start script directly.
You can still use rc_domino (or the new alias domino) to interact with your server once you started a shell inside the container.

In addition the script also supports remote setup of a Domino server.  
If no names.nsf is located in the data directory it puts the server into listen mode for port 1352 for remote server setup.

You an add your own configuration script `/docker_prestart.sh` to change the way the server is configured.  
The script is started before this standard operations.
If the file `/docker_prestart.sh` is present in the container and the server is not yet setup, the script is executed first.

The output log of the Domino server is still written to the notes.log files.
And the only output you see in from the entry point script are the start and stop operations.

If you want to interact with the logs or use the monitor command, you can use a shell inside the container.
Using a shell you can use all existing Start Script commands.
But you should stop the Domino server by stopping the container and not use the 'stop' command provided by the start script.

## !! Important information !!

Docker has a very short default shutdown timeout!
When you stop your container Docker will send a `SIGTERM` to the entry point.
After waiting for 10 seconds Docker will send a `SIGKILL` signal to the entry point!!

This would cause an unclean Domino Server shutdown!

The entrypoint script is designed to catch the signals, but the server needs time to shutdown!

So you should stop your Domino Docker containers always specifying the `--time` parameter to increase the shutdown grace period.

Example:

```
docker stop --time=60 domino
```

Will wait for **60 seconds** until the container is killed.

## Additonal Docker Start Script Configuration

There is a special configuration option for start script parameters for Docker.  
Because the `rc_domino_config` file is read-only, on Docker you can specify an additional config file
in your data directory which is usually configured to use a persistent volume which isn't part of the container.  
This allows you to set new parameters or override parameters from the default config file.
