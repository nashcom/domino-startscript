#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2024 - APACHE 2.0 see LICENSE
############################################################################

adduser nginx -D

apk update
apk add openresty openresty-mod-http-lua openssl curl bash jq libcap apache2-utils

cd /

mv nginx.conf /etc/nginx/nginx.conf
chmod 444 /etc/nginx/nginx.conf

mv domdownload.conf /etc/nginx
chown 444 /etc/nginx domdownload.conf

mkdir /etc/nginx/conf.d
chown 444 /etc/nginx/conf.d

mv domdownload.sh /usr/local/bin/domdownload
chmod 555 /usr/local/bin/domdownload

mkdir /var/tmp/nginx
chown 1000:1000 /var/tmp/nginx

setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx
apk del libcap

chmod 555 /entrypoint.sh
chown 1000:1000 /var/log/nginx

unlink "$0"

