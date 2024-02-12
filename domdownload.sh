#!/bin/bash

###########################################################################
# Domino Software Download Script                                         #
# Version 0.9.9 26.01.2024                                                #
# Copyright Nash!Com, Daniel Nashed                                       #
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

# Supported Environments
# ----------------------
#
# - RedHat/CentOS & clones
# - Ubuntu/Debian
# - VMware Photon OS
# - MacOS
# - GitBash on Windows

# Change History
# --------------
#
# 0.9.2  Support for GitBash
# 0.9.3  Bug fixes
# 0.9.4  Custom download and "local" mode
# 0.9.5  Fix for software with multiple languages (e.g language packs)
#        '-silent' option for not printing information about a web-kit
#        Caching access token for 40 minutes to avoid round trips got get a new access token (token is valid for 60 minutes)
# 0.9.6  Bug fixes
# 0.9.7  Fit & Finish changes
# 0.9.8  Performance counter for Linux but not for Mac because there is only a seconds timer in "date" and we don't want to install tools extra for this 
# 0.9.9  Better error output for invalid refesh tokens

SCRIPT_NAME=$0
SCRIPT_DIR=$(dirname $SCRIPT_NAME)

DOMDOWNLOAD_SCRIPT_VERSION=0.9.9

ClearScreen()
{
  if [ "$DISABLE_CLEAR_SCREEN" = "yes" ]; then
    return 0
  fi

  clear
}

LogError()
{
  echo >& 2
  echo "ERROR: $@" >& 2
  echo >& 2
}


LogMessage()
{
  echo
  echo "$@"
  echo
}

LogMessageIfNotSilent()
{
  if [ "$SILENT_MODE" = "yes" ]; then
    return 0
  fi

  echo
  echo "$@"
  echo
}

print_delim()
{
  echo "--------------------------------------------------------------------------------"
}

header()
{
  echo
  print_delim
  echo "$1"
  print_delim
  echo
}

DebugText()
{
  if [ "$DOMDOWNLOAD_DEBUG" = "yes" ]; then
    echo
    echo "$(date '+%F %T') Debug:" $@
    echo
  fi

  return 0
}

DebugDump()
{
  if [ "$DOMDOWNLOAD_DEBUG" = "yes" ]; then
    echo
    echo "-------------------- $1 --------------------"
    echo "$2"
    echo "-------------------- $1 --------------------"
    echo
  fi
}

PerfTimerLogSession()
{
  if [ "$OS_PLATFORM" = "Darwin" ]; then
    return 0
  fi

  if [ -z "$PERF_LOG_FILE" ]; then
    return 0
  fi

  # truncate log
  if [ -e "$PERF_LOG_FILE" ]; then
    tail -$PERF_MAX_LOG_LINES "$PERF_LOG_FILE" >> "$PERF_LOG_FILE.tmp"
    mv -f "$PERF_LOG_FILE.tmp" "$PERF_LOG_FILE"
  fi

  echo >> "$PERF_LOG_FILE"
  date '+%F %T' >> "$PERF_LOG_FILE"
  echo "--------------------" >> "$PERF_LOG_FILE"
}

PerfTimerBegin()
{
  if [ "$OS_PLATFORM" = "Darwin" ]; then
    return 0
  fi

  if [ -z "$PERF_LOG_FILE" ]; then
    return 0
  fi

  PERF_BEGIN_TIMER=$(($(date +%s%N)/1000000))
}

PerfTimerEnd()
{
  if [ "$OS_PLATFORM" = "Darwin" ]; then
    return 0
  fi

  if [ -z "$PERF_LOG_FILE" ]; then
    return 0
  fi

  local END_TIMER=$(($(date +%s%N)/1000000))
  local DIFF_TIMER=$(($END_TIMER-$PERF_BEGIN_TIMER))

  if [ $DIFF_TIMER -gt $1 ]; then
    printf "%6s ms  %s\n" "$DIFF_TIMER" "$2" >> "$PERF_LOG_FILE"
  fi
}

CheckWriteFile()
{
  if [ ! -w "$1" ]; then
    LogError "Cannot write to file: $1"
    exit 1
  fi
}

CheckWriteDir()
{
  if [ ! -w "$1" ]; then
    LogError "Cannot write to directory: $1"
    exit 1
  fi
}

remove_file()
{
  if [ -z "$1" ]; then
    DebugText "remove_file - No file specified"
    return 1
  fi

  if [ ! -e "$1" ]; then
    DebugText "remove_file - File does not exist: $1"
    return 2
  fi

  rm -f "$1"

  if [ ! "$?" = "0" ]; then
    LogError "Cannot delete file: $1"
    return 3
  fi

  DebugText "File removed: $1"
  return 0
}

create_link()
{
  if [ -z "$1" ]; then
    return 1
  fi

  if [ -z "$2" ]; then
    return 2
  fi

  if [ -e "$2" ]; then
    DebugText "create_link - Link already exists [$2]"
    return 0
  fi

  if [ ! -r "$1" ]; then
    LogError "create_link - Cannot read file when creating a link: $1"
    return 0
  fi

  ln -s "$1" "$2"

  if [ ! "$?" = "0" ]; then
    LogError "create_link - Cannote create link [$1] -> [$2]"
    return 3
  fi

  DebugText "Link created [$1] -> [$2]"
  return 0
}

install_package()
{
  local SUDO=

  if [ ! "$UID" = "0" ]; then
    SUDO=sudo
  fi

  if [ -x /usr/bin/zypper ]; then
    $SUDO /usr/bin/zypper install -y "$@"

  elif [ -x /usr/bin/dnf ]; then
    $SUDO /usr/bin/dnf install -y "$@"

  elif [ -x /usr/bin/tdnf ]; then
    $SUDO /usr/bin/tdnf install -y "$@"

  elif [ -x /usr/bin/microdnf ]; then
    $SUDO /usr/bin/microdnf install -y "$@"

  elif [ -x /usr/bin/yum ]; then
    $SUDO /usr/bin/yum install -y "$@"

  elif [ -x /usr/bin/apt-get ]; then

    if [ -z "$UBUNTU_PACKAGES_LOADED" ]; then
      LogMessage "Info: Loading Ubuntu packages first to ensure the repository is available and latest"
      $SUDO /usr/bin/apt-get update -y
      UBUNTU_PACKAGES_LOADED=1
    fi

    $SUDO /usr/bin/apt-get install -y "$@"

  else

    if [ -z "$2" ]; then
       LogError "No package manager found!"
    else
      LogError "No package manager found. Please check $2 how to download $1."
      exit 1
    fi

  fi
}


AssistInstallPackage()
{
  local QUESTION=

  echo
  read -p "Install $1 : (yes/no) ? " QUESTION

  if [ "$QUESTION" = "yes" ] || [ "$QUESTION" = "y" ]; then

    header "Installing $1"
    install_package "$1"
    echo
    echo
    return 0

  else
    return 1
  fi
}


AssistInstallJQ4Mac()
{
  local QUESTION=
  local JQ_GITHUB_BIN=

  echo
  read -p "Install JQ for MacOSX from GitHub project : (yes/no) ? " QUESTION

  if [ "$QUESTION" = "yes" ] || [ "$QUESTION" = "y" ]; then

    if [ "$CPU_TYPE" = "arm64" ]; then
      JQ_GITHUB_BIN="https://github.com/jqlang/jq/releases/download/jq-1.7/jq-macos-arm64"
    else
      JQ_GITHUB_BIN="https://github.com/jqlang/jq/releases/download/jq-1.7/jq-macos-amd64"
    fi

    $CURL_BIN  -sL "$JQ_GITHUB_BIN" -o jq
    chmod 755 jq

    if [ -w /usr/local/bin ]; then
      mv jq /usr/local/bin/jq
    else

      LogMessage "Info: Need root permissions to move jq to /usr/local/bin/jq (you might get promted for sudo)"

      sudo mv jq /usr/local/bin/jq

      if [ "$?" = "0" ]; then
        JQ_CMD=/usr/local/bin/jq
        return 0
      else
        LogError "Cannot move jq to /usr/local/bin. Please log in with root permissions and move jq manually"
        return 1
      fi
    fi

    echo
    echo
    return 0

  else
    return 1
  fi
}


InstallJQ()
{
  local HOME_PAGE="https://jqlang.github.io/jq/"

  header "JQ package required"
  echo "This script requires the JQ package."
  echo "JQ is the de-facto standard for JSON files and used to parse JSON data."
  echo
  echo "See $HOME_PAGE for details."
  echo

  if [ "$OS_PLATFORM" = "Darwin" ]; then
    AssistInstallJQ4Mac
  else
    AssistInstallPackage jq "$HOME_PAGE"
  fi

  JQ_VERSION=$($JQ_CMD --version 2>/dev/null)
  if [ -z "$JQ_VERSION" ]; then
    LogError "This script requires JQ!"
    exit 1
  fi

  LogMessage "$JQ_VERSION installed"

}

InstallCurl()
{

  local HOME_PAGE="https://curl.se/"

  header "Curl package required"
  echo "This script requires the Curl package."
  echo "Curl is the de-facto standard for command-line URL requests."
  echo
  echo "See $HOME_PAGE for details."
  echo

  AssistInstallPackage curl "$HOME_PAGE"

  CURL_VERSION=$(curl --version 2>/dev/null)
  if [ -z "$CURL_VERSION" ]; then
    LogError "This script requires Curl!"
    exit 1
  fi

  header "Curl installed"

  echo "$CURL_VERSION"
  echo ---
  echo
}

CheckBin()
{
  if [ ! -x "/usr/bin/$1" ]; then
    AssistInstallPackage "$1"
  fi

  if [ ! -x "/usr/bin/$1" ]; then
    LogError "$1 is required!"
    exit 1
  fi
}


