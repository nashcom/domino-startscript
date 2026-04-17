#!/bin/bash
############################################################################
# Proxmox LXC Container Management Script
# Copyright Nash!Com, Daniel Nashed 2026  - APACHE 2.0 see LICENSE
############################################################################

VERSION="0.9.3"


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


log()
{
  echo
  echo "$1"
  echo
}

get_config()
{
  if [ -z "$VMID" ]; then
    return 0
  fi

  PCT_LXC_CFG_FILE="/etc/pve/lxc/${VMID}.conf"
  PCT_CFG_HOSTNAME=""
  PCT_CFG_TAGS=""

  if [ ! -f "$PCT_LXC_CFG_FILE" ]; then
    return 0
  fi

  while IFS= read -r line
  do
    case "$line" in
      hostname:*)
        PCT_CFG_HOSTNAME="${line#hostname: }"
        ;;
      tags:*)
        PCT_CFG_TAGS="${line#tags: }"
        PCT_CFG_TAGS="${PCT_CFG_TAGS//;/|}"
        ;;
    esac
  done < "$PCT_LXC_CFG_FILE"
}


get_pct_status()
{
  LXC_STATUS=$(pct status $VMID 2>/dev/null | awk '{print $2}')

  get_config

  if [ "$LXC_STATUS" != "running" ]; then
    return 0
  fi
}


log_error()
{
  log "ERROR: $1"
}


 log_error_exit()
{
  log "ERROR: $1"
  exit 1
}

print_server_config()
{
  header "Configuration"

  format_size()   { local size="$1"; if [ "$size" -ge 1024 ]; then awk "BEGIN { printf \"%6.1f TB\", $size/1024 }"; else printf "%4d GB" "$size"; fi; }
  print_cfg()     { printf "%-20s %-16s :  %s\n" "$1" "$2" "$3"; }
  print_size()    { printf "%-20s %-16s :  %s\n" "$1" "$2" "$(format_size "$3")"; }
  print_size_mb() { printf "%-20s %-16s :  %4d MB\n" "$1" "$2" "$3"; }
  print_size_kb() { printf "%-20s %-16s :  %4d KB\n" "$1" "$2" "$3"; }

  print_cfg "PCT_DATA_POOL" "Data pool" "$PCT_DATA_POOL"
  print_cfg "PCT_NET0" "Network config" "$PCT_NET0"
  print_cfg "PCT_TEMPLATE_ID" "Template LXC ID" "$PCT_TEMPLATE_ID"
  print_cfg "PCT_CPU" "CPU/Cores" "$PCT_CPU"

  echo

  print_size_kb "PCT_RECORD_SIZE" "ZFS recordsize" "$PCT_RECORD_SIZE"
  print_size "PCT_RAM_GB" "RAM Size" "$PCT_RAM_GB"
  print_size "PCT_SWAP_GB" "Swap Size" "$PCT_SWAP_GB"
  print_size "PCT_DISK_SIZE_GB" "Data disk size" "$PCT_DISK_SIZE_GB"
  [ -n "$PCT_NSF_SIZE_GB" ] && print_size "PCT_NSF_SIZE_GB" "NSF size" "$PCT_NSF_SIZE_GB"
  [ -n "$PCT_TRANSLOG_SIZE_GB" ] && print_size "PCT_TRANSLOG_SIZE_GB" "Translog size" "$PCT_TRANSLOG_SIZE_GB"
  [ -n "$PCT_DAOS_SIZE_GB" ] && print_size "PCT_DAOS_SIZE_GB" "DAOS size" "$PCT_DAOS_SIZE_GB"
  [ -n "$PCT_BACKUP_SIZE_GB" ] && print_size "PCT_BACKUP_SIZE_GB" "Backup size" "$PCT_BACKUP_SIZE_GB"
  echo
}

