#!/bin/bash
############################################################################
# Proxmox LXC Container Management Script
# Copyright Nash!Com, Daniel Nashed 2026  - APACHE 2.0 see LICENSE
############################################################################

VERSION="0.9.4"


print_delim()
{
  echo "--------------------------------------------------------------------------------"
}


header()
{
  if [ -n "$OUTPUT_FORMAT" ]; then
    return 0
  fi

  echo
  print_delim
  echo "$1"
  print_delim
  echo
}

print_info()
{
  if [ -n "$OUTPUT_FORMAT" ]; then
    return 0
  fi

  echo "$@"
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
  if [ "$OUTPUT_FORMAT" = "json" ]; then

    printf '{\n'
    printf '  "error": "%s",\n' "$1"
    printf '}\n'

  else
    log "ERROR: $1"
  fi

  exit 1
}

inject_ssh_pubkey()
{
    VMID="$1"
    USERNAME="$2"
    PUBKEY="$3"

    if [ -z "$VMID" ] || [ -z "$USERNAME" ] || [ -z "$PUBKEY" ]; then
        echo "Usage: inject_ssh_pubkey <vmid> <user> <pubkey>"
        return 1
    fi

    # basic validation
    if ! printf "%s\n" "$PUBKEY" | grep -qE '^(ssh-|ecdsa-)'; then
        echo "Invalid SSH public key format"
        return 1
    fi

    printf "%s\n" "$PUBKEY" | pct exec "$VMID" -- sh -c '
user="'"$USERNAME"'"

home=$(getent passwd "$user" | cut -d: -f6)

mkdir -p "$home/.ssh"
touch "$home/.ssh/authorized_keys"

key="$(cat)"
grep -qxF "$key" "$home/.ssh/authorized_keys" 2>/dev/null || echo "$key" >> "$home/.ssh/authorized_keys"

chown -R "$user:$user" "$home/.ssh"
chmod 700 "$home/.ssh"
chmod 600 "$home/.ssh/authorized_keys"
'
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


config_to_env_file()
{
  local CONFIG_FILE="$1"
  local OUTPUT_FILE="$2"

  if [ -z "$OUTPUT_FILE" ]; then
    return 0
  fi

  if [ -z "$CONFIG_FILE" ]; then
    return 0
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "config file not found: $CONFIG_FILE"
    return 0
  fi

  while IFS='=' read -r key value
  do
    if [ -z "$key" ]; then
      continue
    fi

    case "$key" in
      \#*)
        continue
        ;;

      env_*)
        printf "%s=%s\n" "${key#env_}" "$value" >> "$OUTPUT_FILE"
        ;;
    esac

  done < "$CONFIG_FILE"
}