CheckEnvironment()
{

  OS_PLATFORM=$(uname -s)
  CPU_TYPE=$(uname -m)

  DebugText "Platform: $OS_PLATFORM"
  DebugText "CPU Type: $CPU_TYPE"

  if [ "$OS_PLATFORM" = "Darwin" ]; then

    CHECKSUM_VERSION=$(shasum --version 2>/dev/null | head -1)
    CHECKSUM_CMD="shasum -a 256 -b"

    if [ -z "$CHECKSUM_VERSION" ]; then
      LogError "No shasum found"
      exit 1
    fi

  else

    CHECKSUM_VERSION=$(sha256sum --version 2>/dev/null | head -1)
    CHECKSUM_CMD="sha256sum"

    if [ -z "$CHECKSUM_VERSION" ]; then
      LogError "No sha256sum found"
      exit 1
    fi

  fi

  if [ -e /usr/bin/curl ]; then
    CURL_BIN=/usr/bin/curl
  elif [ -e /mingw64/bin/curl ]; then
    CURL_BIN=/mingw64/bin/curl

  else
    CURL_BIN=
  fi

  if [ -z "$CURL_BIN" ]; then
    InstallCurl
    CURL_BIN=/usr/bin/curl
  fi

  CURL_VERSION=$($CURL_BIN --version 2>/dev/null)
  if [ -z "$CURL_VERSION" ]; then
    LogError "This script requires Curl!"
    exit 1
  fi

  if [ -e /usr/bin/jq ]; then
    JQ_CMD=/usr/bin/jq
  elif [ -e /usr/local/bin/jq ]; then
    JQ_CMD=/usr/local/bin/jq
  elif [ -e /mingw64/bin/jq ]; then
    JQ_CMD=/mingw64/bin/jq
  else
    JQ_CMD=
  fi

  if [ -z "$JQ_CMD" ]; then
    JQ_CMD=/usr/bin/jq
    InstallJQ

    # Check JQ again
    if [ -e /usr/bin/jq ]; then
      JQ_CMD=/usr/bin/jq
    elif [ -e /usr/local/bin/jq ]; then
      JQ_CMD=/usr/local/bin/jq
    elif [ -e /mingw64/bin/jq ]; then
      JQ_CMD=/mingw64/bin/jq
    else
      JQ_CMD=
    fi
  fi

  JQ_VERSION=$($JQ_CMD --version 2>/dev/null | head -1)

  DebugText "Curl : $CURL_VERSION"
  DebugText "JQ   : $JQ_VERSION"

  CheckBin awk
  CheckBin cut
  CheckBin stat
  CheckBin du
}


LogConnectionError()
{
  if [ "$DOMDOWNLOAD_MODE" = "local" ]; then
    LogMessage "LOCAL - MODE"
  fi

  if [ "$DOMDOWNLOAD_MODE" = "not-agreeed" ]; then
    LogMessage "No agreement to connect to internet"
  fi

  LogError "$1"
}

ConfirmConnection()
{
  if [ -e "$CONNECTION_AGREED_FILE" ]; then
    return 0
  fi

   date > "$CONNECTION_AGREED_FILE"
}


CheckConnection()
{
  if [ -n "$DOMDOWNLOAD_MODE" ]; then
    return 0
  fi

  if [ ! -e "$CONNECTION_AGREED_FILE" ]; then

    local QUESTION=
    echo

    header "Agree Internet Connection"

    echo "Please agree to connect to Internet to"
    echo
    echo "- Download Domino installation software from My HCL Software Portal"
    echo "- Download software information (JWT/JSON data) from HCL Domino AutoUpdate site"
    echo
    echo "Host names to connect to via HTTPS (port 443)"
    echo
    echo "$MYHCL_PORTAL_URL"
    echo "$MYHCL_API_URL"
    echo "$HCL_AUTOUPDATE_URL"
    echo "$GITHUB_URL"
    echo
    echo
    read -p "Confirm connection : (yes/no) ? " QUESTION
    echo

      if [ "$QUESTION" = "yes" ] || [ "$QUESTION" = "y" ]; then
      date > "$CONNECTION_AGREED_FILE"
    else

      echo
      QUESTION=
      read -p "Do you want to use the local mode instead : (yes/no) ? " QUESTION
      echo

      if [ "$QUESTION" = "yes" ] || [ "$QUESTION" = "y" ]; then

        DOMDOWNLOAD_MODE=local
        echo >> "$DOMDOWNLOAD_CFG_FILE"
        echo "# Local mode - configured at $(date)" >> "$DOMDOWNLOAD_CFG_FILE"
        echo "DOMDOWNLOAD_MODE=local" >> "$DOMDOWNLOAD_CFG_FILE"
        return 0

      else
        DOMDOWNLOAD_MODE=not-agreed
        LogConnectionError "No internet connection"
        exit 1
      fi
    fi
  else
    DebugText "Agreed to connect via $CONNECTION_AGREED_FILE at [$(cat $CONNECTION_AGREED_FILE)]"
  fi

  PerfTimerBegin
  local CURL_RET=$($CURL_CMD --silent "$GITHUB_URL" --head -w 'RESP_CODE:%{response_code}\n')
  PerfTimerEnd $PERF_MAX_CURL "$MYHCL_PORTAL_URL"

  if [ -z "$(echo "$CURL_RET" | grep "RESP_CODE:200")" ]; then
    DOMDOWNLOAD_MODE=error
  else
    DOMDOWNLOAD_MODE=online
  fi

  DebugText "Connection: $DOMDOWNLOAD_MODE"
}


SetRefreshToken()
{
  # Set the download/refresh token to specified value or prompt

  local REFRESH_TOKEN=$1

  if [ -n "$REFRESH_TOKEN" ]; then
    echo "$REFRESH_TOKEN" > "$DOMDOWNLOAD_TOKEN_FILE_NAME"
    return 0
  fi

  echo
  echo "My HCL Software portal requires a download token."
  echo
  echo "Please visit -> $MYHCL_PORTAL_URL"
  echo
  echo "- Log in with your HCL software account."
  echo "- Navigate to the upper right corner and select 'API keys' to generate a key."
  echo "- Specify the generated key as a download token below."
  echo
  read -p "Enter Download Token: " REFRESH_TOKEN
  echo

  if [ -z "$REFRESH_TOKEN" ]; then
    LogError "No download token specified"
    exit 1
  fi

  echo "$REFRESH_TOKEN" > "$DOMDOWNLOAD_TOKEN_FILE_NAME"
}


