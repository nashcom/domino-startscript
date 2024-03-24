#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023 - APACHE 2.0 see LICENSE
############################################################################

# Domino on Linux installation script
# Version 3.8.1 01.03.2024

# - Installs required software
# - Adds notes:notes user and group
# - Creates directory structure in /local/ for the Domino server data (/local/notesdata, /local/translog, ...)
# - Installs NashCom Domino on Linux start script
# - Creates a new NRPC firewall rule and opens ports NRPC, HTTP, HTTPS and SMTP
# - Installs Domino with default options using silent install
# - Sets security limits

SCRIPT_NAME=$(readlink -f $0)
SCRIPT_DIR=$(dirname $SCRIPT_NAME)

# Get install options if specified
if [ -n "$1" ]; then
  INSTALL_OPTIONS="$@"
fi

if [ -n "$DOWNLOAD_FROM" ]; then
  echo "Downloading and installing software from [$DOWNLOAD_FROM]"

elif [ -n "$SOFTWARE_DIR" ]; then
  echo "Installing software from [$SOFTWARE_DIR]"

else
  SOFTWARE_DIR=/local/software
  echo "Installing software from default location [$SOFTWARE_DIR]"
fi

# In any case set a software directory
if [ -z "$SOFTWARE_DIR" ]; then
  SOFTWARE_DIR=/local/software
fi

if [ -z "$HCL_SOFTWARE" ]; then
  HCL_SOFTWARE=/local/HCLSoftware
fi

if [ -z "$INSTALL_TEMP_DIR" ]; then
  INSTALL_TEMP_DIR=/tmp/install_domino_$$
fi

if [ -z "$DOMINO_START_SCRIPT_GIT_ZIP" ]; then
  DOMINO_START_SCRIPT_GIT_ZIP=https://github.com/nashcom/domino-startscript/archive/refs/heads/develop.zip
fi

if [ -z "$DOMINO_CONTAINER_GIT_ZIP" ]; then
  DOMINO_CONTAINER_GIT_ZIP=https://github.com/HCL-TECH-SOFTWARE/domino-container/archive/refs/heads/develop.zip
fi


SPECIAL_CURL_ARGS=
CURL_CMD="curl --fail --location --connect-timeout 15 --max-time 300 $SPECIAL_CURL_ARGS"

if [ -z "$DOMINO_USER" ]; then
  DOMINO_USER=notes
fi

if [ -z "$DOMINO_GROUP" ]; then
  DOMINO_GROUP=notes
fi

if [ -z "$DIR_PERM" ]; then
  DIR_PERM=770
fi


print_delim()
{
  echo "--------------------------------------------------------------------------------"
}

log_ok ()
{
  echo
  echo "$1"
  echo
}


log_error()
{
  echo
  echo "Failed - $1"
  echo
}


header()
{
  echo
  print_delim
  echo "$1"
  print_delim
  echo
}


install_package()
{
  if [ -x /usr/bin/zypper ]; then
    /usr/bin/zypper install -y "$@"

  elif [ -x /usr/bin/dnf ]; then
    /usr/bin/dnf install -y "$@"

  elif [ -x /usr/bin/tdnf ]; then
    /usr/bin/tdnf install -y "$@"

  elif [ -x /usr/bin/microdnf ]; then
    /usr/bin/microdnf install -y "$@"

  elif [ -x /usr/bin/yum ]; then
    /usr/bin/yum install -y "$@"

  elif [ -x /usr/bin/apt-get ]; then
    /usr/bin/apt-get install -y "$@"

  elif [ -x /usr/bin/pacman ]; then
    /usr/bin/pacman --noconfirm -Sy "$@"

  elif [ -x /sbin/apk ]; then
    /sbin/apk add "$@"

  else
    log_error "No package manager found!"
    exit 1
  fi
}

install_packages()
{
  local PACKAGE=
  for PACKAGE in $*; do
    install_package $PACKAGE
  done
}

remove_package()
{
  if [ -x /usr/bin/zypper ]; then
    /usr/bin/zypper rm -y "$@"

  elif [ -x /usr/bin/dnf ]; then
    /usr/bin/dnf remove -y "$@"

  elif [ -x /usr/bin/tdnf ]; then
    /usr/bin/tdnf remove -y "$@"

  elif [ -x /usr/bin/microdnf ]; then
    /usr/bin/microdnf remove -y "$@"

  elif [ -x /usr/bin/yum ]; then
    /usr/bin/yum remove -y "$@"

  elif [ -x /usr/bin/apt-get ]; then
    /usr/bin/apt-get remove -y "$@"

  elif [ -x /usr/bin/pacman ]; then
    /usr/bin/pacman --noconfirm -R "$@"

  elif [ -x /sbin/apk ]; then
      /sbin/apk del "$@"
  fi
}