pct_create()
{
  header "Creating LXC $VMID"

  if [ -n "$LXC_STATUS" ]; then
    log_error "Container already exists: $LXC_STATUS"
    return 0
  fi

  if ! command -v zfs >/dev/null 2>&1; then
    log_error_exit "No ZFS found"
  fi

  if ! zfs list -H "$PCT_DATA_POOL" >/dev/null 2>&1; then
    log_error_exit "ZFS dataset not found: $PCT_DATA_POOL"
  fi

  if [ -n "$PCT_TRANSLOG_SIZE_GB" ] && [ "$PCT_TRANSLOG_POOL" != "$PCT_DATA_POOL" ]; then
    if ! zfs list -H "$PCT_TRANSLOG_POOL" >/dev/null 2>&1; then
      log_error_exit "ZFS dataset not found: $PCT_TRANSLOG_POOL"
    fi
  fi

  if [ -n "$PCT_DAOS_SIZE_GB" ] && [ "$PCT_DAOS_POOL" != "$PCT_DATA_POOL" ]; then
    if ! zfs list -H "$PCT_DAOS_POOL" >/dev/null 2>&1; then
      log_error_exit "ZFS dataset not found: $PCT_DAOS_POOL"
    fi
  fi

  header "Clone container image $PCT_TEMPLATE_ID -> $VMID"

  pct clone "$PCT_TEMPLATE_ID" "$VMID" --full 

  header "Configuring LXC $VMID"

  pct set  $VMID --description "HCL Domino server $VMID"

  if [ -z "$PCT_TAGS" ]; then
    pct set  $VMID --tags "$PCT_TAGS"
  fi

  zfs create -o refquota=${PCT_DISK_SIZE_GB}G "$PCT_DOMINO_VOL_LOCAL"

  pct set $VMID -memory $PCT_RAM_MB -swap $PCT_SWAP_MB -cores $PCT_CPU

  # Ensure container 1000 is owner of the volume
  chown 101000:101000 "/$PCT_DOMINO_VOL_LOCAL"

  # Domino NSF/NIF/FT data should have 32K or smaller
  zfs set recordsize=${PCT_RECORD_SIZE}K "$PCT_DOMINO_VOL_LOCAL"

  if [ -n "$PCT_NSF_SIZE_GB" ]; then
    zfs create -o refquota=${PCT_NSF_SIZE_GB}G "$PCT_DOMINO_VOL_NSF"
    zfs set recordsize=${PCT_RECORD_SIZE}K "$PCT_DOMINO_VOL_NSF"
    chown 101000:101000 "/$PCT_DOMINO_VOL_NSF"
  fi

  if [ -n "$PCT_TRANSLOG_SIZE_GB" ]; then
    zfs create -o refquota=${PCT_TRANSLOG_SIZE_GB}G "$PCT_DOMINO_VOL_TRANSLOG"
    zfs set recordsize=16K "$PCT_DOMINO_VOL_TRANSLOG"
    chown 101000:101000 "/$PCT_DOMINO_VOL_TRANSLOG"
  fi

  if [ -n "$PCT_DAOS_SIZE_GB" ]; then

    zfs create -o refquota=${PCT_DAOS_SIZE_GB}G "$PCT_DOMINO_VOL_DAOS"
    zfs set recordsize=128K "$PCT_DOMINO_VOL_DAOS"
    zfs set dedup=on "$PCT_DOMINO_VOL_DAOS"
    chown 101000:101000 "/$PCT_DOMINO_VOL_DAOS"
  fi

  if [ -n "$PCT_BACKUP_SIZE_GB" ]; then
    zfs create -o refquota=${PCT_BACKUP_SIZE_GB}G "$PCT_DOMINO_VOL_BACKUP"
    zfs set recordsize=128K "$PCT_DOMINO_VOL_BACKUP"
    zfs set dedup=on "$PCT_DOMINO_VOL_BACKUP"
    chown 101000:101000 "/$PCT_DOMINO_VOL_BACKUP"
  fi

  # Ensure container 1000 is owner of the volume
  chown 101000:101000 "/$PCT_DOMINO_VOL_LOCAL"

  pct set $VMID -hostname "$PCT_HOSTNAME"
  pct set $VMID -mp0 $PCT_DOMINO_VOL_OPT,mp=/opt,ro=1
  pct set $VMID -mp1 /$PCT_DOMINO_VOL_LOCAL,mp=/local

  if [ -n "$PCT_NSF_SIZE_GB" ]; then
    pct set $VMID -mp2 /$PCT_DOMINO_VOL_NSF,mp=/local/notesdata
  fi

  if [ -n "$PCT_TRANSLOG_SIZE_GB" ]; then
    pct set $VMID -mp3 /$PCT_DOMINO_VOL_TRANSLOG,mp=/local/translog
  fi

  if [ -n "$PCT_DAOS_SIZE_GB" ]; then
    pct set $VMID -mp4 /$PCT_DOMINO_VOL_DAOS,mp=/local/daos
  fi

  if [ -n "$PCT_BACKUP_SIZE_GB" ]; then
    pct set $VMID -mp5 /$PCT_DOMINO_VOL_BACKUP,mp=/local/backup
  fi

  pct start $VMID
  sleep 5
  get_pct_status

  header "Generate user key & push public key"

  pct push $VMID ed25519-lxc.pub /root/.ssh/authorized_keys
  pct exec $VMID -- sudo -u notes ssh-keygen -t ed25519 -N "" -f /home/notes/.ssh/id_ed25519
  pct push $VMID ed25519-lxc.pub /home/notes/.ssh/authorized_keys

  header "Generate new server SSH keys"

  # Templates should have SSH keys removed. OpenSSH server requires those keys - but does not re-create them
  pct exec $VMID -- ssh-keygen -A
  sleep 5
  pct exec $VMID -- systemctl restart ssh

  print_server_config

  header "LXC $VMID created"
  echo "Use the following command to jump into your new Domino LXC container"
  log "pct enter $VMID"
  print_status
}