GetAccessToken()
{
  # Get access token and rotate refresh token from My HCL Software site

  local REFRESH_TOKEN=
  local JSON=

  ACCESS_TOKEN=

  if [ -e "$DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME" ]; then

    # If access token isn't older than 40 min used cached token, else delete existing cached file
    if [ -n "$(find "$DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME" -mmin -40 2>/dev/null)" ]; then
      DebugText "Returning cached access token"
      ACCESS_TOKEN=$(cat "$DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME")
      return 0
    fi

    DebugText "Deleting old cached access token: $DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME"
    remove_file "$DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME"
  else
    DebugText "No cached access token found: $DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME"
  fi

  if [ ! -e "$DOMDOWNLOAD_TOKEN_FILE_NAME" ]; then
    SetRefreshToken
  fi

  if [ -e "$DOMDOWNLOAD_TOKEN_FILE_NAME" ]; then
    REFRESH_TOKEN=$(cat "$DOMDOWNLOAD_TOKEN_FILE_NAME")
  fi

  if [ -z "$REFRESH_TOKEN" ]; then
    LogError "No refresh token found"
    return 1
  fi

  DebugDump "REFRESH_TOKEN" "$REFRESH_TOKEN"

  DebugText "Request: $MYHCL_TOKEN_URL"

  CheckWriteFile "$DOMDOWNLOAD_TOKEN_FILE_NAME"

  # Exchange refresh token and get access token (JWT)

  PerfTimerBegin
  JSON=$($CURL_CMD -sL "$MYHCL_TOKEN_URL" -H "Content-Type: application/json" -d "{\"refreshToken\":\"$REFRESH_TOKEN\"}")
  PerfTimerEnd $PERF_MAX_CURL "MyHCL-API-ExchangeToken"

  DebugDump "JSON" "$JSON"

  REFRESH_TOKEN=$(echo "$JSON" | $JQ_CMD -r .refreshToken)

  if [ "$REFRESH_TOKEN" = "null" ] || [ -z "$REFRESH_TOKEN" ]; then

    ERROR_TEXT=$(echo "$JSON" | $JQ_CMD -r .summary)
    if [ -z "$ERROR_TEXT" ]; then
      LogError "No refresh token returned"
    else
      LogError "$ERROR_TEXT"
    fi

    exit 1
  fi

  echo "$REFRESH_TOKEN" > "$DOMDOWNLOAD_TOKEN_FILE_NAME"

  ACCESS_TOKEN=$(echo "$JSON" | $JQ_CMD -r .accessToken)

  # Cache access token to avoid round trips for next request
  echo "$ACCESS_TOKEN" > "$DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME"

  if [ ! "$DOMDOWNLOAD_DEBUG" = "yes" ]; then
    return 0
  fi

  DebugDump "REFRESH_TOKEN" "$REFRESH_TOKEN"
  DebugDump "ACCESS_TOKEN" "$ACCESS_TOKEN"

  # Decode token and dump content
  local PAYLOAD_BASE64URL=$(echo "$ACCESS_TOKEN" | /usr/bin/cut -d"." -f2)
  local PAYLOAD_BASE64=$(echo -n $PAYLOAD_BASE64URL | tr '_-' '/+')

  # Add padding for valid BASE64 encoding (base64url encoding removes padding)
  local PAD_COUNT=$(expr 4 - ${#PAYLOAD_BASE64} % 4)

  if [ "$PAD_COUNT" != "4" ]; then
    while ((PAD_COUNT--)); do PAYLOAD_BASE64=$PAYLOAD_BASE64=; done
  fi

  DECODED_TOKEN=$(echo "$PAYLOAD_BASE64" | openssl base64 -d -A)

  echo
  echo "---- Decoded Token ----"
  echo "$DECODED_TOKEN" | $JQ_CMD
  echo "---- Decoded Token ----"
  echo

  return 0
}


CheckDownloadedFile()
{
  local OUTFILE_FULLPATH="$1"
  local FILE_SHA256=

  if [ -z "FILE_CHECKSUM_SHA256" ]; then
    LogMessage "Info: No checksum for web-kit. Skipping verification!"
    LogMessage "$OUTFILE_FULLPATH"
    exit 0
  fi

  PerfTimerBegin
  FILE_SHA256=$($CHECKSUM_CMD "$OUTFILE_FULLPATH" | /usr/bin/cut -f1 -d" " | /usr/bin/awk '{print tolower($0)}')
  PerfTimerEnd $PERF_MAX_CHECKSUM "SHA256: $OUTFILE_FULLPATH"

  if [ "$FILE_SHA256" = "$(echo "$FILE_CHECKSUM_SHA256" | /usr/bin/awk '{print tolower($0)}')" ]; then
    LogMessage "[OK] Hash verified"
  else
    LogMessage "[FAILED] Hash does NOT match!"
    remove_file "$OUTFILE_FULLPATH"
    exit 1
  fi
}


DownloadCustom()
{
  local DOWNLOAD_URL=
  local DOWNLOAD_BASIC_AUTH=
  local DOWNLOAD_BASIC_AUTH_CMD=
  local OUTFILE_FULLPATH=$SOFTWARE_DIR/$1

  if [ "$PRINT_INFO_ONLY" = "yes" ]; then
    exit 0
  fi

  if [ -z "$1" ]; then

    LogError "No custom download found"
    return 0
  fi

  if [ -e "$OUTFILE_FULLPATH" ]; then
    if [ "$FORCE_DOWNLOAD" = "yes" ]; then
      LogMessage "Info: Overwriting existing download [$OUTFILE_FULLPATH]"
      remove_file "$OUTFILE_FULLPATH"
    else
      LogMessageIfNotSilent "Info: File already exists [$OUTFILE_FULLPATH]"
      return 0
    fi
  fi

  CheckWriteDir "$SOFTWARE_DIR"

  DOWNLOAD_URL="$DOMDOWNLOAD_CUSTOM_URL/$1"

  LogMessage "Downloading from $DOWNLOAD_URL ..."

  if [ -n "$DOMDOWNLOAD_CUSTOM_USER" ] && [ -n "$DOMDOWNLOAD_CUSTOM_PASSWORD" ]; then
    DOWNLOAD_BASIC_AUTH="$DOMDOWNLOAD_CUSTOM_USER:$DOMDOWNLOAD_CUSTOM_PASSWORD"
    DOWNLOAD_BASIC_AUTH_CMD="--user"
  fi

  PerfTimerBegin
  $CURL_DOWNLOAD_CMD "$DOWNLOAD_URL" -o "$OUTFILE_FULLPATH" "$DOWNLOAD_BASIC_AUTH_CMD" "$DOWNLOAD_BASIC_AUTH"
  PerfTimerEnd $PERF_MAX_CURL "$OUTFILE_FULLPATH"

  if [ ! -e "$OUTFILE_FULLPATH" ]; then
    LogError "Cannot download file from $DOWNLOAD_URL"
    exit 1
  fi

  if [ -z "FILE_CHECKSUM_SHA256" ]; then
    LogMessage "Info: No checksum for web-kit. Skipping verification!"
    exit 0
  fi

  CheckDownloadedFile "$OUTFILE_FULLPATH"
  LogMessage "$OUTFILE_FULLPATH"
}


DownloadSoftware()
{
  # Download software or print curl command for command-line download

  # $1: URL
  # $2: Filename
  # $3: SHA256

  local OUTFILE_FULLPATH=$SOFTWARE_DIR/$2
  local DOWNLOAD_FILE_URL=

  if [ "$PRINT_INFO_ONLY" = "yes" ]; then
    exit 0
  fi

  if [ -z "$1" ]; then
    LogError "No file ID specified"
    return 1
  fi

  if [ -z "$2" ]; then
    LogError "No download file specified"
    return 1
  fi

  if [ -n "$DOMDOWNLOAD_CUSTOM_URL" ]; then
    DownloadCustom "$FILE_NAME"
    exit 0
  fi

  if [ -e "$OUTFILE_FULLPATH" ]; then

    if [ ! "$PRINT_DOWNLOAD_CURL_CMD" = "yes" ]; then

        CheckWriteDir "$SOFTWARE_DIR"

        if [ "$FORCE_DOWNLOAD" = "yes" ]; then
          LogMessage "Info: Overwriting existing download [$OUTFILE_FULLPATH]"
          remove_file "$OUTFILE_FULLPATH"
        else
          LogMessageIfNotSilent "Info: File already exists [$OUTFILE_FULLPATH]"
          return 0
        fi
    fi
  fi

  CheckWriteDir "$SOFTWARE_DIR"

  CheckConnection
  if [ ! "$DOMDOWNLOAD_MODE" = "online" ]; then
    LogConnectionError "Cannot download software"
    exit 1
  fi

  GetAccessToken

  if [ -z "$ACCESS_TOKEN" ]; then
    LogError "No access token"
    return 1
  fi

  DebugText "Request: ${MYHCL_DOWNLOAD_URL_PREFIX}$1${MYHCL_DOWNLOAD_URL_SUFFIX}"

  PerfTimerBegin
  DOWNLOAD_FILE_URL=$($CURL_CMD -s --write-out "%{redirect_url}\n" --output /dev/null "${MYHCL_DOWNLOAD_URL_PREFIX}$1${MYHCL_DOWNLOAD_URL_SUFFIX}" -H "Authorization: Bearer $ACCESS_TOKEN" -o "$OUTFILE_FULLPATH")
  PerfTimerEnd $PERF_MAX_CURL "MyHCL-API-FileURL"

  if [ -z "$DOWNLOAD_FILE_URL" ]; then
    LogError "No download URL returned"
    return 1
  fi

  if [ "$PRINT_DOWNLOAD_CURL_CMD" = "yes" ]; then

    echo
    echo
    echo Linux / MacOS Download:
    echo
    echo curl -L \'$DOWNLOAD_FILE_URL\' -o "$2"
    echo
    print_delim
    echo
    echo Windows Download:
    echo
    echo curl -L \"$DOWNLOAD_FILE_URL\" -o "$2"
    echo
    echo

    return 0

  fi

  DebugText "Download URL: $DOWNLOAD_FILE_URL"
  LogMessage "Downloading $OUTFILE_FULLPATH ..."

  HTTP_STATUS=$($CURL_DOWNLOAD_CMD -L "$DOWNLOAD_FILE_URL" -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" -o "$OUTFILE_FULLPATH")

  if [ "$?" != "0" ]; then
    LogError "Failed to download ($1 -> $OUTFILE_FULLPATH)"
    return 1
  fi

  if [ ! -e "$OUTFILE_FULLPATH" ]; then
    LogError "Failed to download FileID: ($1 -> $OUTFILE_FULLPATH)"
    return 1
  fi

  if [ "$HTTP_STATUS" = "200" ]; then
    LogMessage "Download completed"
  else
    LogError "Failed to download - HTTP_STATUS: $HTTP_STATUS"
    return 1
  fi

  if [ "$OS_PLATFORM" = "Darwin" ]; then
    DOWNLOAD_FILE_SIZE=$(/usr/bin/stat -f%z "$OUTFILE_FULLPATH")
  else
    DOWNLOAD_FILE_SIZE=$(/usr/bin/du -b "$OUTFILE_FULLPATH" | /usr/bin/cut -f1)
  fi

  if [ -n "$(find "$DOWNLOAD_FILE_SIZE" -size -1k 2>/dev/null)" ]; then
    ERROR_TXT=$(cat "$OUTFILE_FULLPATH" | $JQ_CMD .summary)

    LogError "Failed to download ($1 -> $OUTFILE_FULLPATH): [$ERROR_TXT]"
    return 1
  fi

  if [ -z "FILE_CHECKSUM_SHA256" ]; then
    LogMessage "Info: No checksum for web-kit. Skipping verification!"
    exit 0
  fi

  CheckDownloadedFile "$OUTFILE_FULLPATH"
  LogMessage "$OUTFILE_FULLPATH"
  return 0
}


DownloadS3()
{
  local OUTFILE_FULLPATH=$SOFTWARE_DIR/$2

  if [ -z "$1" ]; then

    LogError "No S3 download found"
    return 0
  fi

  if [ ! "$DOWNLOAD_SELECTED" = "yes" ]; then

    echo
    echo
    echo Linux / MacOS Download:
    echo
    echo aws s3 cp \'$1\' "$2"
    echo
    print_delim
    echo
    echo Windows Download:
    echo
    echo aws s3 cp \"$1\" "$2"
    echo
    echo
    return 0
  fi

  if [ -e "$OUTFILE_FULLPATH" ]; then
    if [ "$FORCE_DOWNLOAD" = "yes" ]; then
      LogMessage "Info: Overwriting existing download [$OUTFILE_FULLPATH]"
      remove_file "$OUTFILE_FULLPATH"
    else
      LogMessageIfNotSilent "Info: File already exists [$OUTFILE_FULLPATH]"
      return 0
    fi
  fi

  CheckWriteDir "$SOFTWARE_DIR"

  aws s3 cp "$1" "$2"

  if [ ! -e "$OUTFILE_FULLPATH" ]; then
    LogError "Cannot download file from S3!"
    exit 1
  fi

  CheckDownloadedFile "$OUTFILE_FULLPATH"
  LogMessage "$OUTFILE_FULLPATH"
}

GetProductLinePortal()
{
  if [ -z "$PRODUCT_INFO" ]; then
    LogError "No software found"
    exit 1
  fi

  PerfTimerBegin
  local PRODUCT_LINE=$(echo "$PRODUCT_INFO" | $JQ_CMD -r '.name + "|" + .description + "|" + .platform  + "|" + (.size|tostring) + "|" + .checksums.sha256 + "|" + .id + "|" + .modified')
  PerfTimerEnd $PERF_MAX_JQ "JQ: GetProductLinePortal"

  FILE_NAME=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f1)
  FILE_DESCRIPTION=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f2)
  FILE_PLATFORM=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f3)
  FILE_SIZE=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f4)
  FILE_CHECKSUM_SHA256=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f5)
  FILE_ID=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f6)
  FILE_MODIFIED=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f7)

  if [ "$SILENT_MODE" = "yes" ]; then
    return 0
  fi

  echo
  print_delim
  echo "WebKit   : " $FILE_DESCRIPTION
  echo "Name     : " $FILE_NAME

  if [ -n "$FILE_VERSION" ]; then
    echo "Version  : " $FILE_VERSION
  fi

  if [ -n "$FILE_PLATFORM" ]; then
    echo "Platform : " $FILE_PLATFORM
  fi

  echo "Size     : " $FILE_SIZE
  echo "SHA256   : " $FILE_CHECKSUM_SHA256
  echo "ID       : " $FILE_ID

  if [ -n "$FILE_MODIFIED" ]; then
    echo "Modified : " $FILE_MODIFIED
  fi

  print_delim
  echo
}

