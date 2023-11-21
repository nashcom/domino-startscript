#!/bin/bash

DOMINO_SNMP_SYSTEMD_NAME=dominosnmp
DOMINO_SNMP_SYSTEMD_FILE=$DOMINO_SNMP_SYSTEMD_NAME.service
DOMINO_SNMP_SYSTEMD_FILEPATH=/etc/systemd/system/$DOMINO_SNMP_SYSTEMD_FILE
SNMPD_CONF=/etc/snmp/snmpd.conf


log ()
{
  echo
  echo "$@"
  echo
}

log_error()
{
  log "$@"
  exit 1
}


if [ ! -e "$SNMPD_CONF" ]; then
  log_error "SNMP Agent not installed" 
fi

if [ -n "$(grep "smuxpeer 1.3.6.1.4.1.334.72" "$SNMPD_CONF")" ]; then
  log "Domino SNMP settings already set in $SNMPD_CONF"

else
  echo >> "$SNMPD_CONF"
  echo "# Allow HCL Domino SNMP SMUX (lnsnmp)" >> "$SNMPD_CONF"
  echo "smuxpeer 1.3.6.1.4.1.334.72 NotesPasswd" >> "$SNMPD_CONF"
  echo >> "$SNMPD_CONF"

  systemctl restart snmpd
fi


cp $DOMINO_SNMP_SYSTEMD_FILE $DOMINO_SNMP_SYSTEMD_FILEPATH 
chown root:root $DOMINO_SNMP_SYSTEMD_FILEPATH
chmod 644 $DOMINO_SNMP_SYSTEMD_FILEPATH

systemctl daemon-reload
systemctl enable $DOMINO_SNMP_SYSTEMD_NAME

log "Starting Domino SNMP agent..."

systemctl restart $DOMINO_SNMP_SYSTEMD_NAME
systemctl status $DOMINO_SNMP_SYSTEMD_NAME

log "Note: Ensure that the quryset and intrcpt server tasks are started on your Domino server"

