---
layout: default
title: Systemd configuration
nav_order: 4
description: "Special systemd configuration"
parent: "Domino Start Script"
has_children: false
---

# Special systemd configuration

Linux introdued systemd in the following version and is since then the standard used instead of the older init.d functionality

- CentOS 7+ RHEL 7+
- SLES 12+ or higher

`etc/systemd/system/domino.service` contains the configuration for the systemd service.

The following parameters should be reviewed and might need to be configured.
Once you have configured the service you can enable and disable it with systemctl.

```
systemctl enable domino.service
systemctl disable domino.service
```

To check the status use `systemctl status domino.service`.

Description of parameters used in `domino.service`.

```
User=notes
```

This is the Linux user name that your partition runs with.

```
LimitNOFILE=80000
```

With systemd the security limit configuration is not used anymore and the limits
are enforced by systemd. You should configure at least `80000` files.
Files means file handles and also TCP/IP sockets!

```
LimitNPROC=8000
```

With systemd the security limit configuration is not used anymore and the limits
are enforced by systemd. Even Domino uses pthreads you should ensure that you have
sufficient processes configured because the limit does not specify the number of
processes but the number of threads that the "notes" user is allowed to use!

```
TasksMax=8000
```

The version of systemd shipped in SLES 12 SP2 uses the PIDs cgroup controller.
This provides some per-service fork() bomb protection, leading to a safer system.
It controls the number of threads/processes a user can use.
To control the default TasksMax= setting for services and scopes running on the system,
use the `system.conf` setting `DefaultTasksMax=`.

This setting defaults to `512`, which means services that are not explicitly configured otherwise
will only be able to create `512` processes or threads at maximum.
The domino.service sets this value for the service to `8000` explicitly.
But you could also change the system wide setting.
CentOS / RHEL versions also support `TaskMax` and the setting is required as well.

Note: If you are running an older version `TaskMax` might not be supported and you have to remove the line from the domino.service

```
#Environment=LANG=en_US.UTF-8
#Environment=LANG=de_DE.UTF-8
```

You can specify environment variables in the systemd service file.
Depending on your configuration you might want to set the `LANG` variable to define your locale.
But in normal cases it should be fine to set it in the profile.

```
PIDFile=/local/notesdata/domino.pid
```

This PIDFile has to match the configured DOMINO_PID_FILE ins the start script.
By default the name is "domino.pid" in your data directory.
You can change the location if you set the configuration variable "DOMINO_PID_FILE"
to override the default configuration if really needed.

```
ExecStart=/opt/nashcom/startscript/rc_domino_script start
ExecStop=/opt/nashcom/startscript/rc_domino_script stop
```

Those two lines need to match the location of the main domino script including the start/stop command parameter.

`TimeoutSec=100`


Time-out value for starting the service

`TimeoutStopSec=300`

Time-out value for stopping the service