PrintSoftwareLine()
{
  local PRODUCT="$FILE_PRODUCT"
  local VERSION="$FILE_VERSION"

  if [ ! "$PRINT_SOFTWARE_LINE" = "yes" ]; then
    return 0
  fi

  if [ "$FILE_TYPE" = "langpack" ]; then
    PRODUCT=domlp
    VERSION=$FILE_LANG-$FILE_VERSION
  fi

  echo
  echo "$PRODUCT|$VERSION|$FILE_NAME|-|$FILE_CHECKSUM_SHA256"
}

GetProductLineAutoUpdate()
{
  if [ -z "$PRODUCT_INFO" ]; then
    LogError "No software found"
    exit 1
  fi

  PerfTimerBegin

  local PRODUCT_LINE=$(echo "$PRODUCT_INFO" | $JQ_CMD  -r '( (select(.platform|type=="array") | .fileName + "|" + .description + "|" + .labelVersion + "|" +(.fileSize|tostring) + "|" + .fileChecksum + "|" + .fileID + "|" + .product + "|" + .type + "|" + (.platform|join(",")) + "|" + .info.S3), (select(.platform|type=="string") | .fileName + "|" + .description + "|" + .labelVersion + "|" +(.fileSize|tostring) + "|" + .fileChecksum + "|" + .fileID + "|" + .product + "|" + .type + "|" + .platform + "|" + .info.S3) )')

  PerfTimerEnd $PERF_MAX_JQ "JQ: GetProductLineAutoUpdate"

  # cut is faster to than JQ and is a very simple operation
  FILE_NAME=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f1)
  FILE_DESCRIPTION=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f2)
  FILE_VERSION=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f3)
  FILE_SIZE=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f4)
  FILE_CHECKSUM_SHA256=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f5)
  FILE_ID=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f6)
  FILE_PRODUCT=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f7)
  FILE_TYPE=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f8)
  FILE_PLATFORM=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f9)
  FILE_INFO_S3=$(echo "$PRODUCT_LINE" | /usr/bin/cut -d"|" -f10)

  if [ "$SILENT_MODE" = "yes" ]; then
    return 0
  fi

  echo
  print_delim
  echo "WebKit   : " $FILE_DESCRIPTION
  echo "Product  : " $FILE_PRODUCT
  echo "Type     : " $FILE_TYPE
  echo "Platform : " $FILE_PLATFORM
  echo "Version  : " $FILE_VERSION
  if [ -n "$FILE_LANG" ]; then
    echo "Language : " $FILE_LANG
  fi
  echo "Name     : " $FILE_NAME
  echo "Size     : " $FILE_SIZE
  echo "SHA256   : " $FILE_CHECKSUM_SHA256
  echo "ID       : " $FILE_ID
  if [ -n "$FILE_INFO_S3" ]; then
    echo "S3       : " $FILE_INFO_S3
  fi
  print_delim
  PrintSoftwareLine
  echo
}


DownloadProductFromPortal()
{

  # $1 File
  # $2 Product path
  # $3 SLUG

  FILE_VERSION="$3"

  # Only invoke JQ once is much faster specially when working with multiple product files
  PRODUCT_INFO=$(echo "$1")
  GetProductLinePortal

  return 0
}

GetDownloadFromPortal()
{
  local JSON=
  local FILE_JSON=
  local PRODUCT_PATH=
  local TYPE=
  local SELECT=
  local TITLE=
  # Note "$SLUG" is not a local variable and comes from the next higher recursion level

  if [ -z "$1" ]; then
    return 1
  fi

  while [ -z "$SELECTED" ];
  do

    ClearScreen

    # Display the Title if present
    if [ -n "$2" ]; then
      header "$2"
    fi

    PerfTimerBegin
    JSON=$($CURL_CMD -sL $1)
    PerfTimerEnd $PERF_MAX_CURL "Curl: $1"

    if [ -z "$JSON" ]; then
      LogError "No JSON returned from [$1]!"
      exit 1
    fi

    # First check the type to see which data needs to be parsed

    PerfTimerBegin
    TYPE=$(echo "$JSON" | $JQ_CMD -r '.type')

    if [ "$TYPE" = "null" ] || [ "$TYPE" = "product-group" ]; then
      SELECT=$(echo "$JSON" | $JQ_CMD -r ' .children | map (.name) | join("\n")' | sort)

    elif [ "$TYPE" = "product" ]; then
      SELECT=$(echo "$JSON" | $JQ_CMD -r '.releases | map (.name) | join("\n")' | sort -V)

    elif [ "$TYPE" = "release" ]; then
      SELECT=$(echo "$JSON" | $JQ_CMD -r '.files | map (.name) | join("\n")' | sort)

      PRODUCT_PATH=$(echo "$JSON" | $JQ_CMD -r '.path[0].path')

    else
      echo "Invalid Type: [$TYPE]"
      exit 1
    fi

    PerfTimerEnd $PERF_MAX_JQ "JQ: parsed $TYPE"

    DebugText "TYPE: [$TYPE]"

    # In case if a product release ask which one to pick

    echo
    N=0
    while IFS= read -r LINE
    do
      if [ -n "$LINE" ]; then
        N=$(($N + 1))
        echo "[$N] $LINE"
      fi
    done <<< "$SELECT"

    if [ "$N" = "0" ]; then
      LogError "No configuration found!"
      exit 1
    fi

    # Set to one to automatically select if only one entry is in list
    if [ "$N" = "1" ]; then
      SELECTED=1
    else
      echo
      SELECTED=
      while [ -z "$SELECTED" ];
      do 
        read -p "Select [1-$N] 0 to cancel, x to go back? " SELECTED;
      done
      echo

      if [ "$SELECTED" = "0" ]; then
        exit 0
      fi

      if [ "$SELECTED" = "x" ]; then
        return 0
      fi
    fi

    DebugText "SELECTED: [$SELECTED]"

    N=0
    KEY=
    while IFS= read -r LINE
    do
      if [ -n "$LINE" ]; then
        N=$(($N + 1))
        if [ "$N" = "$SELECTED" ]; then
          KEY=$(echo $LINE | awk -v ORS="" 1)
        fi
      fi
    done <<< "$SELECT"

    if [ "$N" = "0" ]; then
      exit 1
    fi

    DebugText "KEY: [$KEY]"

    if [ -z "$KEY" ]; then
      exit 1
    fi

    # Depending on type check for children, releases or files

    PerfTimerBegin

    if [ "$TYPE" = "null" ] || [ "$TYPE" = "product-group" ]; then
      SLUG=$(echo "$JSON" | $JQ_CMD --arg key "$KEY" -r '.children[] | select(.name==$key) | .slug')

    elif [ "$TYPE" = "product" ]; then
      SLUG=$(echo "$JSON" | $JQ_CMD --arg key "$KEY" -r '.releases[] | select(.name==$key) | .slug')

    elif [ "$TYPE" = "release" ]; then
      FILE_JSON=$(echo "$JSON" | $JQ_CMD --arg key "$KEY" -r '.files[] | select(.name==$key)')
    fi

    PerfTimerEnd $PERF_MAX_JQ "JQ: parse key: $KEY"

    if [ -n "$FILE_JSON" ]; then
      DownloadProductFromPortal "$FILE_JSON" "$PRODUCT_PATH" "$SLUG"
      return 0
    fi

    if [ "null" = "$SLUG" ]; then
      return 0
    fi

    if [ -n "$SLUG" ]; then

      # Ensure to ClearScreen previous selection before jumping to sub "menu"
      SELECTED=
      TITLE=$KEY
      GetDownloadFromPortal "$1/$SLUG" "$TITLE"

      if [ "$SELECTED" = "x" ]; then
        LogMessage "Going one level back"
        SELECTED=
      else
        return 0
      fi
    fi

  done

  return 0
}


