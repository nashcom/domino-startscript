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
  header "Updating GitHub projects"

  if [ -e /local/github/domino-container ]; then
    cd /local/github/domino-container
    git pull
  fi

  if [ -e /local/github/domino-startscript ]; then
    cd /local/github/domino-startscript
    git pull
  fi

  echo
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
    ./install_script
    echo
  fi

  if [ -n "$(which dominoctl 2>/dev/null)" ]; then
    header "Updating Domino Container Control (dominoctl)"
    ./install_dominoctl
    echo
  fi

  if [ -n "$(which domdownload 2>/dev/null)" ]; then
	  header "Updating Domino Download Script (domdownload)"
    ./domdownload.sh install
    echo
  fi
}


# --- Main logic ---

SAVED_DIR=$(pwd)

update_github_repos
update_components

cd $SAVED_DIR