remove_packages()
{
  local PACKAGE=
  for PACKAGE in $*; do
    remove_package $PACKAGE
  done
}


install_if_missing()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ -x  "/usr/bin/$1" ]; then
    echo "already exists: $1"
    return 0
  fi

  if [ -x "/usr/local/bin/$1" ]; then
    return 0
  fi

  if [ -z "$2" ]; then
    install_package "$1"
  else
    install_package "$2"
  fi
}


check_linux_update()
{

  # On Ubuntu and Debian update the cache in any case to be able to install additional packages
  if [ -x /usr/bin/apt-get ]; then
    header "Refreshing packet list via apt-get"
    /usr/bin/apt-get update -y
  fi

  if [ -x /usr/bin/pacman ]; then
    header "Refreshing packet list via pacman"
    pacman --noconfirm -Sy
  fi

  # Install Linux updates if requested
  if [ ! "$LinuxYumUpdate" = "yes" ]; then
    return 0
  fi

  if [ -x /usr/bin/zypper ]; then

    header "Updating Linux via zypper"
    /usr/bin/zypper refresh
    /usr/bin/zypper update -y

  elif [ -x /usr/bin/dnf ]; then

    header "Updating Linux via dnf"
    /usr/bin/dnf update -y

  elif [ -x /usr/bin/tdnf ]; then

    header "Updating Linux via tdnf"
    /usr/bin/tdnf update -y

  elif [ -x /usr/bin/microdnf ]; then

    header "Updating Linux via microdnf"
    /usr/bin/microdnf update -y

  elif [ -x /usr/bin/yum ]; then

    header "Updating Linux via yum"
    /usr/bin/yum update -y

  elif [ -x /usr/bin/apt-get ]; then

    header "Updating Linux via apt"
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

    /usr/bin/apt-get update -y

    # Needed by Astra Linux, Ubuntu and Debian. Should be installed before updating Linux but after updating the repo!
    if [ -x /usr/bin/apt-get ]; then
      install_package apt-utils
    fi

    /usr/bin/apt-get upgrade -y

  elif [ -x /usr/bin/pacman ]; then
    header "Updating Linux via pacman"
    pacman --noconfirm -Syu

  elif [ -x /sbin/apk ]; then
    header "Updating Linux via apk"
    /sbin/apk update

  else
    log_error "No packet manager to update Linux"
  fi
}


remove_directory()
{
  if [ -z "$1" ]; then
    return 1
  fi

  if [ ! -e "$1" ]; then
    return 2
  fi

  rm -rf "$1"

  if [ -e "$1" ]; then
    echo " --- directory not completely deleted! ---"
    ls -l "$1"
    echo " --- directory not completely deleted! ---"
  fi

  return 0
}

get_download_name()
{
  local DOWNLOAD_NAME=""

  if [ -e "$SOFTWARE_FILE" ]; then
    DOWNLOAD_NAME=$(grep "$1|$2|" "$SOFTWARE_FILE" | cut -d"|" -f3)
  else
    log_error "Download file [$SOFTWARE_FILE] not found!"
    exit 1
  fi

  if [ -z "$DOWNLOAD_NAME" ]; then
    log_error "Download for [$1] [$2] not found!"
    exit 1
  fi

  return 0
}