DownloadFileDataJSON()
{
  # Get a .json or .jwt file and write it in JSON format.

  local DOWNLOAD_URL=$1
  local TARGET_FILE=$2
  local JSON_OBJECT=$3
  local DOWNLOAD_FILE=

  if [ -z "$DOWNLOAD_URL" ]; then
    return 1
  fi

  if [ -z "$TARGET_FILE" ]; then
    return 1
  fi

  case "$DOWNLOAD_URL" in

    *.jwt)
      DOWNLOAD_FILE=$(echo "$TARGET_FILE" | awk -F'.json' '{print $1}').jwt
      ;;

    *)
      DOWNLOAD_FILE="$TARGET_FILE".download
      ;;
  esac

  if [ -e "$TARGET_FILE" ]; then

    # Check if file has changed manually and needs update
    if [ "$DOWNLOAD_FILE" -nt "$TARGET_FILE" ]; then
      DebugText "$DOWNLOAD_FILE newer than $TARGET_FILE -- Updating"
    else

      DebugText "$TARGET_FILE newer than $DOWNLOAD_FILE -- Checking file age"

      # File already exists and isn't older than configured age
      if [ -n "$(find "$TARGET_FILE" -mmin -$MAX_JSON_FILE_AGE_MIN 2>/dev/null)" ]; then

        DebugText "File is less than $MAX_JSON_FILE_AGE_MIN minute(s) old: $TARGET_FILE"
        return 0
      fi
    fi
  fi

  CheckConnection

  # If online download file and parse. In local mode check if file is already parsed 
  if [ "$DOMDOWNLOAD_MODE" = "online" ]; then

    DebugText "Downloading: $DOWNLOAD_URL -> $DOWNLOAD_FILE"

    PerfTimerBegin
    $CURL_CMD -sL "$DOWNLOAD_URL" -o "$DOWNLOAD_FILE"
    PerfTimerEnd $PERF_MAX_CURL "Curl: $DOWNLOAD_URL"

  else

    if [ -e "$DOWNLOAD_FILE" ]; then
      DebugText "Not on-line but file already exists: $DOWNLOAD_FILE"
    else
      LogConnectionError "No Internet connection. Please download $DOWNLOAD_URL to $DOWNLOAD_FILE"
      exit 1
    fi

  fi

  DebugText "DOWNLOAD_FILE: [$DOWNLOAD_FILE]"
  DebugText "TARGET_FILE  : [$TARGET_FILE]"
  DebugText "JSON_OBJECT  : [$JSON_OBJECT]"

  case "$DOWNLOAD_URL" in

    *.jwt)

      local PAYLOAD_BASE64URL=$(cat "$DOWNLOAD_FILE" | /usr/bin/cut -d"." -f2)
      local PAYLOAD_BASE64=$(echo -n $PAYLOAD_BASE64URL | tr '_-' '/+')

      # Add padding for valid BASE64 encoding (base64url encoding removes padding)
      local PAD_COUNT=$(expr 4 - ${#PAYLOAD_BASE64} % 4)

      if [ "$PAD_COUNT" != "4" ]; then
        while ((PAD_COUNT--)); do PAYLOAD_BASE64=$PAYLOAD_BASE64=; done
      fi

      if [ -z "$JSON_OBJECT" ]; then
        echo "$PAYLOAD_BASE64" | openssl base64 -d -A | $JQ_CMD -r > "$TARGET_FILE"
      else
        echo "$PAYLOAD_BASE64" | openssl base64 -d -A | $JQ_CMD -r ".$JSON_OBJECT[]" > "$TARGET_FILE"
      fi

      ;;

    *)

      if [ -z "$JSON_OBJECT" ]; then
        cat "$DOWNLOAD_FILE" | $JQ_CMD -r > "$TARGET_FILE"
      else
        cat "$DOWNLOAD_FILE" | $JQ_CMD -r ".$JSON_OBJECT[]" > "$TARGET_FILE"
      fi
      ;;
  esac

  # Check if resulting file is valid JSON

  $JQ_CMD -e '.' "$TARGET_FILE" >/dev/null 2>&1

  if [ "$?" = "0" ]; then
     DebugText "JSON is valid: $TARGET_FILE"
  else
     LogError "JSON file is invalid: $TARGET_FILE"
     exit 1
  fi

}


GetSoftwareConfig()
{
  # Gets software configuration. If not yet downloaded, get configuration from software.json/jwt

  DOMDOWNLOAD_CFG_SOFTWARE_FILE=$DOMDOWNLOAD_CFG_DIR/software.cfg

  if [ -e "$DOMDOWNLOAD_CFG_SOFTWARE_FILE" ]; then
    . "$DOMDOWNLOAD_CFG_SOFTWARE_FILE"
    return 0
  fi

  local CONFIG=

  if [ -z "$SOFTWARE_URL" ]; then
    LogError "No software URL specified"
    exit 1
  fi

  CheckConnection

  if [ "$DOMDOWNLOAD_MODE" = "local" ]; then
    DebugText "No configuration needed in local mode"

  elif [ ! "$DOMDOWNLOAD_MODE" = "online" ]; then

    if [ ! -e "$2" ]; then
      LogConnectionError "No Internet connection"
      exit 1
    fi

  fi

  PerfTimerBegin

  case "$SOFTWARE_URL" in

    *.jwt)

      local PAYLOAD_BASE64URL=$($CURL_CMD -sL "$SOFTWARE_URL" | /usr/bin/cut -d"." -f2)

      local PAYLOAD_BASE64=$(echo -n $PAYLOAD_BASE64URL | tr '_-' '/+')

      # Add padding for valid BASE64 encoding (base64url encoding removes padding)
      local PAD_COUNT=$(expr 4 - ${#PAYLOAD_BASE64} % 4)

      if [ "$PAD_COUNT" != "4" ]; then
        while ((PAD_COUNT--)); do PAYLOAD_BASE64=$PAYLOAD_BASE64=; done
      fi

      CONFIG=$(echo "$PAYLOAD_BASE64" | openssl base64 -d -A | $JQ_CMD -r '.configuration.tokenURL + "|" + .configuration.downloadURLPrefix + "|" + .configuration.downloadURLSuffix')
      ;;

    *)

      CONFIG=$($CURL_CMD -sL "$SOFTWARE_URL" | $JQ_CMD -r '.configuration.tokenURL + "|" + .configuration.downloadURLPrefix + "|" + .configuration.downloadURLSuffix')
      ;;
  esac

  PerfTimerEnd $PERF_MAX_CURL "Curl: $SOFTWARE_URL"

  if [ -z "$CONFIG" ]; then
    LogError "No configuration found"
    exit 1
  fi

  # cut is faster to than JQ and is a very simple operation
  MYHCL_TOKEN_URL=$(echo "$CONFIG" | /usr/bin/cut -d"|" -f1)
  MYHCL_DOWNLOAD_URL_PREFIX=$(echo "$CONFIG" | /usr/bin/cut -d"|" -f2)
  MYHCL_DOWNLOAD_URL_SUFFIX=$(echo "$CONFIG" | /usr/bin/cut -d"|" -f3)

  DebugText "Token URL:      " $MYHCL_TOKEN_URL
  DebugText "Download Prefix:" $MYHCL_DOWNLOAD_URL_PREFIX
  DebugText "Download Suffix:" $MYHCL_DOWNLOAD_URL_SUFFIX

  echo "MYHCL_TOKEN_URL=$MYHCL_TOKEN_URL" >> "$DOMDOWNLOAD_CFG_SOFTWARE_FILE"
  echo "MYHCL_DOWNLOAD_URL_PREFIX=$MYHCL_DOWNLOAD_URL_PREFIX" >> "$DOMDOWNLOAD_CFG_SOFTWARE_FILE"
  echo "MYHCL_DOWNLOAD_URL_SUFFIX=$MYHCL_DOWNLOAD_URL_SUFFIX" >> "$DOMDOWNLOAD_CFG_SOFTWARE_FILE"
}


GetSoftwareList()
{
  # Create the software list and write it to a file

  local JSON=
  local FILE_JSON=

  if [ -z "$1" ]; then
    return 1
  fi

  if [ -z "$2" ]; then
    return 1
  fi

  DownloadFileDataJSON "$1" "$CATALOG_JSON_FILE" "files"

  cat "$CATALOG_JSON_FILE" | $JQ_CMD -r '[(.locations[0] | ascii_upcase | sub("DOMINO/DOMINO/";"domino|") | sub("DOMINO/NOMAD/";"nomad|") | sub("DOMINO/VERSE/";"verse|") | sub("DOMINO/NOTES/";"notes|") | sub("DOMINO/TRAVELER/";"traveler|") | sub("DOMINO/VERSE/";"verse|") | sub("DOMINO/CAPI/";"capi|") | sub("DOMINO/SAFELINX/";"safelinx|") | sub("DOMINO/RESTAPI/";"restapi|")), .name, .id, .checksums.sha256] | @csv | sub("\"";"";"g")' | grep -v DOMINO | sed -e 's~,~|~g' > "$2"

  return 0
}


GetSoftwareFromCatalogByName()
{
  # Get software by name from catalog

  # $1 : URL
  # $2 : FileName

  if [ -z "$1" ]; then
    return 1
  fi

  if [ -z "$2" ]; then
    return 1
  fi

  DownloadFileDataJSON "$1" "$CATALOG_JSON_FILE" "files"

  PRODUCT_INFO=$(cat "$CATALOG_JSON_FILE" | $JQ_CMD --arg key "$2" -r 'select(.name==$key)')
  GetProductLinePortal
}


GetLatestVersionProductJSON()
{
  DownloadFileDataJSON "$1" "$PRODUCT_JSON_FILE" "product"
  PRODUCT_VERSION=$(cat "$PRODUCT_JSON_FILE" | $JQ_CMD --arg key "$2" -r 'select(.product==$key) | .version')
}


