#!/bin/bash
SCRIPT_NAME=$(readlink -f $0)
SCRIPT_DIR=$(dirname $SCRIPT_NAME)
VERSION=1.0.1


###########################################################################
# Domino One-Touch JSON remote setup configuration script                 #
# Helper Script to send OTS JSON to a remotely running domsetup.sh        #
#                                                                         #
# (C) Copyright Daniel Nashed/NashCom 2025-2026                           #
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


log_error()
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

  echo "$1" | openssl x509 -noout > /dev/null 2>&1

  if [ "$?" != "0" ]; then
    log_space "No certificates found"
    exit 1
  fi

  local SAN=$(echo "$1" | openssl x509 -noout -ext subjectAltName | grep "DNS:" | xargs )
  local SUBJECT=$(echo "$1" | openssl x509 -noout -subject | cut -d '=' -f 2- )
  local ISSUER=$(echo "$1" | openssl x509 -noout -issuer | cut -d '=' -f 2- )
  local EXPIRATION=$(echo "$1" | openssl x509 -noout -enddate | cut -d '=' -f 2- )
  local FINGERPRINT=$(echo "$1" | openssl x509 -noout -fingerprint | cut -d '=' -f 2- )
  local SERIAL=$(echo "$1" | openssl x509 -noout -serial | cut -d '=' -f 2- )

  header "Certificate $2"
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
  local TOKEN=
  local RESPONSE=
  local CLIENT_NONCE=
  local CLIENT_TOKEN=
  local SERVER_NONCE=
  local SERVER_TOKEN=

  if [ -n "$DOMSETUP_TOKEN" ] && [ "$DOMSETUP_SERVER_VERIFIED" != "1" ]; then

    # First get the server nonce to ensure server can issue nonces
    RESPONSE="$(curl -s $DOMSETUP_CURL_OPTIONS "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/nonce")"

    # If it fails it is either we got no connection, no trusted cert
    if [ -z "$RESPONSE" ]; then
      CURL_STATUS=60
      return 0
    fi

    case "$RESPONSE" in
      nonce:*)
        SERVER_NONCE=$(printf "%s\n" "$RESPONSE" | cut -d':' -f2- | xargs)
        ;;

      *)
        log_error "Server verification failed - Invalid nonce returned: $RESPONSE"
        CURL_STATUS=403
        return 0
        ;;

    esac

    if [ "$SERVER_NONCE" = "-" ]; then
      log_error "Server has no token specified"
      CURL_STATUS=403
      return 0
    fi

    # Generate a client nonce and validate the server
    CLIENT_NONCE=$(openssl rand -hex 16)
    SERVER_TOKEN="$(curl -s $DOMSETUP_CURL_OPTIONS "https://$DOMSETUP_HOST:$DOMSETUP_HTTPS_PORT/validateserver/$CLIENT_NONCE")"

    if [ -z "$SERVER_TOKEN" ]; then
      log_error "Server verification failed - No Server Token returned"
      CURL_STATUS=403
      return 0
    fi

    # Validate server token
    TOKEN=$(printf "%s" "$CLIENT_NONCE" | openssl dgst -sha256 -hmac "$DOMSETUP_TOKEN" | awk '{print $2}')

    if [ "$SERVER_TOKEN" = "$TOKEN" ]; then
      DOMSETUP_SERVER_VERIFIED=1
      log_space "Info: Server token verified"
    else
      log_error "Server verification failed. Server Token: $SERVER_TOKEN"
      CURL_STATUS=403
      return 0
    fi

    # Finally generate a client token for client authorization
    CLIENT_TOKEN=$(printf "%s" "$SERVER_NONCE" | openssl dgst -sha256 -hmac "$DOMSETUP_TOKEN" | awk '{print $2}')
    CURL_AUTHORIZATION="Bearer $CLIENT_TOKEN"
  fi

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

  log

  get_variable DOMSETUP_OTS_JSON_FILE "OTS-JSON"

  if [ -z "$DOMSETUP_OTS_JSON_FILE" ]; then
    log_error " No DOMSETUP_OTS_JSON_FILE defined"
    return 1
  fi

  if [ ! -e "$DOMSETUP_OTS_JSON_FILE" ]; then
    log_error " No OTS JSON file not found: $DOMSETUP_OTS_JSON_FILE"
    return 1
  fi

  if [ -z "$DOMSETUP_HOST" ]; then
    DOMSETUP_HOST=$(cat "$DOMSETUP_OTS_JSON_FILE" | jq -r .serverSetup.network.hostName)
  fi

  get_variable DOMSETUP_HOST "Host"
  get_variable DOMSETUP_IP "Address"
  get_variable DOMSETUP_HTTPS_PORT "Port"
  get_variable DOMSETUP_BEARER "Bearer"
  get_variable DOMSETUP_TOKEN "Token"

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

  if [ -n "$DOMSETUP_CACERT_FILE" ] && [ -e "$DOMSETUP_CACERT_FILE" ]; then
    set_curl_option "--cacert $DOMSETUP_CACERT_FILE"
    log_space "Info: Trusting $DOMSETUP_CACERT_FILE"
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
      log_error "server.id not found: $DOMSETUP_SERVER_ID"
      return 1
    fi
  fi

  if [ -z "$DOMSETUP_TOKEN" ]; then
    log_space "Warning: Skipping server verification (No DOMSETUP_TOKEN configured)"
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

    # Get full chain once
    local CERT_CHAIN=$(openssl s_client -servername "$DOMSETUP_HOST" --connect "$OPENSSL_CONNECT" -showcerts </dev/null 2>/dev/null)

    if [ -z "$CERT_CHAIN" ]; then
      log_error "Terminating setup because no certificate data was received from $DOMSETUP_HOST"
      return 2
    fi

    # Extract leaf (first cert)
    local LEAF_CERT=$(echo "$CERT_CHAIN" | awk '/BEGIN CERTIFICATE/{c++} c==1{print} /END CERTIFICATE/ && c==1{exit}')

    if [ -z "$LEAF_CERT" ]; then
      log_error "Terminating setup because no leaf certificate was found"
      return 2
    fi

    # Extract root (last cert) into variable
    ROOT_CERT=$(echo "$CERT_CHAIN" | awk '/BEGIN CERTIFICATE/{x=""} {x = x $0 ORS} /END CERTIFICATE/{last=x} END{print last}')

    if [ -z "$ROOT_CERT" ]; then
      log_error "Terminating setup because no root certificate could be extracted"
      return 2
    fi

    # Check hostname
    echo "$LEAF_CERT" | openssl x509 -noout -checkhost "$DOMSETUP_HOST" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      log_error "Terminating setup because server certificate does not match hostname: $DOMSETUP_HOST"
      show_cert "$LEAF_CERT" "Leaf"
      return 2
    fi

    # Check expiration
    echo "$LEAF_CERT" | openssl x509 -noout -checkend 0 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      log_error "Terminating setup because server certificate is expired for: $DOMSETUP_HOST"
      show_cert "$LEAF_CERT" "Leaf"
      return 2
    fi

    if [ -n "$DOMSETUP_TRUST_ISSUER" ]; then

      local ISSUER=$(echo "$ROOT_CERT" | openssl x509 -noout -issuer | cut -d '=' -f 2- )

      case "$ISSUER" in
        *$DOMSETUP_TRUST_ISSUER*)
          echo "$ROOT_CERT" > "$DOMSETUP_CACERT_FILE"
          set_curl_option "--cacert $DOMSETUP_CACERT_FILE"
          log_space "Trusting root: $ISSUER"
          ;;

        *)
          log_error "Terminating setup because root certificate issuer does not match expected value: $DOMSETUP_TRUST_ISSUER"
          show_cert "$ROOT_CERT" "Root"
          return 2
          ;;
      esac

    elif [ "$DOMSETUP_ALLOW_UNTRUSTED" = "1" ]; then

      echo "$ROOT_CERT" > "$DOMSETUP_CACERT_FILE"
      set_curl_option "--cacert $DOMSETUP_CACERT_FILE"
      log_space "Trusting root"
      show_cert "$LEAF_CERT" "Leaf"

    else
      show_cert "$ROOT_CERT" "Root"

      local QUESTION=
      log
      read -p "Trust certificate : (yes/no) ? " QUESTION

      if [ "$QUESTION" = "yes" ] || [ "$QUESTION" = "y" ]; then
        # Write root to file
        echo "$ROOT_CERT" > "$DOMSETUP_CACERT_FILE"
        set_curl_option "--cacert $DOMSETUP_CACERT_FILE"
      else
        log_space "Terminating setup"
        return 2
      fi
    fi

    # Now try again
    check_domsetup_ready
  fi

  HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)
  HTTP_TEXT=$(echo "$HTTP_RESPONSE" | head -1)

  log_debug "HTTP-Status: [$HTTP_STATUS]"

  if [ "$HTTP_STATUS" = "401" ]; then
    log_error "Not authorized to use DomSetup"
    return 3
  fi

  if [ "$HTTP_STATUS" != "202" ]; then
    log
    if [ "$HTTP_STATUS" = "000" ]; then
      log_space "Remote server is not ready for DomSetup"
    else
      log_error "Remote server is not ready for DomSetup ($HTTP_STATUS)"
    fi

    delim
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
        log_error "Server.ID upload failed: [$HTTP_STATUS] $HTTP_TEXT"
        return 5
      fi

    else
      log_error "Server.ID upload failed: [$HTTP_STATUS] $HTTP_TEXT"
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

    # Remove OTS file after successful setup
    if [ "$DOMSETUP_KEEP_OTS_FILE" != "1" ]; then
      remove_file "$$DOMSETUP_OTS_JSON_FILE"
    fi
    return 0
  fi

  log_error "DomSetup failed: [$HTTP_STATUS] $HTTP_TEXT"
  return 5
}