download_file_ifpresent()
{
  local DOWNLOAD_SERVER=$1
  local DOWNLOAD_FILE=$2
  local TARGET_DIR=$3
  local SAVED_DIR=

  if [ -z "$DOWNLOAD_FILE" ]; then
    log_error "No download file specified!"
    exit 1
  fi

  CURL_RET=$($CURL_CMD "$DOWNLOAD_SERVER/$DOWNLOAD_FILE" --silent --head 2>&1)
  STATUS_RET=$(echo $CURL_RET | grep -e 'HTTP/1.1 200 OK' -e 'HTTP/2 200')
  if [ -z "$STATUS_RET" ]; then

    log_ok "Info: Download file does not exist [$DOWNLOAD_FILE]"
    return 0
  fi

  SAVED_DIR=$(pwd)
  if [ -n "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    cd $TARGET_DIR
  fi

  if [ -e "$DOWNLOAD_FILE" ]; then
    log_ok "Replacing existing file [$DOWNLOAD_FILE]"
    rm -f "$DOWNLOAD_FILE"
  fi

  echo
  $CURL_CMD "$DOWNLOAD_SERVER/$DOWNLOAD_FILE" -o "$(basename $DOWNLOAD_FILE)" 2>/dev/null
  echo

  if [ "$?" = "0" ]; then
    log_ok "Successfully downloaded: [$DOWNLOAD_FILE] "
    cd "$SAVED_DIR"
    return 0

  else
    log_error "File [$DOWNLOAD_FILE] not downloaded correctly"
    echo "CURL returned: [$CURL_RET]"
    cd "$SAVED_DIR"
    exit 1
  fi
}


download_and_check_hash()
{
  DOWNLOAD_SERVER=$1
  DOWNLOAD_STR=$2
  TARGET_DIR=$3

  if [ -z "$DOWNLOAD_FILE" ]; then
    log_error "No download file specified!"
    exit 1
  fi

  # check if file exists before downloading

  for CHECK_FILE in $(echo "$DOWNLOAD_STR" | tr "," "\n" ); do

    DOWNLOAD_FILE=$DOWNLOAD_SERVER/$CHECK_FILE
    CURL_RET=$($CURL_CMD "$DOWNLOAD_FILE" --silent --head 2>&1)
    STATUS_RET=$(echo $CURL_RET | grep -e 'HTTP/1.1 200 OK' -e 'HTTP/2 200')

    if [ -n "$STATUS_RET" ]; then
      CURRENT_FILE="$CHECK_FILE"
      FOUND=TRUE
      break
    fi
  done

  if [ ! "$FOUND" = "TRUE" ]; then
    log_error "File [$DOWNLOAD_FILE] does not exist"
    echo "CURL returned: [$CURL_RET]"
    exit 1
  fi

  SAVED_DIR=$(pwd)

  if [ -n "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
  fi

  if [[ "$DOWNLOAD_FILE" =~ ".tar.gz" ]]; then
    TAR_OPTIONS=xz
  elif [[ "$DOWNLOAD_FILE" =~ ".taz" ]]; then
    TAR_OPTIONS=xz
  elif [[ "$DOWNLOAD_FILE" =~ ".tar" ]]; then
    TAR_OPTIONS=x
  else
    TAR_OPTIONS=""
  fi

  if [ -z "$TAR_OPTIONS" ]; then

    # download without extracting for none tar files

    echo
    local DOWNLOADED_FILE=$(basename $DOWNLOAD_FILE)
    $CURL_CMD "$DOWNLOAD_FILE" -o "$DOWNLOADED_FILE"

    if [ ! -e "$DOWNLOADED_FILE" ]; then
      log_error "File [$DOWNLOAD_FILE] not downloaded [1]"
      cd "$SAVED_DIR"
      exit 1
    fi

    HASH=$(sha256sum -b $DOWNLOADED_FILE | cut -f1 -d" ")
    FOUND=$(grep "$HASH" "$SOFTWARE_FILE" | grep "$CURRENT_FILE" | wc -l)

    if [ "$FOUND" = "1" ]; then
      log_ok "Successfully downloaded: [$DOWNLOAD_FILE] "
    else
      log_error "File [$DOWNLOAD_FILE] not downloaded correctly [1]"
    fi

  else
    if [ -e $SOFTWARE_FILE ]; then
      echo
      echo "DOWNLOAD_FILE: [$DOWNLOAD_FILE]"
      HASH=$($CURL_CMD $DOWNLOAD_FILE | tee >(tar $TAR_OPTIONS 2>/dev/null) | sha256sum -b | cut -d" " -f1)
      echo
      FOUND=$(grep "$HASH" "$SOFTWARE_FILE" | grep "$CURRENT_FILE" | wc -l)

      if [ "$FOUND" = "1" ]; then
        log_ok "Successfully downloaded, extracted & checked: [$DOWNLOAD_FILE] "
        cd "$SAVED_DIR"
        return 0

      else
        log_error "File [$DOWNLOAD_FILE] not downloaded correctly [2]"
        cd "$SAVED_DIR"
        exit 1
      fi
    else
      echo
      $CURL_CMD $DOWNLOAD_FILE | tar $TAR_OPTIONS 2>/dev/null
      echo

      if [ "$?" = "0" ]; then
        log_ok "Successfully downloaded & extracted: [$DOWNLOAD_FILE] "
        cd "$SAVED_DIR"
        return 0

      else
        log_error "File [$DOWNLOAD_FILE] not downloaded correctly [3]"
        cd "$SAVED_DIR"
        exit 1
      fi
    fi
  fi

  cd "$SAVED_DIR"
  return 0
}


get_current_version()
{
  if [ -n "$VERSION_FILE_NAME_URL" ]; then

    DOWNLOAD_FILE=$VERSION_FILE_NAME_URL

    CURL_RET=$($CURL_CMD -L "$DOWNLOAD_FILE" --silent --head 2>&1)
    STATUS_RET=$(echo $CURL_RET | grep -e 'HTTP/1.1 200 OK' -e 'HTTP/2 200')
    if [ -n "$STATUS_RET" ]; then
      DOWNLOAD_VERSION_FILE=$DOWNLOAD_FILE
    fi
  fi

  if [ -n "$DOWNLOAD_VERSION_FILE" ]; then
    log_ok "Getting current software version from [$DOWNLOAD_VERSION_FILE]"
    LINE=$($CURL_CMD -L --silent $DOWNLOAD_VERSION_FILE | grep "^$1|")
  else
    if [ ! -r "$VERSION_FILE" ]; then
      log_ok "No current version file found! [$VERSION_FILE]"
    else
      log_ok "Getting current software version from [$VERSION_FILE]"
      LINE=$(grep "^$1|" $VERSION_FILE)
    fi
  fi

  PROD_VER=$(echo $LINE|cut -d'|' -f2)
  PROD_FP=$(echo $LINE|cut -d'|' -f3)
  PROD_HF=$(echo $LINE|cut -d'|' -f4)

  return 0
}


set_security_limits()
{
  header "Set security limits"

  local REQ_NOFILES_SOFT=80000
  local REQ_NOFILES_HARD=80000

  local SET_SOFT=
  local SET_HARD=
  local UPD=FALSE

  NOFILES_SOFT=$(su - $DOMINO_USER -c ulimit' -n')
  NOFILES_HARD=$(su - $DOMINO_USER -c ulimit' -Hn')

  if [ "$NOFILES_SOFT" -ne "$REQ_NOFILES_SOFT" ]; then
    SET_SOFT=$REQ_NOFILES_SOFT
    UPD=TRUE
  fi

  if [ "$NOFILES_HARD" -ne "$REQ_NOFILES_HARD" ]; then
    SET_HARD=$REQ_NOFILES_HARD
    UPD=TRUE
  fi

  if [ "$UPD" = "FALSE" ]; then
    return 0
  fi

  echo >> /etc/security/limits.conf
  echo "# -- Domino configuation begin --" >> /etc/security/limits.conf

  if [ -n "$SET_HARD" ]; then
    echo "$DOMINO_USER  hard    nofile  $SET_HARD" >> /etc/security/limits.conf
  fi

  if [ -n "$SET_SOFT" ]; then
    echo "$DOMINO_USER  soft    nofile  $SET_SOFT" >> /etc/security/limits.conf
  fi

  echo "# -- Domino configuation end --" >> /etc/security/limits.conf
  echo >> /etc/security/limits.conf

}


config_firewall()
{
  if [ -n "$1" ]; then
    STARTSCRIPT_DIR="$1"
  fi

  header "Configure firewall"

  if [ -n "$STARTSCRIPT_SKIP_FIREWALL_CFG" ]; then
    echo "Skip firewall config requested"
    return 0
  fi

  if [ ! -e /usr/sbin/firewalld ]; then
    echo "Firewalld not installed"
    return 0
  fi

  if [ -z "$STARTSCRIPT_DIR" ]; then
    echo "No start script directory found when configuring firewall settings"
    return 0
  fi

  if [ -e "/etc/firewalld/services/nrpc.xml" ]; then
    echo "Firewall settings for NRPC already configured"
    return 0
  fi

  # Add well known NRPC port
  cp "$STARTSCRIPT_DIR/extra/firewalld/nrpc.xml" /etc/firewalld/services/

  # Reload just in case to let firewalld notice the change
  firewall-cmd --reload

  # enable NRPC, HTTP, HTTPS and SMTP in firewall
  firewall-cmd --zone=public --permanent --add-service={nrpc,http,https,smtp}

  # reload firewall changes
  firewall-cmd --reload

  echo "Info: Firewall services enabled - TCP/Inbound: NRPC, HTTP, HTTPS, SMTP"

}


add_notes_user()
{
  header "Add Notes user"

  local NOTES_UID=$(id -u $DOMINO_USER 2>/dev/null)
  if [ -n "$NOTES_UID" ]; then
    echo "$DOMINO_USER user already exists (UID:$NOTES_UID)"
    return 0
  fi

  # creates user and group

  groupadd $DOMINO_GROUP
  useradd $DOMINO_USER -g $DOMINO_GROUP -m
}


glibc_lang_add()
{

  local INSTALL_LOCALE
  local INSTALL_LANG

  if [ -z "$1" ]; then
    INSTALL_LOCALE=$(echo $DOMINO_LANG|cut -f1 -d"_")
    INSTALL_LANG=$DOMINO_LANG

  else
    INSTALL_LOCALE=$(echo $1|cut -f1 -d"_")
    INSTALL_LANG=$1
  fi

  if [ -z "$INSTALL_LOCALE" ]; then
    return 0
  fi

  header "Installing locale [$INSTALL_LOCALE]"

  CHECK_LOCALE_INSTALLED=$(locale -a | grep "^$INSTALL_LOCALE")

 if [ -n "$CHECK_LOCALE_INSTALLED" ]; then
    echo "Locale [$INSTALL_LOCALE] already installed"
    return 0
  fi

  # Ubuntu
  if [ "$LINUX_ID" = "ubuntu" ]; then
    install_package language-pack-$INSTALL_LOCALE
  fi

  # Debian
  if [ "$LINUX_ID" = "debian" ]; then
    # Debian has locales already installed
    return 0
  fi

  #Photon OS
  if [ "$LINUX_ID" = "photon" ]; then

    install_package glibc-i18n
    echo "$INSTALL_LANG UTF-8" >> /etc/locale-gen.conf
    locale-gen.sh
    #yum remove -y glibc-i18n

    return 0
  fi

  # Only needed for centos like platforms -> check if yum is installed

  if [ ! -x /usr/bin/yum ]; then
    return 0
  fi

  yum install -y glibc-langpack-$INSTALL_LOCALE

  return 0
}


install_software()
{
  # adds epel repository for additional software packages on RHEL/CentOS/Fedora platforms

  header "Installing required Linux packages"

  case "$LINUX_ID_LIKE" in

    *fedora*|*rhel*)
      install_package epel-release
    ;;

  esac

  # epel on Oracle Linux has a different name

  case "$LINUX_PRETTY_NAME" in

    Oracle*)
      local MAJOR_VER=$(echo $LINUX_PLATFORM_ID | cut -d ":" -f2)
      install_package oracle-epel-release-$MAJOR_VER
    ;;

  esac

  # install required and useful packages
  install_packages hostname tar sysstat net-tools jq gettext cpio

  # SUSE does not have gdb-minimal
  if [ -x /usr/bin/zypper ]; then
    install_package gdb
  else
    install_package gdb-minimal
    if [ ! -e /usr/bin/gdb ]; then
      ln -s /usr/bin/gdb.minimal /usr/bin/gdb
    fi
  fi

  # additional packages by platform

  if [ "$LINUX_ID" = "photon" ]; then
    # Photon OS packages
    install_package bindutils

  elif [ -x /usr/bin/apt-get ]; then
    # Ubuntu needs different packages and doesn't provide some others
    install_package bind9-utils

  else

    # RHEL/CentOS/Fedora
    case "$LINUX_ID_LIKE" in
      *fedora*|*rhel*)
        install_packages procps-ng which bind-utils
      ;;
    esac
  fi

  # first check if platform supports perl-libs
  if [ ! -x /usr/bin/perl ]; then
    install_package perl-libs
  fi

  # if not found install full perl package
  if [ ! -x /usr/bin/perl ]; then
    install_package perl
  fi
}


