#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2024 - APACHE 2.0 see LICENSE
############################################################################

adduser nginx -D

apk update
apk add openresty openresty-mod-http-lua envsubst openssl curl bash jq libcap apache2-utils

cd /

mv nginx.conf /etc/nginx/nginx.conf
mv domdownloadsrv.cfg /etc/nginx
mv domdownload.sh /usr/local/bin/domdownload

mkdir -p /etc/nginx/conf.d
mkdir -p /var/tmp/nginx
mkdir -p /var/log/nginx

chown -R 1000:1000 /etc/nginx/conf.d
chown -R 1000:1000 /var/tmp/nginx
chown -R 1000:1000 /var/log/nginx

chmod 555 /usr/local/bin/domdownload
chmod 555 /entrypoint.sh

setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx
apk del libcap

unlink "$0"

