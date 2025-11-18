#!/bin/bash
SCRIPT_NAME=$(readlink -f $0)
SCRIPT_DIR=$(dirname $SCRIPT_NAME)


###########################################################################
# Domino One-Touch JSON remote setup configuration script                 #
# Helper Script to send OTS JSON to a remotely running domsetup.sh        #
#                                                                         #
# (C) Copyright Daniel Nashed/NashCom 2025                                #
#                                                                         #
# Licensed under the Apache License, Version 2.0 (the "License");         #
# you may not use this file except in compliance with the License.        #
# You may obtain a copy of the License at                                 #
#                                                                         #
#      http://www.apache.org/licenses/LICENSE-2.0                         #
#                                                                         #
# Unless required by applicable law or agreed to in writing, software     #
# distributed under the License is distributed on an "AS IS" BASIS,       #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.#
# See the License for the specific language governing permissions and     #
# limitations under the License.                                          #
###########################################################################


log()
{
  echo "$@"
}


log_debug()
{
  if [ "$DOMSETUP_LOG" = "2" ]; then
    log "$@"
  fi
}


log_space()
{
  log
  log "$@"
  log
}


delim()
{
  log  "------------------------------------------------------------"
}


header()
{
  log
  delim
  log $@
  delim
  log
}


remove_file()
{
  if [ -z "$1" ]; then
    return 1
  fi

  if [ ! -e "$1" ]; then
    return 2
  fi

  rm -f "$1"

  if [ ! "$?" = "0" ]; then
    log_space "Cannot delete file: $1"
    return 3
  fi

  return 0
}


set_curl_option()
{
  if [ -z "$1" ]; then
    export DOMSETUP_CURL_OPTIONS=
    return
  fi

  if [ -z "$DOMSETUP_CURL_OPTIONS" ]; then
    export DOMSETUP_CURL_OPTIONS="$1"
  else
    export DOMSETUP_CURL_OPTIONS="$DOMSETUP_CURL_OPTIONS $1"
  fi

  log_debug "DOMSETUP_CURL_OPTIONS: [$DOMSETUP_CURL_OPTIONS]"
}


show_cert()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  openssl x509 -in "$1" -noout > /dev/null 2>&1

  if [ "$?" != "0" ]; then
    log_space "No certificates found"
    exit 1
  fi

  local SAN=$(openssl x509 -in "$1" -noout -ext subjectAltName | grep "DNS:" | xargs )
  local SUBJECT=$(openssl x509 -in "$1" -noout -subject | cut -d '=' -f 2- )
  local ISSUER=$(openssl x509 -in "$1" -noout -issuer | cut -d '=' -f 2- )
  local EXPIRATION=$(openssl x509 -in "$1" -noout -enddate | cut -d '=' -f 2- )
  local FINGERPRINT=$(openssl x509 -in "$1" -noout -fingerprint | cut -d '=' -f 2- )
  local SERIAL=$(openssl x509 -in "$1" -noout -serial | cut -d '=' -f 2- )

  header "Certificate [$1]"
  log "SAN         : $SAN"
  log "Subject     : $SUBJECT"
  log "Issuer      : $ISSUER"
  log "Expiration  : $EXPIRATION"
  log "Fingerprint : $FINGERPRINT"
  log "Serial      : $SERIAL"
  log
}


check_domsetup_ready()
{
  if [ -z "$CURL_AUTHORIZATION" ]; then
    HTTP_RESPONSE=$(curl -s $DOMSETUP_CURL_OPTIONS "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/status" --show-error -w "\n%{http_code}\n" 2>&1)
  else
    HTTP_RESPONSE=$(curl -s $DOMSETUP_CURL_OPTIONS "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/status" -H "Authorization: $CURL_AUTHORIZATION" --show-error -w "\n%{http_code}\n" 2>&1)
  fi

  CURL_STATUS=$?
  log_debug "CURL_STATUS: [$CURL_STATUS]"
}