print_banner()
{
  header "Domino Remote OTS Setup  $VERSION"
}

usage()
{

  print_banner
  echo "A Domino One-Touch JSON remote setup configuration script."
  echo "It works hand in hand with domsetup, which is part of the container image."
  echo "domsetup connects to the server over the specified port and posts a OTS file."
  echo "In addition for additional server setups a server.id can be pushed."
  echo "Note: OTS setup also supports embedded server.ids in Base64 format."
  echo
  echo
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
  echo "-token=<tokenvalue>          Token value for client authentication and server verification"
  echo "-prompt                      Interactively prompt for all parameters"
  echo "-promptempty                 Interactively prompt for empty parameters only"
  echo "-silent                      Do not prompt"
  echo "-reset                       Remove existing OTS file and restart configuration"
  echo "-allow_untrusted             Allow untrusted connections"
  echo "-trust_issuer=<name>         Allow connection even untrusted if the specified name is part of the root's subject"
  echo "-cacerts=<filename>          Specify cacerts file (default: /tmp/domsetup_cacert.pem)"
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
  echo "DOMSETUP_TOKEN               Token value for client authentication and server verification"
  echo "DOMSETUP_ALLOW_UNTRUSTED     Allow connections even untrusted and don't prompt"
  echo "DOMSETUP_TRUST_ISSUER        Even untrusted, allow the following issuer"
  echo "DOMSETUP_CACERT_FILE         Trusted root file (default: /tmp/domsetup_cacert.pem)"
  echo "DOMSETUP_NOPROMPT            0=always prompt, 1=only prompt if empty, 2=never prompt"
  echo "DOMSETUP_RESET_OTS=1         Remove existing OTS file and restart configuration"
  echo "DOMSETUP_KEEP_OTS_FILE       Keep OTS file after successful setup"
  echo
}