pct_start()
{
  header "Starting LXC $VMID"

  if [ -z "$LXC_STATUS" ]; then
    log_error "Container does not exist"
    return 0
  fi

  pct start $VMID
  get_pct_status

  log "Done"
}


pct_update()
{
  header "Updating LXC $VMID"

  if [ -z "$LXC_STATUS" ]; then
    log_error "Container does not exists"
    return 0
  fi

  pct shutdown $VMID
  pct set $VMID -mp1 $PCT_DOMINO_VOL_OPT,mp=/opt,ro=1
  pct start $VMID
}


pct_shutdown()
{
  header "Shutting down LXC $VMID"

  log "Waiting for shutdown ..."

  if [ "$LXC_STATUS" != "running" ]; then
    log_error "Container is not running: $LXC_STATUS"
    return 0
  fi

  pct shutdown $VMID
}


pct_destroy()
{
  header "Destroying LXC $VMID"

  if [ -z "$LXC_STATUS" ]; then
    log "Info: Container does not exists"
    return 0
  fi

  if [ "$LXC_STATUS" = "running" ]; then
    log "Shutting down container first ..."
    pct shutdown $VMID
  fi

  pct destroy $VMID
}


pct_kill()
{
  if [ -z "$LXC_STATUS" ]; then
    log_error "Container does not exists"
    return 0
  fi

  if [ "$LXC_STATUS" = "running" ]; then
    log "Stopping container first ..."
    pct stop $VMID
  fi

  pct destroy $VMID
}


destroy_dataset()
{
  DATASET="$1"

  if [ -z "$DATASET" ]; then
    return
  fi

  if zfs list -H "$DATASET" >/dev/null 2>&1; then
    echo "Destroying ZFS dataset: $DATASET"
    zfs destroy -r "$DATASET" || log_error "Failed to destroy $DATASET"
  else
    echo "Dataset not found: $DATASET"
  fi
}


