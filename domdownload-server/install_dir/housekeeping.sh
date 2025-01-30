#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2025 - APACHE 2.0 see LICENSE
############################################################################

# This script is a housekeeping script running in background for periodic operations

# Update MHS Catalog at startup and periodically

if [ -z "$MHS_REFRESH_INTERVAL" ]; then
  # 15 minutes default
  MHS_REFRESH_INTERVAL=900
fi

/upd_catalog.sh -v >/tmp/nginx/upd_catalog.log  2>&1

seconds=0

while true; do

  if [ "$seconds" -ge "$MHS_REFRESH_INTERVAL" ]; then
    date  >> /tmp/housekeeping.log
    /upd_catalog.sh -v >/tmp/nginx/upd_catalog.log  2>&1
    seconds=0
  fi

  sleep 1
  seconds=$(expr $seconds + 1)

done
