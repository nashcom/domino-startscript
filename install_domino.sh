#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2025 - APACHE 2.0 see LICENSE
############################################################################

# Domino on Linux installation script
# Version 4.0.9 06.12.2025

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

if [ -z "$DOMINO_START_SCRIPT_GIT_REPO" ]; then
  DOMINO_START_SCRIPT_GIT_REPO=https://github.com/nashcom/domino-startscript.git
fi

if [ -z "$DOMINO_CONTAINER_GIT_REPO" ]; then
  DOMINO_CONTAINER_GIT_REPO=https://github.com/HCL-TECH-SOFTWARE/domino-container.git
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

  echo "$@" >> /tmp/remove_package.log
}


remove_packages()
{
  local PACKAGE=
  for PACKAGE in $*; do
    remove_package $PACKAGE
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
  create_directory /local/github    $DOMINO_USER $DOMINO_GROUP 777
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


enable_chrony_service()
{
    local unit=
    local names=

    # Try querying chronyd.service first
    names=$(systemctl show -p Names chronyd.service 2>/dev/null | cut -d= -f2)

    if [ -z "$names" ]; then
        # Try chrony.service if chronyd did not exist
        names=$(systemctl show -p Names chrony.service 2>/dev/null | cut -d= -f2)
    fi

    if [ -z "$names" ]
    then
      echo "ERROR: chrony service not found" >&2
      return 1
    fi

    # systemd returns canonical name first
    unit=$(echo "$names" | awk '{print $1}')

    if [ -z "$unit" ]; then
      echo "ERROR: Could not determine real chrony systemd unit" >&2
      return 1
    else
      echo "Info: NTP service $unit enabled. Ensure it can connect a configured NTP server"
    fi

    systemctl enable --now "$unit"
}


install_chrony()
{
  header "Install NTP client: chrony"

  install_package chrony
  enable_chrony_service
}


cleanup_git()
{
  # Additional option to remove temporary installed GitHub repositories and Git

  if [ "$DOMINO_INSTALL_CLEANUP_GIT" != "yes" ]; then
    return 0
  fi

  rm -rf "/local/github/domino-startscript"
  rm -rf "/local/github/domino-container"

  # Remove directory if empty
  rmdir "/local/github"

  # Remove git
  remove_package git
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


header "Installing required software"

install_packages unzip ncurses jq procps openssl git

# Install sudo if not present. It's required for systemd
if [ ! -e /usr/bin/sudo ]; then
  install_package sudo
fi

if [ -z "$LinuxYumUpdate" ]; then
  export LinuxYumUpdate=yes
fi


header "Git clone Domino Start Script Project & HCL Domino Container Project"

cd /local/github
git clone "$DOMINO_START_SCRIPT_GIT_REPO"
git clone "$DOMINO_CONTAINER_GIT_REPO"

cd /local/github/domino_container
git pull

cd /local/github/domino_startscript
git pull


header "Install Domino Download Script"

INSTALL_DOMDOWNLOAD_SCRIPT="/local/github/domino-startscript/domdownload.sh"

"$INSTALL_DOMDOWNLOAD_SCRIPT" -connect install

if [ -n "$DOMDOWNLOAD_TOKEN" ]; then
  "$INSTALL_DOMDOWNLOAD_SCRIPT" -token "$DOMDOWNLOAD_TOKEN"
fi


header "Installing Domino"

cd /local/github/domino-container

if [ -z "$INSTALL_OPTIONS" ]; then

  echo "Install native via menu"
  ./build.sh menu -installnative

else
  echo "Install native silent"
  ./build.sh domino $INSTALL_OPTIONS -installnative
fi


header "Installing Domino Start Script"
cd /local/github/domino-startscript
./install_script

config_sudo
install_chrony
cleanup_git

cd $SAVED_DIR

echo
echo "Done"
print_runtime
echo