pct_kill_disks()
{
  header "Destroying ZFS datasets for LXC $VMID"

  # Core datasets (always present)
  destroy_dataset "$PCT_DOMINO_VOL_LOCAL"

  # Optional datasets
  [ -n "$PCT_NSF_SIZE_GB" ] && destroy_dataset "$PCT_DOMINO_VOL_NSF"
  [ -n "$PCT_TRANSLOG_SIZE_GB" ] && destroy_dataset "$PCT_DOMINO_VOL_TRANSLOG"
  [ -n "$PCT_DAOS_SIZE_GB" ] && destroy_dataset "$PCT_DOMINO_VOL_DAOS"
  [ -n "$PCT_BACKUP_SIZE_GB" ] && destroy_dataset "$PCT_DOMINO_VOL_BACKUP"

  log "ZFS cleanup completed for LXC $VMID"
}


pct_about_container()
{
  if [ "$LXC_STATUS" != "running" ]; then
    log_error "Container is not running: $LXC_STATUS"
    return 0
  fi

  pct exec $VMID -- domino about
}


pct_bash()
{
  header "LXC $VMID - $PCT_HOSTNAME"

  if [ "$LXC_STATUS" != "running" ]; then
    log_error "Container is not running: $LXC_STATUS"
    return 0
  fi

  pct enter "$VMID"
}


pct_config()
{
  header "Config LXC $VMID"

  if [ -z "$LXC_STATUS" ]; then
    log_error "Container not found"
    return 0
  fi

  pct config "$VMID"
  echo
}


print_status()
{
  if [ -z "$LXC_STATUS" ]; then
    PCT_IP_ADDRESS=
    PCT_HOSTNAME=
  else
    PCT_IP_ADDRESS=$(pct exec $VMID -- hostname -I)
    PCT_HOSTNAME=$(pct exec $VMID -- hostname)
  fi

  header "PCT Status"
  echo "VMID        :  $VMID"
  echo "Status      :  $LXC_STATUS"
  echo "IP Address  :  $PCT_IP_ADDRESS"
  echo
}


usage()
{
  log "Usage: $0 {create|start|stop|about|update|status|enter|PCT_PROFILE|config|profile|destroy} <VMID>"
}


enable_raw()
{
  stty -echo -icanon time 0 min 1
  tput civis
}

disable_raw()
{
  stty sane
  tput cnorm
}

cleanup()
{
  disable_raw
  echo
  exit 0
}

ClearScreen()
{
  printf "\033[H\033[J"
}

# Detect interactive terminal
if [ -t 1 ]; then
  USE_HIGHLIGHT=1
else
  USE_HIGHLIGHT=0
fi


highlight_line()
{
  local text="$1"

  if [ "$USE_HIGHLIGHT" = "1" ]; then
    printf "\033[7m%s\033[0m\n" "  $text  "
  else
    printf "> %s\n" "  $text  "
  fi
}


print_line()
{
  printf "%s\n" "  $1  "
}

press_any_key()
{
  if [ "$PCT_MENU" = "1" ]; then
    read -n1 -p "Press any key to continue..." || cleanup
  fi
}

edit_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ -z "$EDIT_COMMAND" ]; then
    if [ -n "$EDITOR" ]; then
      EDIT_COMMAND="$EDITOR"
    else
      EDIT_COMMAND="vi"
    fi
  fi

  "$EDIT_COMMAND" "$1"
}

create_cfg_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ -f "$1" ]; then
    return 0
  fi

  touch "$1"

  if [ -n "$1" ]; then
    echo "# Domino LXC configuration - $2" >> "$1"
    echo >> "$1"
  fi

  echo "PCT_TAGS=domino" >>  "$1"
  echo "PCT_DATA_POOL=rpool/data" >> "$1"
  echo "PCT_DAOS_POOL=rpool/data" >> "$1"
  echo "PCT_TRANSLOG_POOL=rpool/data" >> "$1"
  echo  >> "$1"
  echo "PCT_TRANSLOG_SIZE_GB=5" >> "$1"
  echo "PCT_NSF_SIZE_GB=100" >> "$1"
  echo "PCT_BACKUP_SIZE_GB=100" >> "$1"
  echo "PCT_DAOS_SIZE_GB=100" >> "$1"
  echo  >> "$1"
  echo "PCT_RAM_GB=8" >> "$1"
  echo "PCT_SWAP_GB=0" >> "$1"
  echo "PCT_CPU=4" >> "$1"
}