print_status()
{
  if [ -z "$LXC_STATUS" ]; then
    PCT_IP_ADDRESS=
    PCT_HOSTNAME=
  else
    PCT_IP_ADDRESS=$(pct exec $VMID -- hostname -I)
    PCT_IP_ADDRESS=${PCT_IP_ADDRESS%% *}

    PCT_HOSTNAME=$(pct exec $VMID -- hostname)
    PCT_HOSTNAME=${PCT_HOSTNAME%% *}
  fi

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    printf '{\n'
    printf '  "vmid": "%s",\n' "$VMID"
    printf '  "status": "%s",\n' "$LXC_STATUS"
    printf '  "ip_address": "%s"\n' "$PCT_IP_ADDRESS"
    printf '}\n'

  else
    header "PCT Status"
    echo "VMID        :  $VMID"
    echo "Status      :  $LXC_STATUS"
    echo "IP Address  :  $PCT_IP_ADDRESS"
    echo
  fi
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

  pct clone "$PCT_TEMPLATE_ID" "$VMID" --full > "$LOG_OUTPUT" 2>&1

  header "Configuring LXC $VMID"

  if [ -z "$PCT_DESCRIPTION" ]; then
    PCT_DESCRIPTION="HCL Domino server $VMID"
  fi

  if [ -n "$PCT_DESCRIPTION" ]; then
    pct set $VMID --description "$PCT_DESCRIPTION" > "$LOG_OUTPUT" 2>&1
    print_info "Description -> $PCT_DESCRIPTION"
  fi

  if [ -n "$PCT_TAGS" ]; then
    pct set $VMID --tags "$PCT_TAGS" > "$LOG_OUTPUT" 2>&1
    print_info "Tags -> $PCT_TAGS"
  fi

  zfs create -o refquota=${PCT_DISK_SIZE_GB}G "$PCT_DOMINO_VOL_LOCAL" > "$LOG_OUTPUT" 2>&1

  pct set $VMID -memory $PCT_RAM_MB -swap $PCT_SWAP_MB -cores $PCT_CPU > "$LOG_OUTPUT" 2>&1

  # Ensure container 1000 is owner of the volume
  chown 101000:101000 "/$PCT_DOMINO_VOL_LOCAL" > "$LOG_OUTPUT" 2>&1

  # Domino NSF/NIF/FT data should have 32K or smaller
  zfs set recordsize=${PCT_RECORD_SIZE}K "$PCT_DOMINO_VOL_LOCAL" > "$LOG_OUTPUT" 2>&1

  if [ -n "$PCT_NSF_SIZE_GB" ]; then
    zfs create -o refquota=${PCT_NSF_SIZE_GB}G "$PCT_DOMINO_VOL_NSF" > "$LOG_OUTPUT" 2>&1
    zfs set recordsize=${PCT_RECORD_SIZE}K "$PCT_DOMINO_VOL_NSF" > "$LOG_OUTPUT" 2>&1
    chown 101000:101000 "/$PCT_DOMINO_VOL_NSF" > "$LOG_OUTPUT" 2>&1
  fi

  if [ -n "$PCT_TRANSLOG_SIZE_GB" ]; then
    zfs create -o refquota=${PCT_TRANSLOG_SIZE_GB}G "$PCT_DOMINO_VOL_TRANSLOG" > "$LOG_OUTPUT" 2>&1
    zfs set recordsize=16K "$PCT_DOMINO_VOL_TRANSLOG" > "$LOG_OUTPUT" 2>&1
    chown 101000:101000 "/$PCT_DOMINO_VOL_TRANSLOG" > "$LOG_OUTPUT" 2>&1
  fi

  if [ -n "$PCT_DAOS_SIZE_GB" ]; then

    zfs create -o refquota=${PCT_DAOS_SIZE_GB}G "$PCT_DOMINO_VOL_DAOS" > "$LOG_OUTPUT" 2>&1
    zfs set recordsize=128K "$PCT_DOMINO_VOL_DAOS" > "$LOG_OUTPUT" 2>&1
    zfs set dedup=on "$PCT_DOMINO_VOL_DAOS" > "$LOG_OUTPUT" 2>&1
    chown 101000:101000 "/$PCT_DOMINO_VOL_DAOS" > "$LOG_OUTPUT" 2>&1
  fi

  if [ -n "$PCT_BACKUP_SIZE_GB" ]; then
    zfs create -o refquota=${PCT_BACKUP_SIZE_GB}G "$PCT_DOMINO_VOL_BACKUP" > "$LOG_OUTPUT" 2>&1
    zfs set recordsize=128K "$PCT_DOMINO_VOL_BACKUP" > "$LOG_OUTPUT" 2>&1
    zfs set dedup=on "$PCT_DOMINO_VOL_BACKUP" > "$LOG_OUTPUT" 2>&1
    chown 101000:101000 "/$PCT_DOMINO_VOL_BACKUP" > "$LOG_OUTPUT" 2>&1
  fi

  # Ensure container 1000 is owner of the volume
  chown 101000:101000 "/$PCT_DOMINO_VOL_LOCAL" > "$LOG_OUTPUT" 2>&1

  pct set $VMID -hostname "$PCT_HOSTNAME" > "$LOG_OUTPUT" 2>&1
  pct set $VMID -mp0 $PCT_DOMINO_VOL_OPT,mp=/opt,ro=1 > "$LOG_OUTPUT" 2>&1
  pct set $VMID -mp1 /$PCT_DOMINO_VOL_LOCAL,mp=/local > "$LOG_OUTPUT" 2>&1

  if [ -n "$PCT_NSF_SIZE_GB" ]; then
    pct set $VMID -mp2 /$PCT_DOMINO_VOL_NSF,mp=/local/notesdata > "$LOG_OUTPUT" 2>&1
  fi

  if [ -n "$PCT_TRANSLOG_SIZE_GB" ]; then
    pct set $VMID -mp3 /$PCT_DOMINO_VOL_TRANSLOG,mp=/local/translog > "$LOG_OUTPUT" 2>&1
  fi

  if [ -n "$PCT_DAOS_SIZE_GB" ]; then
    pct set $VMID -mp4 /$PCT_DOMINO_VOL_DAOS,mp=/local/daos > "$LOG_OUTPUT" 2>&1
  fi

  if [ -n "$PCT_BACKUP_SIZE_GB" ]; then
    pct set $VMID -mp5 /$PCT_DOMINO_VOL_BACKUP,mp=/local/backup > "$LOG_OUTPUT" 2>&1
  fi

  config_to_env_file "$PCT_CONFIG_FILE" "/$PCT_DOMINO_VOL_LOCAL/domino.env"
  chown 101000:101000 "/$PCT_DOMINO_VOL_LOCAL/domino.env" > "$LOG_OUTPUT" 2>&1

  if [ -n "$PCT_IP" ]; then
    if [ -z "$PCT_NET0_TEMPLATE" ]; then
      log_error_exit "IP address specified but no network template configured"
    fi

    PCT_NET0="${PCT_NET0_TEMPLATE//%PCT_IP%/$PCT_IP}"
  fi

  if [ -n "$PCT_NET0" ]; then
    header "Updating Network Configuration"
    pct set "$VMID" -net0 "$PCT_NET0"
    print_info "IP  : $PCT_IP"
    print_info "NET0: $PCT_NET0"
  fi

  pct start $VMID
  sleep 5
  get_pct_status

  header "Generate new server SSH keys"

  # Templates should have SSH keys removed. OpenSSH server requires those keys - but does not re-create them
  pct exec $VMID -- ssh-keygen -A > "$LOG_OUTPUT" 2>&1
  sleep 5
  pct exec $VMID -- systemctl restart ssh > "$LOG_OUTPUT" 2>&1


  header "Adding SSH public key to 'notes' user"

  if [ -n "$PCT_SSH_PUBKEY" ]; then
    SSH_PUBKEY="$PCT_SSH_PUBKEY"

  elif [ -n "$PCT_SSH_PUBKEY_FILE" ]; then
    if [ -f "$PCT_SSH_PUBKEY_FILE" ]; then
      SSH_PUBKEY="$(cat "$PCT_SSH_PUBKEY_FILE")"
    else
     log_error_exit "SSH public key not found: $PCT_SSH_PUBKEY_FILE"
    fi

  else
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      SSH_PUBKEY="$(cat "$HOME/.ssh/id_ed25519.pub")"
    fi
  fi

  if [ -z "$SSH_PUBKEY" ]; then
   print_info "Warning: No SSH public key found to push"
  else
    inject_ssh_pubkey "$VMID" "notes" "$SSH_PUBKEY"
  fi

  if [ -z "$OUTPUT_FORMAT" ]; then
    print_server_config
  fi

  header "LXC $VMID created"

  print_info "Use the following command to jump into your new Domino LXC container"
  print_info
  print_info "pct enter $VMID"
  print_info

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
  header "LXC $VMID - $PCT_CFG_HOSTNAME"

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


usage()
{
cat <<EOF

dompct - LXC Container Control Utility

Usage:

  $0 <command> [VMID] [options]

Commands:

  create              Create new container
  start               Start container
  stop                Stop container
  status              Show container status
  enter | bash        Enter container shell
  config              Show container configuration
  update              Update container
  destroy             Destroy container
  about               Show container information
  profile             Select or apply profile
  list                List containers
  KILL                Force kill container
  KILL-WITH-DISKS     Kill container and remove disks

Global Options:

  -profile=<name>     Use profile (from ~/.dompct/*.cfg)
  -host=<name>        Set hostname
  -hostname=<name>    Same as -host
  -tags=<tags>        Set Proxmox tags (comma-separated)
  -ip=<ip>            Assign IP address
  -description=<txt>  Set container description
  -opt-vol=<opts>     Volume options (advanced)

Output Options:

  -json               Output in JSON format (where supported)

Arguments:

  VMID                Numeric container ID (required for most commands)

Examples:

  $0 list
  $0 start 200
  $0 create -profile=mail
  $0 profile
  $0 destroy 200

Notes:

  - If VMID is omitted, interactive menu may be used
  - Profiles are stored in: ~/.dompct/

EOF
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
  if [ -n "$OUTPUT_FORMAT" ]; then
    return 0
  fi

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

cleanup_profiles_menu()
{
  disable_raw
  PCT_SELECTED_PROFILE_NAME=
  return 0
}


menu_profiles()
{
  local selected=0
  local key
  local profiles=()

  PCT_SELECTED_PROFILE_NAME=

  mapfile -t profiles < <(
    find "$HOME/.dompct" -name "*.cfg" -printf "%f\n" |
    sed 's/\.cfg$//' |
    sort
  )

  [ ${#profiles[@]} -eq 0 ] && {
    echo "No profiles found"
    return 1
  }

  enable_raw

  while true
  do
    ClearScreen

    echo
    echo "dompct - Select Profile"
    echo "------------------------"
    echo

    for i in "${!profiles[@]}"
    do
      if [ "$i" -eq "$selected" ]; then
        highlight_line "${profiles[$i]}"
      else
        print_line "${profiles[$i]}"
      fi
    done

    echo
    echo "Use ↑↓ , ENTER or ESC"
    echo

    read -rsn1 key || cleanup

    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 rest || cleanup_profiles_menu
      key+="$rest"

      case "$key" in
        $'\x1b[A') ((selected--)) ;;  # up
        $'\x1b[B') ((selected++)) ;;  # down
        $'\x1b') # ESC
          cleanup_profiles_menu
          return 0
          ;;
      esac

    elif [[ "$key" == "" ]]; then
      cleanup_profiles_menu
      PCT_SELECTED_PROFILE_NAME="${profiles[$selected]}"
      return 0

    elif [[ "$key" == "q" ]]; then
      cleanup_profiles_menu
      return 0
    fi

    # Clamp
    ((selected < 0)) && selected=0
    ((selected >= ${#profiles[@]})) && selected=$((${#profiles[@]} - 1))
  done
}


cleanup_vm_menu()
{
  disable_raw
  PCT_SELECTED_VMID=
  return 0
}


menu_select_vmid()
{
  local selected=0
  local key
  local vms=()

  PCT_SELECTED_VMID=

  if [ "$PCT_ALL_CONTAINERS" = "1" ]; then

    mapfile -t vms < <(
      pct list | awk 'NR>1 {
       printf "%-5s %-8s %s\n", $1, $2, $NF
      }'
    )

  else

    mapfile -t vms < <(
      pct list | awk 'NR>1 && $1 >= 200 && $1 < 300 {
        printf "%-5s %-8s %s\n", $1, $2, $NF
      }'
    )

  fi

  [ ${#vms[@]} -eq 0 ] && {
    echo "No containers found"
    return 1
  }

  enable_raw

  while true
  do
    ClearScreen

    echo
    echo "dompct - Select Container"
    echo "-------------------------"
    echo

    for i in "${!vms[@]}"
    do
      if [ "$i" -eq "$selected" ]; then
        highlight_line "${vms[$i]}"
      else
        print_line "${vms[$i]}"
      fi
    done

    echo
    echo "Use ↑↓ , ENTER or ESC"
    echo

    read -rsn1 key || cleanup

    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 rest || cleanup_vm_menu
      key+="$rest"

      case "$key" in
        $'\x1b[A') ((selected--)) ;;  # up
        $'\x1b[B') ((selected++)) ;;  # down
        $'\x1b') # ESC
          cleanup_vm_menu
          return 0
          ;;
      esac

    elif [[ "$key" == "" ]]; then
      cleanup_vm_menu
      PCT_SELECTED_VMID="$(echo "${vms[$selected]}" | awk '{print $1}')"
      return 0

    elif [[ "$key" == "q" ]]; then
      cleanup_vm_menu
      return 0
    fi

    # Clamp
    ((selected < 0)) && selected=0
    ((selected >= ${#vms[@]})) && selected=$((${#vms[@]} - 1))
  done
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

    enter|bash)
      pct_bash
      ;;

    destroy)
      pct_destroy
      ;;

    profile)
      menu_profiles
      if [ -n "$PCT_SELECTED_PROFILE_NAME" ]; then
        PCT_PROFILE_NAME="$PCT_SELECTED_PROFILE_NAME"
        PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
      fi
      ;;

    edit)
      create_cfg_file "$PCT_CONFIG_FILE" "$PCT_PROFILE_NAME"
      edit_file "$PCT_CONFIG_FILE"
      ;;

    KILL)
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
  "edit"
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
  "edit"
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
  "edit"
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
      echo " Host    :  $PCT_CFG_HOSTNAME"
      echo " Tags    :  $PCT_CFG_TAGS"
      echo " Profile :  $PCT_PROFILE_NAME"
      echo
      echo " VMID    :  $VMID"
      echo " Status  :  $LXC_STATUS"
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

  if [ -z "$lines" ]; then
    count=0
  else
    # Count matching lines
    count=$(printf "%s\n" "$lines" | grep -c .)
  fi

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


LOG_OUTPUT="/dev/stdout"

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

    # Commands
    create|start|stop|about|update|status|enter|bash|config|destroy|profile|list|KILL|KILL-WITH-DISKS)
      if [ -n "$CMD" ]; then
        log_error "Multiple commands specified: $CMD and $arg"
        exit 1
      fi
      CMD="$arg"
      ;;

    -profile=*)
      PCT_PROFILE_NAME="${arg#*=}"
      PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
      ;;

   -host=*|-hostname=*)
      PCT_HOSTNAME="${arg#*=}"
      ;;

   -tags=*)
      PCT_SET_TAGS="${arg#*=}"
      ;;

   -ip=*)
      PCT_IP="${arg#*=}"
      ;;

   -description=*)
      PCT_DESCRIPTION="${arg#*=}"
      ;;

   -opt-vol=*)
      PCT_DOMINO_VOL_OPT="${arg#*=}"
      ;;

   -json)
      OUTPUT_FORMAT=json
      ;;

    -?|-h|help|-help)
     usage
     exit
     ;;

    -*)
     log_error_exit "Invalid command specified: $arg"
     ;;

    *)
      case "$arg" in
        *[!0-9]* | "" )
          if [ -n "$VM_HOST" ]; then
            log_error_exit "Invalid options specified"
          fi
          VM_HOST="$arg"
          ;;
        *)
          if [ -n "$VMID" ]; then
            log_error_exit "Multiple IDs specified: $VMID and $arg"
            exit 1
          fi
          VMID="$arg"
          ;;
      esac
      ;;

  esac
done


if [ "$OUTPUT_FORMAT" = "json" ]; then
  LOG_OUTPUT="/dev/null"
fi

if [ -n "$VMID" ] && [ -n "$VM_HOST" ]; then
  log_error_exit "Invalid parameter combination"
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
    log_error_exit "Invalid host name or command"
  fi
fi

case $CMD in
  profile)
    ;;

  *)
    if [ -z "$VMID" ] && [ -n "$OUTPUT_FORMAT" ]; then
      log_error_exit "Numeric container ID required"
    fi

    if [ -z "$VMID" ]; then
      menu_select_vmid
      VMID="$PCT_SELECTED_VMID"
    fi

    if [ -z "$VMID" ]; then
      exit 0
    fi

esac

if [ -z "$PCT_PROFILE_NAME" ]; then
  PCT_PROFILE_NAME=default
fi

if [ -f "$PCT_CONFIG_FILE" ]; then
  source "$PCT_CONFIG_FILE"
  print_info "Using $PCT_CONFIG_FILE"
fi

# command-line overrides

if [ -n "$PCT_SET_TAGS" ]; then
  PCT_TAGS="$PCT_SET_TAGS"
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

if [ -z "$PCT_DOMINO_OPT_LATEST" ]; then
  PCT_DOMINO_OPT_LATEST="/$PCT_DATA_POOL/domino-opt-latest"
fi

if [ -z "$PCT_DOMINO_VOL_OPT" ]; then

  if [ ! -e "$PCT_DOMINO_OPT_LATEST" ]; then
    log_error_exit "Domino /opt volume not found: $PCT_DOMINO_OPT_LATEST"
  fi

  PCT_DOMINO_VOL_OPT=$(readlink -f "$PCT_DOMINO_OPT_LATEST")
fi

if [ -z "$PCT_DOMINO_VOL_OPT" ]; then
  log_error_exit "Domino /opt volume link is invalid: $PCT_DOMINO_OPT_LATEST"
fi

if [ ! -e "$PCT_DOMINO_VOL_OPT" ]; then
  log_error_exit "Domino /opt volume not found: $PCT_DOMINO_VOL_OPT"
fi

# First get status (Relevant for almost every command)
get_pct_status

# Ensure script ends cleanly and resets terminal
shopt -s huponexit
trap 'exit' SIGINT SIGTERM SIGHUP


if [ -z "$CMD" ]; then

  PCT_MENU=1

  if [ -z "$PCT_PROFILE_NAME" ]; then
    PCT_PROFILE_NAME="default"
    PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
  fi

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

if [ "$CMD" = "profile" ]; then

  # If profile specified edit the profile, else prompt and edit if selected
  if [ -n "$PCT_CONFIG_FILE" ]; then
    edit_file "$PCT_CONFIG_FILE"
  else
    run_action "$CMD"

    if [ -n "$PCT_SELECTED_PROFILE_NAME" ]; then
      create_cfg_file "$PCT_CONFIG_FILE" "$PCT_PROFILE_NAME"
      edit_file "$PCT_CONFIG_FILE"
    fi
  fi

else

  if [ -z "$PCT_PROFILE_NAME" ]; then
    PCT_PROFILE_NAME="default"
    PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
  fi

  run_action "$CMD"
fi

exit 0