GetFileFromSoftwareJSON()
{
  # Get a file from software.json/jwt

  local LOOKUP_TYPE=$5
  local LOOKUP_LANG=$6

  FILE_NAME=

  if [ -z "$1" ]; then
    return 1
  fi

  if [ -z "$2" ]; then
    return 1
  fi

  if [ -z "$3" ]; then
    return 1
  fi

  if [ -z "$4" ]; then
    return 1
  fi

  if [ -z "$5" ]; then
    LOOKUP_TYPE=server
  fi

  DownloadFileDataJSON "$1" "$SOFTWARE_JSON_FILE" "software"

  if [ -z "$LOOKUP_LANG" ]; then
    PRODUCT_INFO=$(cat "$SOFTWARE_JSON_FILE" | $JQ_CMD --arg product "$2" --arg version "$3" --arg platform "$4" --arg type "$LOOKUP_TYPE" -r 'select(.product==$product and .type==$type and .label==$version and (.platform|type=="string") and .platform==$platform )')
  else
    PRODUCT_INFO=$(cat "$SOFTWARE_JSON_FILE" | $JQ_CMD --arg product "$2" --arg version "$3" --arg platform "$4" --arg type "$LOOKUP_TYPE" --arg lang "$LOOKUP_LANG" -r 'select(.product==$product and .type==$type and .label==$version and ((.platform|type=="array") and (.platform[] |contains ($platform))) and .language==$lang)')
  fi
  GetProductLineAutoUpdate
}


GetSoftwareByNameFromSoftwareJSON()
{
  # Get a file from software.json/jwt by file name

  if [ -z "$1" ]; then
    return 1
  fi

  if [ -z "$2" ]; then
    return 1
  fi

  DownloadFileDataJSON "$1" "$SOFTWARE_JSON_FILE" "software"

  DebugText "FILE_NAME: [$2]"

  PRODUCT_INFO=$(cat "$SOFTWARE_JSON_FILE" | $JQ_CMD --arg filename "$2" -r 'select(.fileName==$filename)')
  GetProductLineAutoUpdate
}


GetDownloadFromSoftwareJSON()
{
  # Search a download in software.json/jwt

  FILE_LANG=
  FILE_TYPE=
  FILE_PRODUCT=
  FILE_PLATFORM=
  FILE_VERSION=

  local CURRENT_JSON=
  local SELECT=
  local TEMP=

  DownloadFileDataJSON "$1" "$SOFTWARE_JSON_FILE" "software"

  CURRENT_JSON=$(cat "$SOFTWARE_JSON_FILE")

  ClearScreen
  header "My HCL Software Download (AutoUpdate Navigation)"

  SELECT=$(echo "$CURRENT_JSON" | $JQ_CMD -r '.product' | sort | uniq)

  echo
  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      echo "[$N] $LINE"
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    LogError "No product found!"
    return 1
  fi

  # Set to one to automatically select if only one entry is in list
  if [ "$N" = "1" ]; then
    SELECTED=1
  else
    echo
    SELECTED=
    while [ -z "$SELECTED" ];
    do 
      read -p "Select Product [1-$N] 0 to cancel? " SELECTED;
    done
    echo

    if [ "$SELECTED" = "0" ]; then
      return 0
    fi
  fi

  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      if [ "$N" = "$SELECTED" ]; then
        FILE_PRODUCT=$(echo $LINE | awk -v ORS="" 1)
      fi
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    return 0
  fi

  CURRENT_JSON=$(echo "$CURRENT_JSON" | $JQ_CMD --arg product "$FILE_PRODUCT" -r 'select(.product==$product)')

  ClearScreen
  header "Select Type"

  SELECT=$(echo "$CURRENT_JSON" | $JQ_CMD -r .type | sort | uniq)

  echo
  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      echo "[$N] $LINE"
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    LogError "No type found!"
    return 1
  fi

  # Set to one to automatically select if only one entry is in list
  if [ "$N" = "1" ]; then
    SELECTED=1
  else
    echo
    SELECTED=
    while [ -z "$SELECTED" ];
    do 
      read -p "Select Type [1-$N] 0 to cancel? " SELECTED;
    done
    echo

    if [ "$SELECTED" = "0" ]; then
      return 0
    fi
  fi

  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      if [ "$N" = "$SELECTED" ]; then
        FILE_TYPE=$(echo $LINE | awk -v ORS="" 1)
      fi
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    return 0
  fi

  CURRENT_JSON=$(echo "$CURRENT_JSON" | $JQ_CMD --arg type "$FILE_TYPE" -r 'select(.type==$type)')

  ClearScreen
  header "Select Platform"

  SELECT=$(echo "$CURRENT_JSON" | $JQ_CMD -r '( (select(.platform|type=="array") | .platform[]), (select(.platform|type=="string") | .platform) )' | sort | uniq)

  echo
  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      echo "[$N] $LINE"
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    LogError "No platform found!"
    return 1
  fi

  # Set to one to automatically select if only one entry is in list
  if [ "$N" = "1" ]; then
    SELECTED=1
  else
    echo
    SELECTED=
    while [ -z "$SELECTED" ];
    do 
      read -p "Select Platform [1-$N] 0 to cancel? " SELECTED;
    done
    echo

    if [ "$SELECTED" = "0" ]; then
      return 0
    fi
  fi

  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      if [ "$N" = "$SELECTED" ]; then
        FILE_PLATFORM=$(echo $LINE | awk -v ORS="" 1)
      fi
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    return 0
  fi

  CURRENT_JSON=$(echo "$CURRENT_JSON" | $JQ_CMD --arg platform "$FILE_PLATFORM" -r 'select( ((.platform|type=="array") and .platform[]==$platform) or ((.platform|type=="string") and .platform==$platform))' )

  ClearScreen
  header "Select Version"

  SELECT=$(echo "$CURRENT_JSON" | $JQ_CMD -r .labelVersion | sort -V | uniq)

  echo
  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      echo "[$N] $LINE"
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    LogError "No version found!"
    return 1
  fi

  # Set to one to automatically select if only one entry is in list
  if [ "$N" = "1" ]; then
    SELECTED=1
  else
    echo
    SELECTED=
    while [ -z "$SELECTED" ];
    do 
      read -p "Select Version [1-$N] 0 to cancel? " SELECTED;
    done
    echo

    if [ "$SELECTED" = "0" ]; then
      return 0
    fi
  fi

  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      if [ "$N" = "$SELECTED" ]; then
        FILE_VERSION=$(echo $LINE | awk -v ORS="" 1)
      fi
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    return 0
  fi

  ClearScreen
  header "Select Software"

  CURRENT_JSON=$(echo "$CURRENT_JSON" | $JQ_CMD --arg version "$FILE_VERSION" -r 'select(.labelVersion==$version)')
  SELECT=$(echo "$CURRENT_JSON" | $JQ_CMD -r '((select(.language|type=="array") | .language[]), (select(.language|type=="string") | .language))' | sort | uniq)

  echo
  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      echo "[$N] $LINE"
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then

    # Empty language is perfectly OK
    DebugText "No language found!"

  else

    # Set to one to automatically select if only one entry is in list
    if [ "$N" = "1" ]; then
      SELECTED=1
    else
    echo
      SELECTED=
      while [ -z "$SELECTED" ];
      do 
        read -p "Select Language [1-$N] 0 to cancel? " SELECTED;
      done
      echo

      if [ "$SELECTED" = "0" ]; then
        return 0
      fi
    fi

    N=0
    while IFS= read -r LINE
    do
      if [ -n "$LINE" ]; then
        N=$(($N + 1))
        if [ "$N" = "$SELECTED" ]; then
          FILE_LANG=$(echo $LINE | awk -v ORS="" 1)
        fi
      fi
    done <<< "$SELECT"

    if [ "$N" = "0" ]; then
      return 0
    fi
  fi

  CURRENT_JSON=$(echo "$CURRENT_JSON" | $JQ_CMD --arg lang "$FILE_LANG" -r 'select( (((.language|type=="array") and .language[]==$lang) or ((.language|type=="string") and .language==$lang)) )')

  ClearScreen
  header "Selected software"

  SELECT=$(echo "$CURRENT_JSON" | $JQ_CMD -r .description)

  echo
  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      echo "[$N] $LINE"
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    LogError "No software found!"
    return 1
  fi

  # Set to one to automatically select if only one entry is in list
  if [ "$N" = "1" ]; then
    SELECTED=1
  else
    echo
    SELECTED=
    while [ -z "$SELECTED" ];
    do 
      read -p "Select WebKit [1-$N] 0 to cancel? " SELECTED;
    done
    echo

    if [ "$SELECTED" = "0" ]; then
      return 0
    fi
  fi

  N=0
  while IFS= read -r LINE
  do
    if [ -n "$LINE" ]; then
      N=$(($N + 1))
      if [ "$N" = "$SELECTED" ]; then
        FILE_DESCRIPTION=$(echo $LINE | awk -v ORS="" 1)
      fi
    fi
  done <<< "$SELECT"

  if [ "$N" = "0" ]; then
    return 0
  fi

  PRODUCT_INFO=$(echo "$CURRENT_JSON" | $JQ_CMD --arg description "$FILE_DESCRIPTION" -r 'select(.description==$description)')
  GetProductLineAutoUpdate
}


TranslatePlatform()
{
 
 local PLATFORM_LOWERCASE=$(echo "$SEARCH_PLATFORM" | /usr/bin/awk '{print tolower($0)}')
 
 case "$PLATFORM_LOWERCASE" in

    linux|tux)
      SEARCH_PLATFORM="Linux/64"
      ;;

    windows|win)
      SEARCH_PLATFORM="Windows/64"
      ;;

    aix)
      SEARCH_PLATFORM="AIX/64"
      ;;

    os400|as400)
      SEARCH_PLATFORM="OS/400"
      ;;

  esac
}