run_action()
{
  local cmd=

  if [ "$PCT_MENU" = "1" ]; then
        cmd="${OPTIONS[$1]}"
  else
    cmd="$1"
  fi

  ClearScreen

  case "$cmd" in

    create)
      pct_create
      ;;

    start)
      pct_start
      ;;

    stop)
      pct_shutdown
      ;;

    status)
      print_status
      press_any_key
      ;;

    about)
      pct_about_container
      press_any_key
      ;;

    update)
      pct_update
      press_any_key
      ;;

    config)
      pct_config
      press_any_key
      ;;

    enter)
      pct_bash
      ;;

    destroy)
      pct_destroy
      ;;

    profile)
      create_cfg_file "$PCT_CONFIG_FILE" "$PCT_PROFILE_NAME"
      edit_file "$PCT_CONFIG_FILE"
      ;;

    kill)
      pct_kill
      ;;

    quit)
      log "Bye"
      exit 0
      ;;

    KILL-WITH-DISKS)
      pct_kill
      pct_kill_disks
      ;;

    *)
      log "Unknown option: $cmd"
      ;;
  esac

  echo
}


OPTIONS_CREATE=(
  "create"
  "profile"
  "quit"
)

OPTIONS_RUNNING=(
  "enter"
  "stop"
  "status"
  "about"
  "update"
  "config"
  "profile"
  "destroy"
  "quit"
)


OPTIONS_STOPPED=(
  "start"
  "status"
  "about"
  "update"
  "config"
  "profile"
  "destroy"
  "quit"
)


menu()
{
  local selected=0
  local key

  enable_raw

  while true
  do
    ClearScreen

    echo
    echo "dompct - LXC Container Control"
    echo "------------------------------"
    echo

    if [ -n "$LXC_STATUS" ]; then
      echo " VMID    : $VMID"
      echo " Host    : $PCT_CFG_HOSTNAME"
      echo " Tags    : $PCT_CFG_TAGS"
      echo " Profile : $PCT_PROFILE_NAME"
      echo
      echo " Status  : $LXC_STATUS"
    fi
    echo

    for i in "${!OPTIONS[@]}"
    do
      if [ "$i" -eq "$selected" ]; then
        highlight_line "${OPTIONS[$i]}"
      else
        print_line "${OPTIONS[$i]}"
      fi
    done

    echo
    echo
    echo "Use ↑↓ , ENTER or ESC"
    echo

    read -rsn1 key || cleanup

    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 rest || cleanup
      key+="$rest"

      case "$key" in
        $'\x1b[A') ((selected--)) ;;  # up
        $'\x1b[B') ((selected++)) ;;  # down
        $'\x1b') cleanup ;;           # ESC
      esac

    elif [[ "$key" == "" ]]; then
      disable_raw
      return $selected

    elif [[ "$key" == "q" ]]; then
      cleanup
    fi

    # Clamp
    ((selected < 0)) && selected=0
    ((selected >= ${#OPTIONS[@]})) && selected=$((${#OPTIONS[@]} - 1))
  done
}

pct_list()
{
  local search="$1"

  pct list | grep -i -e "$search" -e '^VMID'
}

pct_find_vmid_by_hostname()
{
  local search="$1"
  local lines
  local count

  if [ -z "$search" ]; then
    echo "Error: hostname required" >&2
    return 1
  fi

  # Match hostname (last column) loosely, skip header
  lines=$(pct list | grep -i "$search" | grep -v '^VMID')

  # Count matching lines
  count=$(printf "%s\n" "$lines" | grep -c .)

  case "$count" in
    0)
      return 1
      ;;
    1)
      # Extract VMID (first column)
      VMID=$(printf "%s\n" "$lines" | awk '{print $1}')
      return 0
      ;;
    *)
      echo "Error: multiple matches for [$search]:" >&2
      printf "%s\n" "$lines" >&2
      return 1
      ;;
  esac
}

