#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2022-2024 - APACHE 2.0 see LICENSE
############################################################################

# Container environment installation script
# Version 1.0.3 22.09.2024

# - Installs required software
# - Adds notes:notes user and group
# - Creates directory structure in /local/ for the Domino server data (/local/notesdata, /local/translog, ...)
# - Clones HCL Domino container project and Domino start script project
# - Installs NashCom Domino container script (dominoctl)
# - Sets security limits
# - Configure NRPC, HTTP and HTTPS if firewalld is configured

SCRIPT_NAME=$0
PARAM1=$1
START_SCRIPT_DIR=$(dirname $0)

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


print_delim ()
{
  echo "--------------------------------------------------------------------------------"
}

log_ok ()
{
  echo
  echo "$1"
  echo
}

log_error ()
{
  echo
  echo "Failed - $1"
  echo
}

header ()
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
   zypper rm -y "$@"

 elif [ -x /usr/bin/dnf ]; then
   dnf remove -y "$@"

 elif [ -x /usr/bin/yum ]; then
   yum remove -y "$@"

 elif [ -x /usr/bin/apt-get ]; then
   apt-get remove -y "$@"

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

linux_update()
{
  if [ -x /usr/bin/zypper ]; then

    header "Updating Linux via zypper"
    zypper refresh
    zypper update -y

  elif [ -x /usr/bin/dnf ]; then

    header "Updating Linux via dnf"
    dnf update -y

  elif [ -x /usr/bin/yum ]; then

    header "Updating Linux via yum"
    yum update -y

  elif [ -x /usr/bin/apt-get ]; then

    header "Updating Linux via apt-get"
    apt-get update -y

    # Needed by Astra Linux, Ubuntu and Debian. Should be installed before updating Linux but after updating the repo!
    if [ -x /usr/bin/apt-get ]; then
      install_package apt-utils
    fi

    apt-get upgrade -y

  elif [ -x /sbin/apk ]; then
    header "Updating Linux via apk"
    apk update
    apk upgrade

  fi
}

remove_directory ()
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
  header "Configure firewall"

  if [ ! -e /usr/sbin/firewalld ]; then
    echo "Firewalld not installed"
    return 0
  fi

  # Add well known NRPC port
  cp "/local/github/domino-startscript/extra/firewalld/nrpc.xml" /etc/firewalld/services/

  # Reload just in case to let firewalld notice the change
  firewall-cmd --reload

  # enable NRPC, HTTP, HTTPS and SMTP in firewall
  firewall-cmd --zone=public --permanent --add-service={nrpc,http,https}

  # reload firewall changes
  firewall-cmd --reload
}

add_notes_user()
{

  local NAME1000=$(id -nu 1000 2>/dev/null)
  local GROUP1000=$(id -ng 1000 2>/dev/null)

  if [ -n "$NAME1000" ]; then
    header "Existing user detected"
    echo User : $NAME1000
    echo Group: $GROUP1000
    echo

    export DOMINO_USER=$NAME1000
    export DOMINO_GROUP=$GROUP1000

    return 0
  fi

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
  install_packages tar sysstat net-tools jq gettext git ncurses unzip

  # additional packages by platform

  if [ "$LINUX_ID" = "photon" ]; then
    # Photon OS packages
    install_package bindutils

  elif [ -x /usr/bin/apt-get ]; then
    # Ubuntu needs different packages and doesn't provide some others
    install_package bind9-utils

  elif [ -x /sbin/apk ]; then
    install_packages bash outils-sha256 curl gettext gawk openssl shadow procps

  else

    # RHEL/CentOS/Fedora
    case "$LINUX_ID_LIKE" in
      *fedora*|*rhel*)
        install_packages procps-ng which bind-utils
      ;;
    esac
  fi

}