get_variable()
{
  local VAR_NAME=$1
  local PROMPT=$2
  local DEFAULT=$3
  local OPTION=$4
  local CURRENT_VALUE=
  local NEW_VALUE=

  # Never prompt
  if [ "$DOMSETUP_NOPROMPT" = "2" ]; then
    return 1
  fi

  if [ -z "$VAR_NAME" ]; then
    return 1
  fi

  CURRENT_VALUE=${!VAR_NAME}

  if [ -n "$CURRENT_VALUE" ]; then

    if [ "$OPTION" = "OnlyIfEmpty" ]; then
      return 1
    fi

    if [ "$DOMSETUP_NOPROMPT" = "1" ]; then
      return 1
    fi
  fi

  if [ -z "$DEFAULT" ]; then
    DEFAULT=${CURRENT_VALUE}
  fi

  if [ -z "$PROMPT" ]; then
    PROMPT=$VAR_NAME
  fi

  PROMPT=$(printf "%-9s" "$PROMPT")

  if [ "$(uname)" = "Darwin" ]; then
    read -p "$PROMPT: " NEW_VALUE
  else
    read -p "$PROMPT: " -e -i "$DEFAULT" NEW_VALUE
  fi

  export $1="$NEW_VALUE"
  return 0
}


domsetup()
{
  # Ensure not getting any caller curl options which might include to allow insecure connections
  export DOMSETUP_CURL_OPTIONS=

  if [ -z "$DOMSETUP_HTTPS_PORT" ]; then
    DOMSETUP_HTTPS_PORT=1352
  fi

  if [ -z "$DOMSETUP_USER" ]; then
    DOMSETUP_USER=admin
  fi

  if [ -z "$DOMSETUP_CACERT_FILE" ]; then
    DOMSETUP_CACERT_FILE=/tmp/domsetup_cacert.pem
  fi

  echo

  get_variable DOMSETUP_OTS_JSON_FILE "OTS-JSON"

  if [ -z "$DOMSETUP_OTS_JSON_FILE" ]; then
    log_space " No DOMSETUP_OTS_JSON_FILE defined"
    return 1
  fi

  if [ ! -e "$DOMSETUP_OTS_JSON_FILE" ]; then
    log_space " No OTS JSON file not found: $DOMSETUP_OTS_JSON_FILE"
    return 1
  fi

  if [ -z "$DOMSETUP_HOST" ]; then
    DOMSETUP_HOST=$(cat "$DOMSETUP_OTS_JSON_FILE" | jq -r .serverSetup.network.hostName)
  fi

  get_variable DOMSETUP_HOST "Host"
  get_variable DOMSETUP_IP "Address"
  get_variable DOMSETUP_HTTPS_PORT "Port"
  get_variable DOMSETUP_BEARER "Bearer"

  if [ -z "$DOMSETUP_BEARER" ]; then
    get_variable DOMSETUP_USER "User"
    get_variable DOMSETUP_PASSWORD "Password"
  fi

  get_variable DOMSETUP_SERVER_ID "ServerID"

  if [ -n "$DOMSETUP_PASSWORD" ]; then
    CURL_AUTHORIZATION="Basic $(echo -n "$DOMSETUP_USER:$DOMSETUP_PASSWORD" | base64)"
  elif [ -n "$DOMSETUP_BEARER" ]; then
    CURL_AUTHORIZATION="Bearer $DOMSETUP_BEARER"
  fi

  if [ -n "$DOMSETUP_IP" ]; then
    set_curl_option "--connect-to $DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT:$DOMSETUP_IP:$DOMSETUP_HTTPS_PORT"
  fi

  if [ ! -e "$DOMSETUP_OTS_JSON_FILE" ]; then
    log_space "OTS JSON file not found: $DOMSETUP_OTS_JSON_FILE"
    return 1
  fi

  if [ -n "$DOMSETUP_SERVER_ID" ]; then
    if [ ! -e "$DOMSETUP_SERVER_ID" ]; then
      log_space "server.id not found: $DOMSETUP_SERVER_ID"
      return 1
    fi
  fi

  set_curl_option "--connect-timeout 5"

  if [ -z "$DOMSETUP_IP" ]; then
    log_space "Checking if server is ready for setup at $DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT ..."
  else
    log_space "Checking if server is ready for setup at $DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT (IP: $DOMSETUP_IP) ..."
  fi

  check_domsetup_ready

  if [ "$CURL_STATUS" = "60" ]; then
    log_space "Certificate is not trusted"

    if [ -z "$DOMSETUP_IP" ]; then
      OPENSSL_CONNECT="$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT"
    else
      OPENSSL_CONNECT="$DOMSETUP_IP:$DOMSETUP_HTTPS_PORT"
    fi

    openssl s_client -servername $DOMSETUP_HOST --connect "$OPENSSL_CONNECT" -showcerts  </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/{x=""} {x = x $0 ORS} /END CERTIFICATE/{last=x} END{print last}' > "$DOMSETUP_CACERT_FILE"
    show_cert "$DOMSETUP_CACERT_FILE"

    local QUESTION=
    echo
    read -p "Trust certificate : (yes/no) ? " QUESTION

    if [ "$QUESTION" = "yes" ] || [ "$QUESTION" = "y" ]; then
      set_curl_option "--cacert $DOMSETUP_CACERT_FILE"
    else
      log_space "Terminating setup"
      remove_file "$DOMSETUP_CACERT_FILE"
      return 2
    fi

    # Now try again
    check_domsetup_ready
  fi

  HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)
  HTTP_TEXT=$(echo "$HTTP_RESPONSE" | head -1)

  log_debug "HTTP-Status: [$HTTP_STATUS]"

  if [ "$HTTP_STATUS" = "401" ]; then
    log_space "Not authorized to use DomSetup"
    return 3
  fi

  if [ "$HTTP_STATUS" != "202" ]; then
    log
    if [ "$HTTP_STATUS" = "000" ]; then
      log "Remote server is not ready for DomSetup"
    else
      log "Remote server is not ready for DomSetup ($HTTP_STATUS)"
    fi
    log
    log "$HTTP_TEXT"
    log
    return 4
  fi

  # Upload server.id first if specified
  if [ -n "$DOMSETUP_SERVER_ID" ]; then

    SERVER_ID_SHA256=$(sha256sum "$DOMSETUP_SERVER_ID" | cut -f1 -d' ')
    log_debug "Local server.id checksum: $SERVER_ID_SHA256"

    if [ -z "$CURL_AUTHORIZATION" ]; then
      HTTP_RESPONSE=$(curl -s $DOMSETUP_CURL_OPTIONS -X POST --data-binary "@$DOMSETUP_SERVER_ID" -H "Content-Type: application/octet-stream" "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/serverid" --show-error -w "\n%{http_code}\n")
    else
      HTTP_RESPONSE=$(curl -s $DOMSETUP_CURL_OPTIONS -X POST --data-binary "@$DOMSETUP_SERVER_ID" -H "Content-Type: application/octet-stream" "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/serverid" -H "Authorization: $CURL_AUTHORIZATION" --show-error -w "\n%{http_code}\n")
    fi

    CURL_STATUS=$?
    log_debug "CURL_STATUS: [$CURL_STATUS]"

    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)
    HTTP_TEXT=$(echo "$HTTP_RESPONSE" | head -1)

    if [ "$HTTP_STATUS" = "200" ]; then

      log_debug "$HTTP_TEXT"

      if [ -n "$(echo "$HTTP_TEXT" | grep "$SERVER_ID_SHA256")" ]; then
        log_space "Server.ID upload successful (hash verified)."
      else
        log_space "Server.ID upload failed: [$HTTP_STATUS] $HTTP_TEXT"
        return 5
      fi

    else
      log_space "Server.ID upload failed: [$HTTP_STATUS] $HTTP_TEXT"
      return 5
    fi
  fi

  if [ -z "$CURL_AUTHORIZATION" ]; then
    HTTP_RESPONSE=$(curl -s $DOMSETUP_CURL_OPTIONS -X POST --data-binary "@$DOMSETUP_OTS_JSON_FILE" -H "Content-Type: application/octet-stream" "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/ots" --show-error -w "\n%{http_code}\n")
  else
    HTTP_RESPONSE=$(curl -s $DOMSETUP_CURL_OPTIONS -X POST --data-binary "@$DOMSETUP_OTS_JSON_FILE" -H "Content-Type: application/octet-stream" "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/ots" -H "Authorization: $CURL_AUTHORIZATION" --show-error -w "\n%{http_code}\n")
  fi

  CURL_STATUS=$?
  log_debug "CURL_STATUS: [$CURL_STATUS]"

  HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)
  HTTP_TEXT=$(echo "$HTTP_RESPONSE" | head -1)

  if [ "$HTTP_STATUS" = "200" ]; then
    log_space "$HTTP_TEXT"
    log_space "Setup completed"
    return 0
  fi

  log_space "DomSetup failed: [$HTTP_STATUS] $HTTP_TEXT"
  return 5
}