CheckWriteStandardConfig()
{
  if [ -e "$DOMDOWNLOAD_CFG_FILE" ]; then
    DebugText "Configuration already exists"
    return 0;
  fi

  echo "Creating new configuration file $DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"

  echo \#Paramters to pass to Curl command >> "$DOMDOWNLOAD_CFG_FILE"
  echo SPECIAL_CURL_ARGS= >> "$DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"

  echo \#Software direcory >> "$DOMDOWNLOAD_CFG_FILE"
  echo \#SOFTWARE_DIR=/local/software >> "$DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"

  echo \#Maximum age of json/jwt files >> "$DOMDOWNLOAD_CFG_FILE"
  echo MAX_JSON_FILE_AGE_MIN=10 >> "$DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"

  echo \#Custom download URL for local mode >> "$DOMDOWNLOAD_CFG_FILE"
  echo DOMDOWNLOAD_CUSTOM_URL= >> "$DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"

  echo \#User for custom download in local mode >> "$DOMDOWNLOAD_CFG_FILE"
  echo DOMDOWNLOAD_CUSTOM_USER= >> "$DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"

  echo \#Password for custom download in local mode >> "$DOMDOWNLOAD_CFG_FILE"
  echo DOMDOWNLOAD_CUSTOM_PASSWORD= >> "$DOMDOWNLOAD_CFG_FILE"
  echo >> "$DOMDOWNLOAD_CFG_FILE"
}


InstallScript()
{
  local TARGET_FILE="/usr/local/bin/domdownload"
  local INSTALL_FILE=
  local SUDO=
  local CURRENT_VERSION=

  if [ "$2" = "debug" ]; then
    DOMDOWNLOAD_DEBUG=yes
  fi

  if [ -x "$TARGET_FILE" ]; then
    CURRENT_VERSION=$($TARGET_FILE --version)

    if [ "$DOMDOWNLOAD_SCRIPT_VERSION" = "$CURRENT_VERSION" ]; then
      LogMessage "Latest version $CURRENT_VERSION already installed"
      exit 0
    fi
  fi

  if [ "$SCRIPT_NAME" = "bash" ]; then
    if [ -n "$1" ]; then
      INSTALL_FILE=$1
    else
      LogError "Installation failed - Running in bash pipe without script file specified"
      exit 1
    fi
  else
    INSTALL_FILE=$SCRIPT_NAME
  fi

  if [ ! -r "$INSTALL_FILE" ]; then
    LogError "Installation failed - Cannot read file: $INSTALL_FILE"
    exit 1
  fi

  header "Install Domino Download Script"

  if [ ! -w "/usr/local/bin" ]; then
    LogMessage "Info: Need root permissions to install $TARGET_FILE (you might get prompted for sudo permissions)"
    SUDO=sudo
  fi

  $SUDO cp "$INSTALL_FILE" "$TARGET_FILE"

  if [ ! "$?" = "0" ]; then
    LogError "Installation failed - Cannot copy [$INSTALL_FILE] to [$TARGET_FILE]"
    exit 1
  fi

  $SUDO chmod +x "$TARGET_FILE"

  if [ ! "$?" = "0" ]; then
    LogError "Installation failed - Cannot change permissions for [$TARGET_FILE]"
    exit 1
  fi

  if [ "$SCRIPT_NAME" = "bash" ]; then
    DebugText "Removing temp script [$INSTALL_FILE]"
    remove_file "$INSTALL_FILE"
  fi

  if [ -z "$CURRENT_VERSION" ]; then
    LogMessage "Successfully installed version $DOMDOWNLOAD_SCRIPT_VERSION to $TARGET_FILE"
  else
    LogMessage "Successfully updated from version $CURRENT_VERSION to $DOMDOWNLOAD_SCRIPT_VERSION"
  fi

  return 0
}


Usage()
{
  echo
  echo Domino Download Script $DOMDOWNLOAD_SCRIPT_VERSION
  print_delim
  echo
  echo "Usage: $SCRIPT_NAME" [options] [WebKit filename]
  echo
  echo "-autoupdate             Navigate software list via software.json"
  echo "-myhcl                  Navigate software list via MyHCL portal (default)"
  echo "-download=<filename>    Download software by WebKit file name"
  echo "-curl                   Print download curl command instead of downloading"
  echo "-out=<fileName>         Custom download target filename (overwrites file name from JSON)"
  echo "-dir=<directory>        Custom download directory"
  echo "-force                  Replace existing download"
  echo "-silent                 Don't print software info"
  echo
  echo "-product=<name>         Product to find"
  echo "-platform=<name>        Platform to find (win|linux|aix|os400)"
  echo "-type=<str>             Type to find (server|client|langpack) Default: server"
  echo "-lang=<str>             Language to find (DE|EN|IT..)"
  echo "-ver=<version>          Version to find"
  echo "-download               Download file after find else print file name"
  echo
  echo "-connect                Confirm internet connection"
  echo "-token                  Prompt for new download token"
  echo "-token=<value>          Set new download token"
  echo "-reload                 Reload JSON Files and configuration"
  echo "-reset                  Reset cached software configuration"
  echo "-cfg/cfg                Edit configuration"
  echo "-debug                  Enable debugging"
  echo "-install                Install or update script"
  echo "-version/--version      prints version and exits"
  echo
  echo
  echo "Examples:"
  echo
  echo "Download selected software:"
  echo
  echo "./domdownload.sh -product=domino -platform=linux -ver=12.0.2FP2 -download"
  echo
  echo "Note: without -download only prints file name"
  echo
  echo
  echo "Find latest version:"
  echo
  echo "./domdownload.sh -product=domino -platform=linux"
  echo
  echo
  echo "Download file by file name:"
  echo
  echo "./domdownload.sh Domino_1202FP2_Linux.tar"
  echo
  echo
  echo "Use HCL AutoUpdate JSON instead of My HCL Software data for download navigation:"
  echo
  echo "./domdownload.sh -autoupdate"
  echo

  return 0
}


# Main Logic

if [ -z "$DOMDOWNLOAD_CFG_DIR" ]; then

  if [ -e .DominoDownload ]; then
    DOMDOWNLOAD_CFG_DIR=$(pwd)/.DominoDownload
  else
    DOMDOWNLOAD_CFG_DIR=~/.DominoDownload
  fi
fi

if [ -z "$PERF_MAX_CURL" ]; then
  PERF_MAX_CURL=1000
fi

if [ -z "$PERF_MAX_JQ" ]; then
  PERF_MAX_JQ=100
fi

if [ -z "$PERF_MAX_CHECKSUM" ]; then
  PERF_MAX_CHECKSUM=5000
fi

if [ -z "$PERF_MAX_LOG_LINES" ]; then
  PERF_MAX_LOG_LINES=100
fi

PERF_LOG_FILE=$DOMDOWNLOAD_CFG_DIR/domdownload.perf


if [ ! -e "$DOMDOWNLOAD_CFG_DIR" ]; then
    LogMessage "Info: Creating configuration directory: $DOMDOWNLOAD_CFG_DIR"
    mkdir -p "$DOMDOWNLOAD_CFG_DIR"
fi

if [ -z "$DOMDOWNLOAD_CFG_FILE" ]; then
  DOMDOWNLOAD_CFG_FILE=$DOMDOWNLOAD_CFG_DIR/domdownload.cfg
fi

if [ -z "$DOMDOWNLOAD_TOKEN_FILE_NAME" ]; then
  DOMDOWNLOAD_TOKEN_FILE_NAME=$DOMDOWNLOAD_CFG_DIR/download.token
fi

if [ -z "$DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME" ]; then
  DOMDOWNLOAD_CACHED_ACCESS_TOKEN_FILE_NAME=$DOMDOWNLOAD_CFG_DIR/cached_access.token
fi

# Check if config exists, else create default config
CheckWriteStandardConfig

if [ -r "$DOMDOWNLOAD_CFG_FILE" ]; then
  DebugText "Using $DOMDOWNLOAD_CFG_FILE"
  . "$DOMDOWNLOAD_CFG_FILE"
fi

if [ -z "$MYHCL_PORTAL_URL" ]; then
  MYHCL_PORTAL_URL=https://my.hcltechsw.com
fi

MYHCL_CATALOG_URL=$MYHCL_PORTAL_URL/catalog/domino

if [ -z "$MYHCL_API_URL" ]; then
  MYHCL_API_URL=https://api.hcltechsw.com
fi

if [ -z "$HCL_AUTOUPDATE_URL" ]; then
   HCL_AUTOUPDATE_URL=https://ds_infolib.hcltechsw.com
fi

SOFTWARE_URL=$HCL_AUTOUPDATE_URL/software.jwt
PRODUCT_URL=$HCL_AUTOUPDATE_URL/product.jwt
GITHUB_URL=https://github.com

if [ -z "$EDIT_COMMAND" ]; then
  EDIT_COMMAND="vi"
fi

if [ -z $CURL_DOWNLOAD_TIMEOUT ]; then
  CURL_DOWNLOAD_TIMEOUT=900
fi

CheckEnvironment

CURL_CMD="$CURL_BIN --max-redirs 10 --connect-timeout 15 --max-time 300 $SPECIAL_CURL_ARGS"
CURL_DOWNLOAD_CMD="$CURL_BIN --max-redirs 10 --fail --connect-timeout 15 --max-time $CURL_DOWNLOAD_TIMEOUT $SPECIAL_CURL_ARGS"

if [ -z "$MAX_JSON_FILE_AGE_MIN" ]; then
  MAX_JSON_FILE_AGE_MIN=10
fi

PRODUCT_JSON_FILE=$DOMDOWNLOAD_CFG_DIR/product.json
SOFTWARE_JSON_FILE=$DOMDOWNLOAD_CFG_DIR/software.json
CATALOG_JSON_FILE=$DOMDOWNLOAD_CFG_DIR/catalog.json
CONNECTION_AGREED_FILE=$DOMDOWNLOAD_CFG_DIR/connection-agreed.txt