create_directory ()
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

  create_directory /local $DOMINO_USER $DOMINO_GROUP 777
  create_directory /local/software $DOMINO_USER $DOMINO_GROUP 777
  create_directory /local/notesdata $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/translog $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/daos $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/nif $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/ft $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/backup $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory /local/github $DOMINO_USER $DOMINO_GROUP $DIR_PERM
}

install()
{
  header "Cloning/updating repositories"

  cd /local/github

  if [ -e /local/github/domino-container ]; then
    cd /local/github/domino-container
    git pull
  else
    git clone https://github.com/HCL-TECH-SOFTWARE/domino-container.git
    git checkout develop
  fi

  if [ -e /local/github/domino-startscript ]; then
    cd /local/github/domino-startscript
    git pull
  else
    git clone https://github.com/nashcom/domino-startscript.git
    git checkout develop
  fi

  local CONFIG_DIR=~/.DominoContainer
  local CONFIG_FILE=$CONFIG_DIR/build.cfg

  mkdir -p "$CONFIG_DIR"
  cp  /local/github/domino-container/build.cfg "$CONFIG_FILE"
  sed -i 's%# SOFTWARE_DIR=/local/software%SOFTWARE_DIR=/local/software%' "$CONFIG_FILE"


  header "Installing/updating Domino Container Control (dominoctl)"

  cd /local/github/domino-startscript
  ./install_dominoctl

  header "Installing/updating Domino Download (domdownload.sh)"

  ./domdownload.sh -connect install
}

detect_container_env()
{
  if [ -x /usr/bin/podman ] || [ -x /usr/local/bin/podman ]; then
    CONTAINER_CMD=podman
    return 0
  fi

  if [ -x /usr/bin/nerdctl ] || [ -x /usr/local/bin/nerdctl ]; then
    CONTAINER_CMD=nerdctl
    return 0
  fi

  if [ -x /usr/bin/docker ] || [ -x /usr/local/bin/docker ]; then
    CONTAINER_CMD=docker
    return 0
  fi
}

install_container_env()
{
  header "Installing container environment"

  if [ -n "$CNT" ]; then
    install_package "$CNT"
  else
    if [ -x /usr/bin/apt-get ]; then
 
      # On Ubuntu the standard Docker package is too old
      install_package curl
      curl -fsSL https://get.docker.com | bash -

      # install_packages docker.io docker-buildx docker-compose-v2

    elif [ -x /sbin/apk ]; then

      # Alpine Linux Docker install
      install_package docker

      header "Enabling and starting Docker"

      if [ -x /sbin/openrc ]; then
        header "Enabling and starting Docker"
        openrc default
        rc-service docker start

        rc-update add docker default
        openrc default
      fi

      return 0

    else
      # Assume Redhat/CentOS compatible environments

      install_package yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    fi

  fi

  systemctl enable --now docker
}

print_runtime()
{
  echo

  # the following line does not work on OSX
  # echo "Completed in" $(date -d@$SECONDS -u +%T)

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

  if [ "$(id -u)" = "0" ]; then
    return 0
  fi

  log_error "Installation requires root permissions. Switch to root or try 'sudo'"
  exit 1
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

header "Nash!Com Container Environment Installer for $LINUX_PRETTY_NAME $LINUX_VM_INFO"

must_be_root
linux_update
install_software
add_notes_user
create_directories

install
set_security_limits
config_firewall

detect_container_env

if [ -z "$CONTAINER_CMD" ]; then
  install_container_env
else
  log_ok "Container environment [$CONTAINER_CMD] already installed"
fi

cd $SAVED_DIR

cd /local/github/domino-container

print_runtime
echo

if [ ! -e ~/.DominoDownload/download.token ]; then
  header "Configure Domino Download Token"

  # Script needs to be invoked interactive to be able to read token
  bash -i domdownload -token
fi

header "Container environment setup completed"

echo
echo "Switch to cloned GitHub container project directory and start the container build script"
echo
echo "cd /local/github/domino-container"
echo "./build.sh"
echo

exit 0