create_directory()
{
  TARGET_FILE=$1
  OWNER=$2
  GROUP=$3
  PERMS=$4

  if [ -z "$TARGET_FILE" ]; then
    return 0
  fi

  if [ -e "$TARGET_FILE" ]; then
    return 0
  fi

  mkdir -p "$TARGET_FILE"

  if [ ! -z "$OWNER" ]; then
    chown $OWNER:$GROUP "$TARGET_FILE"
  fi

  if [ ! -z "$PERMS" ]; then
    chmod "$PERMS" "$TARGET_FILE"
  fi

  return 0
}


create_directories()
{
  header "Create directory structure /local ..."

  # creates local directory structure with the right owner

  create_directory /local           $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/notesdata $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/translog  $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/daos      $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/nif       $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/ft        $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/backup    $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory "$SOFTWARE_DIR"  $DOMINO_USER $DOMINO_GROUP $DIR_PERM
}



get_notes_ini_var()
{
  # $1 = filename
  # $2 = ini.variable

  ret_ini_var=""
  if [ -z "$1" ]; then
    return 0
  fi

  if [ -z "$2" ]; then
    return 0
  fi

  ret_ini_var=$(awk -F '=' -v SEARCH_STR="$2" '{if (tolower($1) == tolower(SEARCH_STR)) print $2}' $1 | xargs)
  return 0
}