install_script()
{
  local TARGET_FILE="/usr/local/bin/dompct"
  local INSTALL_FILE="${BASH_SOURCE[0]}"
  local SUDO=
  local CURRENT_VERSION=

  if [ ! "$UID" = "0" ]; then
    SUDO=sudo
  fi

  if [ "$$TARGET_FILE" = "$INSTALL_FILE" ]; then
    log "Executed script is the installed file."
    exit 0
  fi

  if [ -x "$TARGET_FILE" ]; then
    CURRENT_VERSION=$($TARGET_FILE --version)

    if [ "$VERSION" = "$CURRENT_VERSION" ]; then
      log "Already latest Domino Download version installed: $CURRENT_VERSION"
      exit 0
    fi
  fi

  header "Install Domino Download Script"

  if [ ! -w "/usr/local/bin" ]; then
    log "Info: Need root permissions to install $TARGET_FILE (you might get prompted for sudo permissions)"
    SUDO=sudo
  fi

  $SUDO cp "$INSTALL_FILE" "$TARGET_FILE"

  if [ ! "$?" = "0" ]; then
    log_error_exit "Installation failed - Cannot copy [$INSTALL_FILE] to [$TARGET_FILE]"
  fi

  $SUDO chmod +x "$TARGET_FILE"

  if [ ! "$?" = "0" ]; then
    log_error_exit "Installation failed - Cannot change permissions for [$TARGET_FILE]"
  fi

  if [ -z "$CURRENT_VERSION" ]; then
    log "Successfully installed version $VERSION to $TARGET_FILE"
  else
    log "Successfully updated from version $CURRENT_VERSION to $VERSION"
  fi

  return 0
}


# --- Main logic ---


if ! command -v pct >/dev/null 2>&1; then
  log_error_exit "No Proxmox PCT environment found"
fi


case "$VMID" in
  0)
    log_error "Invalid VMID: 0"
    exit 1
    ;;
esac


# --- Default Parameters ---

: "${PCT_DATA_POOL:=rpool/data}"
: "${PCT_DISK_SIZE_GB:=50}"
: "${PCT_RECORD_SIZE:=16}"
: "${PCT_NET0:=name=eth0,bridge=vmbr0,ip=dhcp}"
: "${PCT_TEMPLATE_ID:=9000}"
: "${PCT_RAM_MB:=4096}"
: "${PCT_SWAP_MB:=4096}"
: "${PCT_CPU:=2}"


if [ -z "$PCT_HOSTNAME" ]; then
  PCT_HOSTNAME=lxc-${VMID}-domino
fi

PCT_DOMINO_OPT_LATEST=/rpool/data/domino-opt-latest

if [ ! -e "$PCT_DOMINO_OPT_LATEST" ]; then
  log_error_exit "Domino /opt volume not found: $PCT_DOMINO_OPT_LATEST"
fi

CMD=

for arg in "$@"
do
  case "$arg" in

    --version|-version)
      echo -n $VERSION
      exit 0
      ;;

    install)
      install_script
      exit 0
      ;;

    create|start|stop|about|update|status|enter|PCT_PROFILE|config|destroy|profile|list|KILL|KILL-WITH-DISKS)
      if [ -n "$CMD" ]; then
        log_error "Multiple commands specified: $CMD and $arg"
        exit PCT_PROFILE_NAME
      fi
      CMD="$arg"
      ;;

    -profile=*)
      PCT_PROFILE_NAME="${arg#*=}"
      ;;

    *)
      case "$arg" in
        *[!0-9]* | "" )
          if [ -n "$VM_HOST" ]; then
            log_error "Invalid options specified"
            exit 1
          fi
          VM_HOST="$arg"
          ;;
        *)
          if [ -n "$VMID" ]; then
            log_error "Multiple IDs specified: $VMID and $arg"
            exit 1
          fi
          VMID="$arg"
          ;;
      esac
      ;;

  esac
