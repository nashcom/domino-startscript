# Domino Download Server

The Domino Download Server provides download functionality for different type of clients intended for company internal downloads

- Downloading software by filename via Curl command line or browser
- Domino Download Script
- Domino AutoUpdate

The container image implements the MyHCLSoftware compatible end-points to allow downloads from Domino AutoUpdate.
It also provides `product.jwt` and `software.jwt` which is required for Domino AutoUpdate.
A Domino AutoUpdate server can be pointed directly to the server using the official DNS names by setting them in the hostfile of the Domino server.

The container image is self contained. It just requires mounts for storing data and optionally a corporate certificate (or operates with it's own MicroCA).


## Technology used

The server is based on an [Alpine](https://alpinelinux.org/) container running NGINX (openresty).
[openresty](https://openresty.org) is used because the logic is implemented in [LUA](https://www.lua.org/) programming language.
Is leveraging the Domino Download script, which is invoked from NGINX via LUA blocks.


## How to build the Container Image

Run the following command to build the image

```
./build.sh
```

The resulting image is called **nashcom/domdownload:latest** by default


## domdownloadctl - Domino Download Control Script

The **domdownloadctl** is a script to provide a single entrypoint for start, stop and maintain the container.

The script can be installed via `./domdownloadctl install`

Once configured the server can be started via

```
domdownloadctl start
```


### Additional Commands

```
Usage: domdownloadctl [Options]

start      start the container
stop       stop the container
bash       start a bash in the container with the standard 'nginx' user
bash root  start a bash with root
rm         remove the container (even when running)

log        show the NGINX server log (container output)
cfg        edit configuration
info       show information about the configuration
du|ncdu    snow the space used SOFTWARE_DIR. Either a 'du' summary or 'ncdu'
allow      edit the allow list
adduser    add a new HTTP user
access     show access lines. Optionally specify the number of lines or 'f' to follow the log
```

## Request Endpoints

All endpoints are protected either by IP address or basic authentication.
The **/about** endpoint prints the version of Domino Download.

If MyHCLSoftware API integrated is enabled the following additional endpoints are available:

- /v1/apitokens/exchange 
- /v1/files/
- /software.jwt
- /product.jwt

All other requests are passed to the software directory, which is the data root of the NGINX server.


## Configuration


## Configure Access

By default the server provides access for the loopback IP **127.0.0.1** only.  
Additional IP addresses and ranges can be configured via **allow.access**.  
The configuration can be specified using the `domdownloadctl allow` command.

In addition a HTTP password file can be configured using the `domdownloadctl adduser` command  (htpasswd).


## Mount points

All mount points can be configured in the DomDownloadServer configuration and ship with a reasonable default (See "Host" in the list below).

- **DOMDOWNLOADSRV_DIR**  
Configuration directory holding configuration data for the server and **domdownload**
Host: `/local/software`  
Container: `/etc/nginx/conf.d` and `/home/nginx/.DominoDownload`

- **SOFTWARE_DIR**  
Software directory to store web-kits  
Host: `/local/software`  
Container: `/local/software`

- **DOMDOWNLOADSRV_LOG**  
Server log directory containing NGINX logs including access.log  
Host: `/var/log/domdownloadsrv`  
Container: `/tmp/nginx`


## Configuration

- **CONTAINER_HOSTNAME**  
Container Host name  
If no host name is specified Linux hostname is used

- **CONTAINER_NAME**  
Container name  
default: domdownload

- **CONTAINER_IMAGE**  
Container image name. Should not be needed to change  
default: nashcom/domdownload:latest

- **CONTAINER_NETWORK_NAME**  
Container network name. By default the container uses the host mode to have access to request IP addresses

- **USE_DOCKER**  
Override container environment to use Docker if also Podman is installed

- **NGINX_LOG_LEVEL**=notice  
NGINX server log level


### NGINX Log Levels

- **debug**  - Useful debugging information to help determine where the problem lies
- **info**   - Informational messages that aren't necessary to read but may be good to know
- **notice** - Something normal happened that is worth noting
- **warn**   - Something unexpected happened, however is not a cause for concern
- **error**  - Something was unsuccessful
- **crit**   - There are problems that need to be critically addressed
- **alert**  - Prompt action is required
- **emerg**  - The system is in an unusable state and requires immediate attention


## Hostname and Port and Network

The default hostname is the hostname of the Linux container. The port used is `8888`.
The recommended configuration uses the container host mode to have full access to the true IP address to allow IP based authentication.
If no IP based authentication is required and a server in front of it (like another NGINX server) the server can also use a container network and map the default port `8888` to another port.


## TLS/SSL Certificate

The server can use a PEM based certificate and key specified in the configuration volume.
If not certificate is specified the server generates it's own MicroCA and a TLS certificate for the server.

For the MyHCLSoftware integration a wild card certificate for `*.hcltechsw.com` is generated to provide a local instance of the MyHCLSoftware portal.
The root certificate generated by the container automatically is displayed on startup and need to be imported into the Domino directory as a trusted root.


## Authentication/Authorization

Download requests must be always authorized. This is specially important in case the server is internet facing.
But also internally the server should only allow authorized access.

The server currently supports access control using basic authentication or IP address.
By default only **127.0.0.1** is allowed. You can either add another load balancer for example NGINX in front of it or run it natively.


## Configure AutoUpdate to use the Domino Download Server


### Configure the Container

The functionality is disabled by default, because it requires port 443.
A separate configuration is available in the GitHub project to enable the required redirecty on port 443.

To enable the functionality copy `hcltechsw.cfg` into the configuration directory.
Once available the `/entrypoint.sh` script automatically generates a wild card certificate for `*.hcltechsw.com`.

In case other services require **port 443** the configuration can be extended or moved into a different NGINX instance.
This integration only provides the required redirect functionality to provide the required endpoints to provide MyHCLSoftware functionality.


### Configure the Domino AutoUpdate Server

Point your Domino server running Domino AutoUpdate to the IP of the Domino Download Server for the following two DNS names:

- api.hcltechsw.com
- ds-infolib.hcltechsw.com

Import the trusted root for the MicroCA created by the server automatically into Domino Directory into Internet Certificates

Add the IP address of your Domino AutoUpdate Server to the allow list of the NGINX server configuration.
No other configuration option is needed.

To get the integration configured create a customized `hcltechsw.conf` in the configuration directory.
The default name `domdownload.myserver.lab` needs to be replaced with your server name.