# --- Main ---

if [ -n "$1" ]; then
  DOMSETUP_NOPROMPT=2
fi

for a in "$@"; do

  p=$(echo "$a" | awk '{print tolower($0)}')

  case "$p" in

    # Passthru options for OTS setup script
    https://*|http://*|file:/*|auto|remote|local)
      DOMSETUP_OTS_OPTIONS="$a"
      ;;

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

    -reset)
      DOMSETUP_RESET_OTS=1
      ;;

    -allow_untrusted)
      DOMSETUP_ALLOW_UNTRUSTED=1
      ;;

    -token=*)
      DOMSETUP_TOKEN=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -trust_issuer=*)
      DOMSETUP_TRUST_ISSUER=$(echo "$a" | cut -f2 -d= -s)
      ;;

    -cacerts=*)
      DOMSETUP_CACERT_FILE=$(echo "$a" | cut -f2 -d= -s)
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

# Check stdin fir input
if [ "$DOMSETUP_OTS_JSON_FILE" = "-" ]; then

  if [ -t 0 ]; then
    log_error "No stdin specified"
    exit 1
  fi

  log_space "Info: Using JSON from stdin"

  if [ -n "$DOMINO_AUTO_CONFIG_JSON_FILE" ]; then
    DOMSETUP_OTS_JSON_FILE="$DOMINO_AUTO_CONFIG_JSON_FILE"
  else
    DOMSETUP_OTS_JSON_FILE="/tmp/domsetup.json"
  fi

  cat > "$DOMSETUP_OTS_JSON_FILE"

  if [ ! -s "$DOMSETUP_OTS_JSON_FILE" ]; then
    log_error "No data received on stdin"
    exit 1
  fi
fi

if [ -z "$DOMSETUP_OTS_JSON_FILE" ]; then

  if [ -n "$DOMINO_AUTO_CONFIG_JSON_FILE" ]; then
    DOMSETUP_OTS_JSON_FILE="$DOMINO_AUTO_CONFIG_JSON_FILE"
  else
    DOMSETUP_OTS_JSON_FILE="/tmp/domsetup.json"
  fi
fi

log_debug "DOMSETUP_OTS_OPTIONS: [$DOMSETUP_OTS_OPTIONS]"


if [ "$DOMSETUP_RESET_OTS" = "1" ]; then
  remove_file "$DOMSETUP_OTS_JSON_FILE"
  log_space "Info: Removed existing OTS file: $DOMSETUP_OTS_JSON_FILE"
fi

# Export the target JSON file for OTS setup
export DOMINO_AUTO_CONFIG_JSON_FILE="$DOMSETUP_OTS_JSON_FILE"

if [ ! -e "$DOMSETUP_OTS_JSON_FILE" ]; then
  "$SCRIPT_DIR/DominoOneTouchSetup.sh" $DOMSETUP_OTS_OPTIONS
elif [ -n "$DOMSETUP_OTS_OPTIONS" ]; then
  "$SCRIPT_DIR/DominoOneTouchSetup.sh" $DOMSETUP_OTS_OPTIONS
  echo "$SCRIPT_DIR/DominoOneTouchSetup.sh" $DOMSETUP_OTS_OPTIONS
fi

print_banner

domsetup
exit "$?"