done

if [ -n "$VMID" ] && [ -n "$VM_HOST" ]; then
  log_error "Invalid parameter combination"
  exit 1
fi

if [ "$CMD" = "list" ]; then

  echo
  if [ -z "$VM_HOST" ]; then
    pct_list "$VMID"
  else
    pct_list "$VM_HOST"
  fi
  echo
  exit 0
fi

if [ -n "$VM_HOST" ]; then

  pct_find_vmid_by_hostname "$VM_HOST"

  if [ -z "$VMID" ]; then
    log_error "Invalid host name or command"
    exit 1
  fi
fi

if [ -z "$VMID" ]; then
  log_error "Numeric container ID required"
  exit 1
fi

if [ -z "$PCT_PROFILE_NAME" ]; then
  PCT_PROFILE_NAME=default
fi

PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"

if [ -f "$PCT_CONFIG_FILE" ]; then
  source "$PCT_CONFIG_FILE"
  echo "Using $PCT_CONFIG_FILE"
fi

# Calculate variables after the configuration was read

# Memory is specifed in MB but we want to specify GB
PCT_RAM_MB=$((1024 * PCT_RAM_GB))
PCT_SWAP_MB=$((1024 * PCT_SWAP_GB))

# Calculate volume names based on configuration for create and for reference
# LATER: Check if it would be better to read the current config and move this logic into pct_create for consistency

if [ -z "$PCT_DAOS_POOL" ]; then
  PCT_DAOS_POOL="$PCT_DATA_POOL"
fi

if [ -z "$PCT_TRANSLOG_POOL" ]; then
  PCT_TRANSLOG_POOL="$PCT_DATA_POOL"
fi

PCT_DOMINO_VOL_LOCAL="${PCT_DATA_POOL}/subvol-${VMID}-domino-local"
PCT_DOMINO_VOL_NSF="${PCT_DATA_POOL}/subvol-${VMID}-domino-nsf"
PCT_DOMINO_VOL_TRANSLOG="${PCT_TRANSLOG_POOL}/subvol-${VMID}-domino-translog"
PCT_DOMINO_VOL_DAOS="${PCT_DAOS_POOL}/subvol-${VMID}-domino-daos"
PCT_DOMINO_VOL_BACKUP="${PCT_DATA_POOL}/subvol-${VMID}-domino-backup"

if [ -z "$PCT_DOMINO_VOL_OPT" ]; then
  PCT_DOMINO_VOL_OPT=$(readlink -f "$PCT_DOMINO_OPT_LATEST")
fi

if [ -z "$PCT_DOMINO_VOL_OPT" ]; then
  log_error_exit "Domino /opt volume link is invalid: $PCT_DOMINO_OPT_LATEST"
fi

# First get status (Relevant for almost every command)
get_pct_status

# Ensure script ends cleanly and resets terminal
shopt -s huponexit
trap 'exit' SIGINT SIGTERM SIGHUP


if [ -z "$CMD" ]; then

  PCT_MENU=1

  while true
  do
    if [ -z "$LXC_STATUS" ]; then
      OPTIONS=("${OPTIONS_CREATE[@]}")
    elif [ "$LXC_STATUS" = "running" ]; then
      OPTIONS=("${OPTIONS_RUNNING[@]}")
    else
      OPTIONS=("${OPTIONS_STOPPED[@]}")
    fi

    menu
    run_action $?
    get_pct_status
  done

  exit 0
fi

run_action "$CMD"
exit 0

