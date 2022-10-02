#!/bin/bash

###########################################################################
# Nash!Com Domino Container Addon Install Script                          #
# Version 1.0.1 18.09.2022                                                #
#                                                                         #
# (C) Copyright Daniel Nashed/NashCom 2019                                #
# Feedback domino_unix@nashcom.de                                         #
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


# Include helper functions & defines -- already present in container image
. /domino-container/scripts/script_lib.sh

INSTALL_DIR=/tmp/install_dir

install_bin_file ()
{

  if [ ! -e "$1" ]; then
    return 0
  fi

  case "$1" in
    *.txt|*.md)
      return 0 
      ;;
  esac

  install_binary "$1"
}


install_all_binaries ()
{
  if [ ! -e "$1" ]; then
    return 0
  fi

  local all_files=$(find "$1" -type f -printf "%p\n")
  local current_file=

  for current_file in $all_files; do
    install_bin_file "$current_file"
  done

  return 0
}


install_res_file ()
{

  if [ ! -e "$1" ]; then
    return 0
  fi

  case "$1" in
    *.txt|*.md)
      return 0
      ;;
  esac

  local target_file=$(basename $1)
  local target_full="$Notes_ExecDirectory/res/C/$target_file"

  echo "Installing '$target_full'"
  cp -f "$1" "$target_full"
  chmod 755 "$target_full"
}

install_res_files ()
{

  if [ ! -e "$1" ]; then
    return 0
  fi

 local all_files=$(find "$1" -type f -printf "%p\n")
  local current_file=

  for current_file in $all_files; do
    install_res_file "$current_file"
  done

  return 0
}

check_linux_update

header "Installing Domino related Files"

# Install servertasks
install_all_binaries "$INSTALL_DIR/servertasks"

# Install extension managers
install_all_binaries "$INSTALL_DIR/extmgr"

# Install res files
install_res_files "$INSTALL_DIR/res"


# Install health check script
if [ -e "$INSTALL_DIR/domino_docker_healthcheck.sh" ]; then
  install_file "$INSTALL_DIR/domino_docker_healthcheck.sh" "/domino_docker_healthcheck.sh" root root 755
fi

# Copy pre-start configuration
if [ -e "$INSTALL_DIR/docker_prestart.sh" ]; then
  install_file "$INSTALL_DIR/docker_prestart.sh" "$DOMDOCK_SCRIPT_DIR/docker_prestart.sh" root root 755
fi

# Copy install data copy
if [ -e "$INSTALL_DIR/domino_install_data_copy.sh" ]; then
  install_file "$INSTALL_DIR/domino_install_data_copy.sh" "$DOMDOCK_SCRIPT_DIR/domino_install_data_copy.sh" root root 755
fi

header "Successfully completed installation!"

exit 0

