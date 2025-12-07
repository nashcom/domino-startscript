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


git_update_repo()
{

  local REPO_DIR="$1"
  local CURRENT_UID="$(id -u)"
  local OWNER_UID=

  if [ -z "$REPO_DIR" ]; then
    return 0
  fi

  if [ ! -e "$REPO_DIR" ]; then
    return 0
  fi

  OWNER_UID="$(stat -c %u "$REPO_DIR")"
  cd "$REPO_DIR"

  if [ "$OWNER_UID" = "$CURRENT_UID" ]; then
    git pull

  elif [ "$OWNER_UID" = "0" ]; then
    SUDO git pull

  else
    log_error "Please pull repository with the correct owner: $REPO_DIR"
    sleep 5
    return 1
  fi

  local rc=$?

  if [ $rc -ne 0 ]; then
    log_error "Git repo update failed:  $REPO_DIR"
    sleep 5
  fi

  log_ok "Git repo pulled:  $REPO_DIR"
}


update_github_repos()
{
  local REPO_DIR=
  header "Updating GitHub projects"

  git_update_repo /local/github/domino-container
  git_update_repo /local/github/domino-startscript
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

    ./install_script --check-version

    if [ "$?" = "0" ]; then
      log_ok "Latest Domino Start Script already installed"
    else
      SUDO ./install_script
    fi
  fi

  if [ -n "$(which dominoctl 2>/dev/null)" ]; then

    header "Updating Domino Container Control (dominoctl)"

    ./install_dominoctl --check-version

    if [ "$?" = "0" ]; then
      log_ok "Latest Domino Container Control (dominoctl) already installed"
    else
      SUDO ./install_dominoctl
    fi
  fi

  if [ -n "$(which domdownload 2>/dev/null)" ]; then

    header "Updating Domino Download Script (domdownload) installed"

    ./domdownload.sh --check-version

    if [ "$?" = "0" ]; then
      log_ok "Latest Domino Download Script (domdownload) already installed"
    else
      SUDO ./domdownload.sh install
    fi
  fi
}


process_updates()
{
  local ONLY_UPDATE_REPOS=

  for a in "$@"; do
    p=$(echo "$a" | awk '{print tolower($0)}')

    case "$p" in
      repo)
        ONLY_UPDATE_REPOS=1
        ;;
      *)
        log_error "Invalid parameter [$a]"
        sleep 5
	return 1
        ;;
    esac
  done

  update_github_repos

  if [ "$ONLY_UPDATE_REPOS" = "1" ]; then
    return 0
  fi

  update_components

}


# --- Main logic ---

SAVED_DIR=$(pwd)

process_updates

cd $SAVED_DIR