set_notes_ini_var()
{
  # updates or sets notes.ini parameter
  local FILE=$1
  local VAR=$2
  local NEW=$3
  local LINE_FOUND=
  local LINE_NEW="$VAR=$NEW"

  LINE_FOUND=$(grep -i "^$VAR=" $FILE)

  if [ -z "$LINE_FOUND" ]; then
    echo "$LINE_NEW"  >> $FILE
    return 0
  fi

  sed -i "s~${LINE_FOUND}~${LINE_NEW}~g" "$FILE"

  return 0
}


setup_notes_ini()
{
  # Avoid Domino Directory Design Update Prompt
  set_notes_ini_var $DOMINO_DATA_PATH/notes.ini "SERVER_UPGRADE_NO_DIRECTORY_UPGRADE_PROMPT" "1"

  # Allow server names with dots and undercores
  set_notes_ini_var $DOMINO_DATA_PATH/notes.ini "ADMIN_IGNORE_NEW_SERVERNAMING_CONVENTION" "1"
}


print_runtime()
{
  echo

  hours=$((SECONDS / 3600))
  seconds=$((SECONDS % 3600))
  minutes=$((seconds / 60))
  seconds=$((seconds % 60))
  h=""; m=""; s=""
  if [ ! $hours =  "1" ] ; then h="s"; fi
  if [ ! $minutes =  "1" ] ; then m="s"; fi
  if [ ! $seconds =  "1" ] ; then s="s"; fi

  if [ ! $hours =  0 ] ; then echo "Completed in $hours hour$h, $minutes minute$m and $seconds second$s"
  elif [ ! $minutes = 0 ] ; then echo "Completed in $minutes minute$m and $seconds second$s"
  else echo "Completed in $seconds second$s"; fi
}

