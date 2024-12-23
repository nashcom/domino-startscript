#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2024 - APACHE 2.0 see LICENSE
############################################################################

# This script is the main entry point for the NGINX container.
# The entry point is invoked by the container run-time to start NGINX.


log_space()
{
  echo
  echo "$@"
  echo
}

log_error()
{
  echo
  echo "ERROR - $@"
  echo
}

delim()
{
  echo  "------------------------------------------------------------"
}


header()
{
  echo
  delim
  echo "$@"
  delim
  echo
}


create_local_ca_cert()
{
  local SERVER_HOST="$1"  
  local PREFIX=

  if [ -z "$1" ]; then
    SERVER_HOST=$(hostname -f)  
  fi

  if [ -n "$2" ]; then
    PREFIX="$2_"
  fi

  if [ -z "$CERT_ORG" ]; then
    local CERT_ORG=DominoDownloadServer
  fi

  if [ -z "$CA_CN" ]; then
    local CA_CN=MicroCA
  fi

  local SERVER_CRT=/etc/nginx/conf.d/${PREFIX}cert.pem
  local SERVER_KEY=/etc/nginx/conf.d/${PREFIX}key.pem
  local SERVER_CSR=/etc/nginx/conf.d/${PREFIX}csr.pem

  local CA_KEY=/etc/nginx/conf.d/ca_key.pem
  local CA_CRT=/etc/nginx/conf.d/ca_cert.pem
  local CA_SEQ=/etc/nginx/conf.d/ca.seq

  if [ ! -e "$CA_KEY" ]; then
    echo "Creating CA key: $CA_KEY"
    openssl ecparam -name prime256v1 -genkey -noout -out $CA_KEY > /dev/null 2>&1 
  fi

  if [ ! -e "$CA_CRT" ]; then
    echo "Create CA certificate: $CA_CRT"
    openssl req -new -x509 -days 3650 -key $CA_KEY -out $CA_CRT -subj "/O=$CERT_ORG/CN=$CA_CN" > /dev/null 2>&1
  fi

  # Create server key
  if [ ! -e "$SERVER_KEY" ]; then
    echo "Create server key: $SERVER_KEY"
    openssl ecparam -name prime256v1 -genkey -noout -out $SERVER_KEY > /dev/null 2>&1
  fi

  openssl req -new -key $SERVER_KEY -out $SERVER_CSR -subj "/O=$CERT_ORG/CN=$SERVER_HOST" -addext "subjectAltName = DNS:$SERVER_HOST" -addext extendedKeyUsage=serverAuth > /dev/null 2>&1

  echo "Creating server certificate: $SERVER_CRT"

   # NOTE: Copying extensions can be dangerous! Requests should be checked
  openssl x509 -req -days 365 -in $SERVER_CSR -CA $CA_CRT -CAkey $CA_KEY -out $SERVER_CRT -CAcreateserial -CAserial $CA_SEQ -copy_extensions copy > /dev/null 2>&1

  rm -f "SERVER_CSR"
}


show_cert()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  local SAN=$(openssl x509 -in "$1" -noout -ext subjectAltName | grep "DNS:" | xargs )
  local SUBJECT=$(openssl x509 -in "$1" -noout -subject | cut -d '=' -f 2- )
  local ISSUER=$(openssl x509 -in "$1" -noout -issuer | cut -d '=' -f 2- )
  local EXPIRATION=$(openssl x509 -in "$1" -noout -enddate | cut -d '=' -f 2- )
  local FINGERPRINT=$(openssl x509 -in "$1" -noout -fingerprint | cut -d '=' -f 2- )
  local SERIAL=$(openssl x509 -in "$1" -noout -serial | cut -d '=' -f 2- )

  echo "SAN         : $SAN"
  echo "Subject     : $SUBJECT"
  echo "Issuer      : $ISSUER"
  echo "Expiration  : $EXPIRATION"
  echo "Fingerprint : $FINGERPRINT"
  echo "Serial      : $SERIAL"
}


# --- Main ---

# Configure defaults

if [ -z "$NGINX_LOG_LEVEL" ]; then
  export NGINX_LOG_LEVEL=notice
fi

if [ -z "$NGINX_PORT" ]; then
  export NGINX_PORT=8888
fi

if [ -z "$DOMDOWNLOADSRV_HOST" ]; then
  export DOMDOWNLOADSRV_HOST=$(hostname -f)
fi


# Substistute variables and create configuration


# Names which need to stay untranslated

export name='$name'
export request_uri='$request_uri'

envsubst < /etc/nginx/domdownloadsrv.cfg > /etc/nginx/conf.d/domdownloadsrv.conf

if [ -e /etc/nginx/conf.d/hcltechsw.cfg ]; then
  envsubst < /etc/nginx/conf.d/hcltechsw.cfg > /etc/nginx/conf.d/hcltechsw.conf 
fi

export name=
export request_uri=

LINUX_PRETTY_NAME=$(cat /etc/os-release | grep "PRETTY_NAME="| cut -d= -f2 | xargs)

# Set more paranoid umask to ensure files can be only read by user
umask 0077

# Create log directory with owner nginx
mkdir -p /tmp/nginx
chown nginx:nginx /tmp/nginx

# Write default access configuration example if file is not present 
if [ ! -e /etc/nginx/conf.d/allow.access ]; then
  echo "# allow 192.168.1.42;"   >> /etc/nginx/conf.d/allow.access
  echo "# allow 192.168.1.0/24;" >> /etc/nginx/conf.d/allow.access
fi

echo
echo
echo NGINX Domino Download Server
delim
echo $LINUX_PRETTY_NAME
echo
nginx -V
echo

if [ -z "$SERVER_HOSTNAME" ]; then
  SERVER_HOSTNAME=$(hostname -f)  
fi

if [ ! -e /etc/nginx/conf.d/cert.pem ]; then
  create_local_ca_cert "$SERVER_HOSTNAME"
fi

header "Server Certficiate"
show_cert /etc/nginx/conf.d/cert.pem
echo
delim
echo

if [ -e /etc/nginx/conf.d/hcltechsw.conf ]; then

  create_local_ca_cert "*.hcltechsw.com" hcltechsw
  create_local_ca_cert localhost localhost

  header "MyHCLDownload Integration"
  show_cert /etc/nginx/conf.d/hcltechsw_cert.pem
  echo
  delim
  echo
fi

if [ -e /etc/nginx/conf.d/ca_cert.pem ]; then
  header "MicroCA Root Certificate"
  openssl x509 -in /etc/nginx/conf.d/ca_cert.pem -noout -subject | cut -d '=' -f 2-
  echo
  cat /etc/nginx/conf.d/ca_cert.pem
  echo
fi

echo
echo
echo NGINX Domino Download Server
delim
echo $LINUX_PRETTY_NAME
nginx -v
echo
echo $SERVER_HOSTNAME:$NGINX_PORT
echo
echo

nginx -g 'daemon off;'

# Dump configurations if start failed. Else we are killed before dumping
sleep 2
header "/etc/nginx/nginx.conf"
cat /etc/nginx/nginx.conf

header "/etc/nginx/conf.d"
cat /etc/nginx/conf.d/*

exit 0