for a in "$@"; do

  p=$(echo "$a" | /usr/bin/awk '{print tolower($0)}')

  case "$p" in

    -autoupdate)
      DOMDOWNLOAD_FROM=autoupdate
      ;;

    -myhcl)
      DOMDOWNLOAD_FROM=myhcl
      ;;

    -token)
      SetRefreshToken
      exit 0
      ;;

    -token=*)
      REFRESH_TOKEN=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      SetRefreshToken "$REFRESH_TOKEN"
      exit 0
      ;;

    -download=*)
      DOWNLOAD_WEB_KIT_NAME=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      ;;

    -download)
      DOWNLOAD_SELECTED=yes
      ;;

    -software)
      SOFTWARE_FILE=software.txt
      ;;

    -software=*)
      SOFTWARE_FILE=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      ;;

    -dir=*)
      SOFTWARE_DIR=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      ;;

    -ls|ls)
      echo
      if [ -z "$SOFTWARE_DIR" ]; then
        header $(pwd)
       else
        if [ ! -e "$SOFTWARE_DIR" ]; then
          LogError "Software directory does not exist"
          exit 1
        fi
        header "$SOFTWARE_DIR"
      fi

      ls -lhS "$SOFTWARE_DIR"
      echo
      exit 0
      ;;

    -ver=*|-version=*)
      PRODUCT_VERSION=$(echo "$a" | /usr/bin/cut -f2 -d= -s | tr '[a-z]' '[A-Z]')
      ;;

    -product=*)
      SEARCH_PRODUCT_NAME=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      ;;

    -platform=*)
      SEARCH_PLATFORM=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      TranslatePlatform
      ;;

    -type=*)
      SEARCH_TYPE=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      ;;

    -lang=*|-language=*)
      SEARCH_LANG=$(echo "$a" | /usr/bin/cut -f2 -d= -s | /usr/bin/awk '{print toupper($0)}')
      ;;

    -out=*)
      OUT_FILE_NAME=$(echo "$a" | /usr/bin/cut -f2 -d= -s)
      ;;

    -curl)
      PRINT_DOWNLOAD_CURL_CMD=yes
      ;;

    -softline)
      PRINT_SOFTWARE_LINE=yes
      ;;

    -s3)
      DOWNLOAD_VIA_S3=yes
      DOMDOWNLOAD_FROM=autoupdate
      ;;

    -reload)
      MAX_JSON_FILE_AGE_MIN=1
      ;;

    -reset)
      MAX_JSON_FILE_AGE_MIN=1
      if [ -e "$DOMDOWNLOAD_CFG_SOFTWARE_FILE" ]; then
        remove_file "$DOMDOWNLOAD_CFG_SOFTWARE_FILE"
      fi
      ;;

    -force)
      FORCE_DOWNLOAD=yes
      ;;

    -info)
      PRINT_INFO_ONLY=yes
      ;;

    -silent)
      SILENT_MODE=yes
      ;;

    -debug)
      DOMDOWNLOAD_DEBUG=yes
      ;;

    -connect)
      ConfirmConnection
      ;;

    -version|--version)
      echo "$DOMDOWNLOAD_SCRIPT_VERSION"
      exit 0
      ;;

    -cfg|cfg)
      "$EDIT_COMMAND" "$DOMDOWNLOAD_CFG_FILE"
      exit 0
      ;;

    -install|install)
      InstallScript "$2" "$3"
      CheckEnvironment
      CheckConnection
      exit 0
      ;;

    perf)
      if [ "$2" = "clear" ] || [ "$2" = "reset" ]; then
	LogMessage "Removing $PERF_LOG_FILE"
        remove_file "$PERF_LOG_FILE"

      elif [ -e "$PERF_LOG_FILE" ]; then
        "$EDIT_COMMAND" "$PERF_LOG_FILE"
      fi
      exit 0
      ;;

    -h|/h|-?|/?|-help|--help|help|usage)
      Usage
      exit 0
      ;;

    -*)
      LogError "Invalid parameter [$a]"
      exit 1
      ;;

    *)
      DOWNLOAD_WEB_KIT_NAME=$a
      ;;

  esac

done

PerfTimerLogSession
GetSoftwareConfig

if [ -z "$SOFTWARE_DIR" ]; then
  SOFTWARE_DIR=$(pwd)
else
  if [ ! -e "$SOFTWARE_DIR" ]; then
    LogMessage "Creating software directory: $SOFTWARE_DIR"
    mkdir -p "$SOFTWARE_DIR"
  fi
fi

if [ -n "$SEARCH_PRODUCT_NAME" ] && [ -n "$PRODUCT_VERSION" ] && [ -n "$SEARCH_PLATFORM" ]; then

  GetFileFromSoftwareJSON "$SOFTWARE_URL" "$SEARCH_PRODUCT_NAME" "$PRODUCT_VERSION" "$SEARCH_PLATFORM" "$SEARCH_TYPE" "$SEARCH_LANG"

  if [ "$DOWNLOAD_SELECTED" = "yes" ] || [ "$PRINT_DOWNLOAD_CURL_CMD" = "yes" ]; then

    if [ -z "$FILE_ID" ]; then
      LogError "No WebKit found"
      exit 1
    fi

    if [ "$PRINT_DOWNLOAD_CURL_CMD" = "yes" ]; then
      LogMessageIfNotSilent "Checking WebKit download command for $FILE_NAME ..."
    else
      LogMessageIfNotSilent "Downloading WebKit $FILE_NAME ..."
    fi

    DownloadSoftware "$FILE_ID" "$FILE_NAME" "$FILE_CHECKSUM_SHA256"

  else
    echo "$FILE_NAME"
  fi

  exit 0

elif [ -n "$SEARCH_PRODUCT_NAME" ] && [ -z "$PRODUCT_VERSION" ]; then

  if [ "$DOWNLOAD_SELECTED" = "yes" ]; then
     LogError "Invalid software selection for download"
     exit 1
  fi

  GetLatestVersionProductJSON "$PRODUCT_URL" "$SEARCH_PRODUCT_NAME"

  echo "$PRODUCT_VERSION"
  exit 0
fi

if [ -n "$SOFTWARE_FILE" ]; then

  if [ -e "$SOFTWARE_FILE" ]; then
    remove_file "$SOFTWARE_FILE"
  fi

  GetSoftwareList "$MYHCL_PORTAL_URL/files/domino" "$SOFTWARE_FILE"
  LogMessage "Runtime : $SECONDS"

  echo
  print_delim
  cat "$SOFTWARE_FILE"
  print_delim
  echo

  exit 0
fi

if [ -n "$DOWNLOAD_WEB_KIT_NAME" ]; then

  OUTFILE_WEBKIT_FULLPATH="$SOFTWARE_DIR/$DOWNLOAD_WEB_KIT_NAME"
  if [ -e "$OUTFILE_WEBKIT_FULLPATH" ]; then

    if [ "$FORCE_DOWNLOAD" = "yes" ]; then
      DebugText "WebKit [$DOWNLOAD_WEB_KIT_NAME] already exists, but download was forced: [$OUTFILE_WEBKIT_FULLPATH]"
    else
      LogMessageIfNotSilent "Info: File already exists [$OUTFILE_WEBKIT_FULLPATH]"
      exit 0
    fi
  fi

  LogMessage Searching for WebKit $DOWNLOAD_WEB_KIT_NAME ...

  if [ "$DOMDOWNLOAD_FROM" = "autoupdate" ]; then
    GetSoftwareByNameFromSoftwareJSON "$SOFTWARE_URL" "$DOWNLOAD_WEB_KIT_NAME"
  else
    GetSoftwareFromCatalogByName "$MYHCL_PORTAL_URL/files/domino" "$DOWNLOAD_WEB_KIT_NAME"
  fi

  if [ -z "$FILE_ID" ]; then
    LogError "No WebKit found"
    exit 1
  fi

fi

if [ -n "$FILE_ID" ]; then

  if [ -z "$FILE_NAME" ]; then
    LogError "No file name specified"
    exit 1
  fi

  DownloadSoftware "$FILE_ID" "$FILE_NAME" "$FILE_CHECKSUM_SHA256"

  exit 0
fi


CheckConnection
if [ ! "$DOMDOWNLOAD_MODE" = "online" ]; then

  if [ "$DOMDOWNLOAD_FROM" = "autoupdate" ]; then
    DebugText "Not online - but autoupdate works also in local mode."

  elif [ -z "$DOMDOWNLOAD_FROM" ]; then
    DebugText "If no download from is specified assume 'autoupdate' in local mode"
    DOMDOWNLOAD_FROM=autoupdate

  else
    LogConnectionError "No connection to software portal"
    exit 1
  fi
fi

if [ "$DOMDOWNLOAD_FROM" = "autoupdate" ]; then

  GetDownloadFromSoftwareJSON "$SOFTWARE_URL"

  if [ "$SELECTED" = "0" ]; then
    exit 1
  fi

  if [ -n "$DOMDOWNLOAD_CUSTOM_URL" ]; then
    DownloadCustom "$FILE_NAME"
    exit 0
  fi

  if [ "$DOWNLOAD_VIA_S3" = "yes" ]; then
    DownloadS3 "$FILE_INFO_S3" "$FILE_NAME"
    exit 0
  fi

else

  GetDownloadFromPortal "$MYHCL_CATALOG_URL" "My HCL Software Download"
fi

if [ -n "$FILE_ID" ]; then

  if [ -z "$FILE_NAME" ]; then
    LogError "No file name specified"
    exit 1
  fi

  DownloadSoftware "$FILE_ID" "$FILE_NAME" "$FILE_CHECKSUM_SHA256"

fi

exit 0