must_be_root()
{
  if [ "$EUID" = "0" ]; then
    return 0
  fi

  log_error "Installation requires root permissions. Switch to root or try 'sudo'"
  exit 1
}


find_scripts()
{
  local SEARCH_DIR=$1
  if [ -z "$SEARCH_DIR" ]; then
    SEARCH_DIR=$(pwd)
  fi

  if [ -z "$INSTALL_DOMDOWNLOAD_SCRIPT" ]; then
    INSTALL_DOMDOWNLOAD_SCRIPT=$(find "$SEARCH_DIR" -maxdepth 2 -name "domdownload.sh")
  fi

  if [ -n "$INSTALL_DOMDOWNLOAD_SCRIPT" ]; then
    START_SCRIPT_DIR="$(dirname "$INSTALL_DOMDOWNLOAD_SCRIPT")"
  fi

  if [ -n "$START_SCRIPT_DIR" ]; then
    INSTALL_DOMINO_SCRIPT="$START_SCRIPT_DIR/install_script"

    # Search for container porject on same level
    SEARCH_DIR=$(dirname "$START_SCRIPT_DIR")
  fi

  if [ -z "$CONTAINER_SCRIPT_DIR" ]; then
    CONTAINER_SCRIPT_DIR=$(find "$SEARCH_DIR" -type d -name "domino-container*")
  fi

  if [ -n "$CONTAINER_SCRIPT_DIR" ]; then
    BUILD_SCRIPT="$CONTAINER_SCRIPT_DIR/build.sh"
  fi
}