usage()
{

  header "Domino One-Touch JSON remote setup configuration script"
  echo "Usage: $(basename $SCRIPT_NAME) <ots.json> <server.id> [options]"
  echo
  echo "Command line parameters"
  echo "-----------------------"
  echo
  echo "-ots/json=<file name>)       Manually specified server OTS JSON"
  echo "-serverid=<id file name>)    Optional Server.ID to upload"
  echo "-host=<host name>            Host name (default: read from OTS JSON)"
  echo "-ip=<address>                Optional IP address or DNS name to connect to"
  echo "-port=<port number>          TCP/IP port to connect to (default: 1352)"
  echo "-bearer=<bearer token>       Bearer token for authentication"
  echo "-user=<username>             User name for authentication (default: admin)"
  echo "-password=<password>         Password for authentication"
  echo "-prompt                      Interactively prompt for all parameters"
  echo "-promptempty                 Interactively prompt for empty parameters only"
  echo "-silent                      Do not prompt"
  echo "-reset                       Remove existing OTS file and restart configuration"
  echo
  echo "Environment variables"
  echo "---------------------"
  echo

  echo "DOMSETUP_OTS_JSON_FILE       OTS JSON File (if not set uses: DOMINO_AUTO_CONFIG_JSON_FILE)"
  echo "DOMSETUP_SERVER_ID           Server.ID"
  echo "DOMSETUP_HOST                Host name"
  echo "DOMSETUP_IP                  IP address"
  echo "DOMSETUP_HTTPS_PORT          TCP/IP port"
  echo "DOMSETUP_BEARER              Bearer token"
  echo "DOMSETUP_USER                User name"
  echo "DOMSETUP_PASSWORD            Password"
  echo "DOMSETUP_NOPROMPT            0=always prompt, 1=only prompt if empty, 2=never prompt"
  echo "DOMSETUP_RESET_OTS=1         Remove existing OTS file and restart configuartion"
  echo
}

