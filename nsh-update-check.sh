#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2025 - APACHE 2.0 see LICENSE
############################################################################

# Domino on Linux project update script
# Version 4.0.9 06.12.2025

SCRIPT_NAME=$(readlink -f $0)
SCRIPT_DIR=$(dirname $SCRIPT_NAME)


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
  echo "$1"
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


update_github_repos()
{
  local REPO_DIR=
  header "Updating GitHub projects"

  REPO_DIR=/local/github/domino-container

  if [ -e "$REPO_DIR" ]; then

    if [ "$(stat -c %u "$REPO_DIR")" -eq "$(id -u)" ]; then
      cd "$REPO_DIR"
      git pull
    else
      log_error "Please pull repository with the correct owner: $$REPO_DIR"
    fi
  fi
  echo

  REPO_DIR=/local/github/domino-startscript

  if [ -e "$REPO_DIR" ]; then

    if [ "$(stat -c %u "$REPO_DIR")" -eq "$(id -u)" ]; then
      cd "$REPO_DIR"
      git pull
    else
      log_error "Please pull repository with the correct owner: $$REPO_DIR"
    fi
  fi
  echo
}



# Check if sudo is requested or fall back in case of error
SUDO()
{
  local RET=

  if [ "$EUID" = 0 ]; then
    "$@"
    return 0
  fi

  if [ -z "$DOMINO_NO_SUDO" ]; then
    sudo "$@"
    RET="$?"

    if [ "$RET" = "0" ]; then
      return 0
    fi

    if [ "$RET" = "9" ]; then
      return 0
    fi

    echo
    echo "Info: export DOMINO_NO_SUDO=1 or enable sudo $DOMINO_USER for systemctl"
    echo
  fi

  "$@"
}



update_components()
{
  
  if [ ! -e /local/github/domino-startscript ]; then
    log_error "Start Script GitHub repository not found"
    return 0
  fi

  cd /local/github/domino-startscript

  if [ -n "$(which domino 2>/dev/null)" ]; then
    header "Updating Domino Start Script"
    SUDO ./install_script
    echo
  fi

  if [ -n "$(which dominoctl 2>/dev/null)" ]; then
    header "Updating Domino Container Control (dominoctl)"
    SUDO ./install_dominoctl
    echo
  fi

  if [ -n "$(which domdownload 2>/dev/null)" ]; then
    header "Updating Domino Download Script (domdownload)"
    SUDO ./domdownload.sh install
    echo
  fi
}


# --- Main logic ---

SAVED_DIR=$(pwd)

update_github_repos
update_components

cd $SAVED_DIR