# -- Main logic --

SAVED_DIR=$(pwd)

LINUX_VERSION=$(cat /etc/os-release | grep "VERSION_ID="| cut -d= -f2 | xargs)
LINUX_PRETTY_NAME=$(cat /etc/os-release | grep "PRETTY_NAME="| cut -d= -f2 | xargs)
LINUX_ID=$(cat /etc/os-release | grep "^ID="| cut -d= -f2 | xargs)
LINUX_ID_LIKE=$(cat /etc/os-release | grep "^ID_LIKE="| cut -d= -f2 | xargs)
LINUX_PLATFORM_ID=$(cat /etc/os-release | grep "^PLATFORM_ID="| cut -d= -f2 | xargs)

if [ -z "$LINUX_PRETTY_NAME" ]; then
  echo "Unsupported platform!"
  exit 1
fi

LINUX_VM_INFO=
if [ -n "$(uname -r|grep microsoft)" ]; then
  LINUX_VM_INFO="on WSL"
fi

header "Nash!Com Domino Installer for $LINUX_PRETTY_NAME $LINUX_VM_INFO"

must_be_root
#check_linux_update
install_software
add_notes_user
create_directories
glibc_lang_add

# Set posix locale for installing Domino to ensure the right res/C link
export LANG=C


if [ -z "SOFTWARE_DIR" ]; then
  export SOFTWARE_DIR=/local/software
fi

mkdir -p "$INSTALL_TEMP_DIR"
cd "$INSTALL_TEMP_DIR"

header "Download Domino Start Script Project"

# Check if projects exist already and determine scripts
find_scripts "$SCRIPT_DIR"

if [ -z "$START_SCRIPT_DIR" ]; then
  if [ -e "$SOFTWARE_DIR/domino-startscript.zip" ]; then
    unzip -q "$SOFTWARE_DIR/domino-startscript.zip"

  else
    curl -L "$DOMINO_START_SCRIPT_GIT_ZIP" -o domino-startscript.zip
    unzip -q domino-startscript.zip
  fi

else
  echo "Using existing Start Script directory: $START_SCRIPT_DIR"
fi

if [ -z "$CONTAINER_SCRIPT_DIR" ]; then
  header "Download Domino Container Project"

  if [ -e "$SOFTWARE_DIR/domino-container.zip" ]; then
    unzip -q "$SOFTWARE_DIR/domino-container.zip"

  else
    curl -L "$DOMINO_CONTAINER_GIT_ZIP" -o domino-container.zip
    unzip -q domino-container.zip
  fi

else
  echo "Using existing Container Domino project: $CONTAINER_SCRIPT_DIR"
fi

# Check again after extract
find_scripts

if [ -z "$INSTALL_DOMDOWNLOAD_SCRIPT" ]; then
  echo "Domino Download Script not found"
  exit 1
fi

if [ -z "$START_SCRIPT_DIR" ]; then
  echo "Domino Start Script dir not found"
  exit 1
fi

if [ -z "$INSTALL_DOMINO_SCRIPT" ]; then
  echo "Domino Start Script installer not found"
  exit 1
fi

if [ -z "$BUILD_SCRIPT" ]; then
  echo "Build script not found"
  exit 1
fi

if [ -z "$CONTAINER_SCRIPT_DIR" ]; then
  echo "Domino Container script dir not found"
  exit 1
fi

cp -f "$CONTAINER_SCRIPT_DIR/software/software.txt" "$SOFTWARE_DIR"
cp -f "$CONTAINER_SCRIPT_DIR/software/current_version.txt" "$SOFTWARE_DIR"

# Install Domino Download Script
"$INSTALL_DOMDOWNLOAD_SCRIPT" -connect install

header "Installing Domino"

if [ -z "$INSTALL_OPTIONS" ]; then

  echo "Install native via menu"
  "$BUILD_SCRIPT" menu -installnative

else
  echo "Install native silent"
  "$BUILD_SCRIPT" domino $INSTALL_OPTIONS -installnative
fi

header "Installing Domino Start Script"
"$INSTALL_DOMINO_SCRIPT"

setup_notes_ini
set_security_limits

cd $SAVED_DIR

# Cleanup
remove_directory "$INSTALL_TEMP_DIR"
# remove_directory "$SOFTWARE_DIR"

echo
echo "Done"
print_runtime
echo

