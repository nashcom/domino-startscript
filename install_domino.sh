#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2025 - APACHE 2.0 see LICENSE
############################################################################

# Domino on Linux installation script
# Version 4.0.3 30.04.2025 

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

config_sudo()
{

  if [ -n "$(cat /etc/sudoers | grep "notes" |grep "/usr/bin/systemctl")" ]; then
    echo "sudo for 'notes' to execute systemctl is already configured"
    return 0
  fi

  echo "%notes ALL= NOPASSWD: /usr/bin/systemctl *" >> /etc/sudoers
  echo "sudo for 'notes' to execute systemctl configured"

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

  create_directory /local           $DOMINO_USER $DOMINO_GROUP 777
  create_directory "$SOFTWARE_DIR"  $DOMINO_USER $DOMINO_GROUP 777
  create_directory /local/notesdata $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/translog  $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/daos      $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/nif       $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/ft        $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/backup    $DOMINO_USER $DOMINO_GROUP $DIR_PERM
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
add_notes_user
create_directories

# Set posix locale for installing Domino to ensure the right res/C link
export LANG=C


if [ -z "SOFTWARE_DIR" ]; then
  export SOFTWARE_DIR=/local/software
fi

mkdir -p "$INSTALL_TEMP_DIR"
cd "$INSTALL_TEMP_DIR"


header "Installing required software"

install_packages unzip ncurses jq procps openssl

# Install sudo if not present. It's required for systemd
if [ ! -e /usr/bin/sudo ]; then
  install_package sudo
fi


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

if [ -z "$LinuxYumUpdate" ]; then
  export LinuxYumUpdate=yes
fi


cp -f "$CONTAINER_SCRIPT_DIR/software/software.txt" "$SOFTWARE_DIR"
cp -f "$CONTAINER_SCRIPT_DIR/software/current_version.txt" "$SOFTWARE_DIR"

# Install Domino Download Script
"$INSTALL_DOMDOWNLOAD_SCRIPT" -connect install

if [ -n "$DOMDOWNLOAD_TOKEN" ]; then
  "$INSTALL_DOMDOWNLOAD_SCRIPT" -token "$DOMDOWNLOAD_TOKEN"
fi

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

config_sudo

cd $SAVED_DIR

# Cleanup
remove_directory "$INSTALL_TEMP_DIR"
# remove_directory "$SOFTWARE_DIR"

echo
echo "Done"
print_runtime
echo