# --- Main ---

if [ -n "$1" ]; then
  DOMSETUP_NOPROMPT=2
fi

for a in "$@"; do

  p=$(echo "$a" | awk '{print tolower($0)}')

  case "$p" in

    -prompt)
      DOMSETUP_NOPROMPT=0
      ;;

    -promptempty)
      DOMSETUP_NOPROMPT=1
      ;;

    -silent)
      DOMSETUP_NOPROMPT=2
      ;;

    -serverid=*|-id=*)
      DOMSETUP_SERVER_ID=$(echo "$a" | cut -f2 -d= -s)
      ;;

    *.id)
      DOMSETUP_SERVER_ID="$a"
      ;;

    -ots=*|-json=*)
      DOMSETUP_OTS_JSON_FILE=$(echo "$a" | cut -f2 -d= -s)
      ;;

    *.json)
      DOMSETUP_OTS_JSON_FILE="$a"
      ;;

    -host=*)
      DOMSETUP_HOST=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -ip=*)
      DOMSETUP_IP=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -port=*)
      DOMSETUP_HTTPS_PORT=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -bearer=*)
      DOMSETUP_BEARER=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -user=*)
      DOMSETUP_USER=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -password=*)
      DOMSETUP_PASSWORD=$(echo "$a" | cut -f2 -d= -s)
      ;;

    # Passthru options for OTS setup script
    https://*|http://*|file:/*|auto|remote|local)
      DOMSETUP_OTS_OPTIONS="$a"
      ;;

    -reset)
      DOMSETUP_RESET_OTS=1
      ;;

    -h|/h|-?|/?|-help|--help|help|usage)
      usage
      exit 0
      ;;

    *)
      log_space "Invalid parameter [$a]"
      exit 1
      ;;
  esac
done

if [ -z "$DOMSETUP_OTS_JSON_FILE" ]; then

  if [ -n "$DOMINO_AUTO_CONFIG_JSON_FILE" ]; then
    DOMSETUP_OTS_JSON_FILE="$DOMINO_AUTO_CONFIG_JSON_FILE"
  else
    DOMSETUP_OTS_JSON_FILE=/tmp/domsetup.json
  fi
fi

log_debug "DOMSETUP_OTS_OPTIONS: [$DOMSETUP_OTS_OPTIONS]"


if [ "$DOMSETUP_RESET_OTS" = "1" ]; then
  remove_file "$DOMSETUP_OTS_JSON_FILE"
  log_space "Info: Removed existing OTS file: $DOMSETUP_OTS_JSON_FILE"
fi

if [ ! -e "$DOMSETUP_OTS_JSON_FILE" ]; then
  "$SCRIPT_DIR/DominoOneTouchSetup.sh" $DOMSETUP_OTS_OPTIONS
elif [ -n "$DOMSETUP_OTS_OPTIONS" ]; then
  "$SCRIPT_DIR/DominoOneTouchSetup.sh" $DOMSETUP_OTS_OPTIONS
  echo "$SCRIPT_DIR/DominoOneTouchSetup.sh" $DOMSETUP_OTS_OPTIONS
fi

header "Domino Remote OTS Setup"

domsetup
exit "$?"


