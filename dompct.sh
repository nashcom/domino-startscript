#!/bin/bash
############################################################################
# Proxmox LXC Container Management Script
# Copyright Nash!Com, Daniel Nashed 2026  - APACHE 2.0 see LICENSE
############################################################################

VERSION="0.9.7"


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
  print_cfg()     { printf "%-22s %-16s :  %s\n" "$1" "$2" "$3"; }
  print_size()    { printf "%-22s %-16s :  %s\n" "$1" "$2" "$(format_size "$3")"; }
  print_size_mb() { printf "%-22s %-16s :  %4d MB\n" "$1" "$2" "$3"; }
  print_size_kb() { printf "%-22s %-16s :  %4d KB\n" "$1" "$2" "$3"; }

  print_cfg "PCT_DATA_POOL" "Data pool" "$PCT_DATA_POOL"
  print_cfg "PCT_NET0" "Network config" "$PCT_NET0"
  print_cfg "PCT_TEMPLATE_ID" "Template LXC ID" "$PCT_TEMPLATE_ID"
  print_cfg "PCT_CPU" "CPU/Cores" "$PCT_CPU"

  echo

  print_size_kb "PCT_RECORD_SIZE" "ZFS recordsize" "$PCT_RECORD_SIZE"
  print_size "PCT_RAM_GB" "RAM Size" "$PCT_RAM_GB"
  print_size "PCT_SWAP_GB" "Swap Size" "$PCT_SWAP_GB"
  print_size "PCT_DISK_SIZE_GB" "Data disk size" "$PCT_DISK_SIZE_GB"
  [ -n "$PCT_NOTESDATA_SIZE_GB" ] && print_size "PCT_NOTESDATA_SIZE_GB" "NOTESDATA size" "$PCT_NOTESDATA_SIZE_GB"
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


# Helper: resolve ZFS pool from storage
get_zfs_pool_from_storage()
{
  local storage="$1"

  awk -v s="$storage" '
    $1=="zfspool:" && $2==s {found=1}
    found && $1=="pool" {print $2; exit}
  ' /etc/pve/storage.cfg
}

# Helper: create volume
create_vol()
{
  local role="$1"
  local vol="$2"
  local pool="$3"
  local size="$4"
  local storage="$5"

  [ -z "$size" ] && return

  local path
  local mount_point

  header "Creating ZFS Volume $role"

  if [ "$STORAGE_MODE" = "zfs" ]; then

    path="${pool}/${vol}"
    zfs create -o refquota=${size}G "$path" >> "$LOG_OUTPUT" 2>&1 || log_error_exit "ZFS create failed: $path"

  else

    if [ "$role" = "local" ]; then
      mount_point="/local"
    else
      mount_point="/local/$role"
    fi

    PCT_MP_COUNT=$((PCT_MP_COUNT + 1))
    pct set "$VMID" -mp${PCT_MP_COUNT} ${storage}:${size},mp=${mount_point} >> "$LOG_OUTPUT" 2>&1 || log_error_exit "Volume alloc failed"

    # extract actual volume ID
    volid=$(pct config "$VMID" | sed -n "s/^mp${PCT_MP_COUNT}: ${storage}:\([^,]*\).*/\1/p")
    [ -z "$volid" ] && log_error_exit "Failed to resolve volume ID for mp${PCT_MP_COUNT}"

    # resolve ZFS pool behind storage
    local resolved_pool=$(get_zfs_pool_from_storage "$storage")
    [ -z "$resolved_pool" ] && log_error_exit "Cannot resolve pool for storage: $storage"

    # final ZFS dataset path
    path="${resolved_pool}/${volid}"
  fi

  # Apply ZFS tuning
  case "$role" in

    local|notesdata)
      zfs set recordsize=${PCT_RECORD_SIZE}K "$path"

      if [ "$role" = "local" ]; then
        PCT_LOCAL_DIR="/$path"
        PCT_NOTES_DATA_DIR="/$path/notesdata"
      else
        PCT_NOTES_DATA_DIR="/$path"
      fi

      echo "path: $path -> $PCT_NOTES_DATA_DIR"
      ;;
    translog)
      zfs set recordsize=16K "$path"
      ;;
    daos|backup)
      zfs set recordsize=128K "$path"
      zfs set dedup=on "$path"
      ;;

  esac

  zfs set compression=lz4 "$path"
  zfs set atime=off "$path"

  # Change ownership to notes:notes
  chown 101000:101000 "/$path"
}

# Helper: mount volume
mount_vol()
{
  local idx="$1"
  local vol="$2"
  local pool="$3"
  local storage="$4"
  local mp="$5"

  if [ "$STORAGE_MODE" = "zfs" ]; then
    pct set $VMID -mp${idx} /${pool}/${vol},mp="$mp"
  fi
}

check_pool()
{
  local pool="$1"
  zfs list -H "$pool" >/dev/null 2>&1 || log_error_exit "ZFS dataset not found: $pool"
}


pct_create()
{
  header "Creating LXC $VMID"

  # Basic validation
  if [ -n "$LXC_STATUS" ]; then
    log_error "Container already exists: $LXC_STATUS"
    return 0
  fi

  command -v zfs >/dev/null 2>&1 || log_error_exit "No ZFS found"

  # Load config
  if [ -n "$PCT_CONFIG_FILE" ]; then
    [ -f "$PCT_CONFIG_FILE" ] || log_error_exit "Cannot find profile: $PCT_CONFIG_FILE"
    source "$PCT_CONFIG_FILE"
    print_info "Using $PCT_CONFIG_FILE"
  fi

  # Input & normalization
  echo
  [ -z "$PCT_HOSTNAME" ] && read -p "Enter host name: " PCT_HOSTNAME
  [ -z "$PCT_HOSTNAME" ] && log_error_exit "No hostname specified!"

  [ -n "$PCT_RAM_GB"   ] && PCT_RAM_MB=$((1024 * PCT_RAM_GB))
  [ -n "$PCT_SWAP_GB"  ] && PCT_SWAP_MB=$((1024 * PCT_SWAP_GB))

  # Storage mode
  if [ -n "$PCT_STORAGE" ]; then
    STORAGE_MODE="proxmox"
  else
    STORAGE_MODE="zfs"
  fi

  # Defaults
  PCT_DATA_POOL="${PCT_DATA_POOL:-rpool/data}"
  PCT_DAOS_POOL="${PCT_DAOS_POOL:-$PCT_DATA_POOL}"
  PCT_TRANSLOG_POOL="${PCT_TRANSLOG_POOL:-$PCT_DATA_POOL}"

  PCT_STORAGE_DEFAULT="${PCT_STORAGE}"
  PCT_STORAGE_DAOS="${PCT_STORAGE_DAOS:-$PCT_STORAGE_DEFAULT}"
  PCT_STORAGE_TRANSLOG="${PCT_STORAGE_TRANSLOG:-$PCT_STORAGE_DEFAULT}"

  # Volume names (logical only)
  VOL_LOCAL="subvol-${VMID}-domino-local"
  VOL_NOTESDATA="subvol-${VMID}-domino-notesdata"
  VOL_TRANSLOG="subvol-${VMID}-domino-translog"
  VOL_DAOS="subvol-${VMID}-domino-daos"
  VOL_BACKUP="subvol-${VMID}-domino-backup"

  # Validate pools
  if [ "$STORAGE_MODE" = "zfs" ]; then
    zfs list -H "$PCT_DATA_POOL" >/dev/null 2>&1 || log_error_exit "Missing $PCT_DATA_POOL"

    [ "$PCT_TRANSLOG_POOL" != "$PCT_DATA_POOL" ] && check_pool "$PCT_TRANSLOG_POOL"
    [ "$PCT_DAOS_POOL" != "$PCT_DATA_POOL" ] && check_pool "$PCT_DAOS_POOL"

  fi

  if [ -z "$PCT_DOMINO_OPT_LATEST" ]; then
    PCT_DOMINO_OPT_LATEST="/$PCT_DATA_POOL/domino-opt-latest"
  fi

  # Resolve /opt
  [ -z "$PCT_DOMINO_VOL_OPT" ] && PCT_DOMINO_VOL_OPT=$(readlink -f "$PCT_DOMINO_OPT_LATEST")
  [ -e "$PCT_DOMINO_VOL_OPT" ] || log_error_exit "Invalid /opt volume"

  # Clone container
  header "Clone LXC Template $PCT_TEMPLATE_ID -> LXC $VMID"
  pct clone "$PCT_TEMPLATE_ID" "$VMID" --full >> "$LOG_OUTPUT" 2>&1 || log_error_exit "clone failed"

  # Basic config
  pct set $VMID --description "${PCT_DESCRIPTION:-HCL Domino server $VMID}"
  [ -n "$PCT_TAGS" ] && pct set $VMID --tags "$PCT_TAGS"
  [ -n "$PCT_RAM_MB" ] && pct set $VMID -memory $PCT_RAM_MB
  [ -n "$PCT_SWAP_MB" ] && pct set $VMID -swap $PCT_SWAP_MB
  [ -n "$PCT_CPU" ] && pct set $VMID -cores $PCT_CPU
  pct set $VMID -hostname "$PCT_HOSTNAME"

  PCT_MP_COUNT=0

  # Create volumes
  create_vol local "$VOL_LOCAL" "$PCT_DATA_POOL" "$PCT_DISK_SIZE_GB" "$PCT_STORAGE_DEFAULT"
  create_vol notesdata "$VOL_NOTESDATA" "$PCT_DATA_POOL" "$PCT_NOTESDATA_SIZE_GB" "$PCT_STORAGE_DEFAULT"
  create_vol translog "$VOL_TRANSLOG" "$PCT_TRANSLOG_POOL" "$PCT_TRANSLOG_SIZE_GB" "$PCT_STORAGE_TRANSLOG"
  create_vol daos "$VOL_DAOS" "$PCT_DAOS_POOL" "$PCT_DAOS_SIZE_GB" "$PCT_STORAGE_DAOS"
  create_vol backup "$VOL_BACKUP" "$PCT_DATA_POOL" "$PCT_BACKUP_SIZE_GB" "$PCT_STORAGE_DEFAULT"

  # Mount volumes
  pct set $VMID -mp0 $PCT_DOMINO_VOL_OPT,mp=/opt,ro=1

  mount_vol 1 "$VOL_LOCAL" "$PCT_DATA_POOL" "$PCT_STORAGE_DEFAULT" "/local"

  [ -n "$PCT_NOTESDATA_SIZE_GB" ] && mount_vol 2 "$VOL_NOTESDATA" "$PCT_DATA_POOL" "$PCT_STORAGE_DEFAULT" "/local/notesdata"

  [ -n "$PCT_TRANSLOG_SIZE_GB" ] && mount_vol 3 "$VOL_TRANSLOG" "$PCT_TRANSLOG_POOL" "$PCT_STORAGE_TRANSLOG" "/local/translog"

  [ -n "$PCT_DAOS_SIZE_GB" ] && mount_vol 4 "$VOL_DAOS" "$PCT_DAOS_POOL" "$PCT_STORAGE_DAOS" "/local/daos"

  [ -n "$PCT_BACKUP_SIZE_GB" ] && mount_vol 5 "$VOL_BACKUP" "$PCT_DATA_POOL" "$PCT_STORAGE_DEFAULT" "/local/backup"

  # Environment config
  DOMINO_ENV_FILE="$PCT_LOCAL_DIR/domino.env"

  config_to_env_file "$PCT_CONFIG_FILE" "$DOMINO_ENV_FILE"
  chown 101000:101000 "$DOMINO_ENV_FILE"

  # Networking
  if [ -n "$PCT_IP" ]; then
    [ -z "$PCT_NET0_TEMPLATE" ] && log_error_exit "Missing network template"
    PCT_NET0="${PCT_NET0_TEMPLATE//%PCT_IP%/$PCT_IP}"
  fi

  [ -n "$PCT_NET0" ] && pct set "$VMID" -net0 "$PCT_NET0"

  # Start container
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
  print_info "Use the following command to open a bash in your new Domino LXC container"
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

  if [ "$LXC_STATUS" = "running" ]; then
    header "Stopping container LXC $VMID after shutdown timeout"
    pct stop $VMID
  fi
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

  local DISK_PREFIX="subvol-${VMID}-domino"

  zfs list -H -o name | grep "${DISK_PREFIX}" | while read -r ds
  do
     echo "Deleting $ds"
     zfs destroy "$ds"
  done

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
  local cfg desc decoded
  local line

  header "Config LXC $VMID"

  # validate VMID
  if [[ -z "$VMID" || ! "$VMID" =~ ^[0-9]+$ ]]; then
    log_error "Invalid or missing VMID"
    return 1
  fi

  # check container exists
  pct status "$VMID" >/dev/null 2>&1 || {
    log_error "Container $VMID not found"
    return 1
  }

  # read config once
  cfg="$(pct config "$VMID")"

  # print everything except description
  while IFS= read -r line; do
    [[ "$line" =~ ^description: ]] && continue
    printf '%s\n' "$line"
  done <<< "$cfg"

  # extract description
  desc="$(sed -n 's/^description: //p' <<< "$cfg")"
  [[ -z "$desc" ]] && return 0

  # decode %XX → characters
  decoded="$(printf '%b' "${desc//%/\\x}")"

  # print header
  printf '\ndescription:\n'

  # print each line (no indent)
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done <<< "$decoded"
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
  $0 start $PCT_RANGE_BEGIN
  $0 create -profile=mail
  $0 profile
  $0 destroy $PCT_RANGE_BEGIN

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

  mkdir -p "$(dirname "$1")"
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
  echo "PCT_NOTESDATA_SIZE_GB=100" >> "$1"
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

  if [ ! -d "$HOME/.dompct" ]; then
    return 0
  fi

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
      pct list | awk -v begin="$PCT_RANGE_BEGIN" -v end="$PCT_RANGE_END" '
      NR > 1 && $1 >= begin && $1 < end {
        printf "%-5s %-8s %s\n", $1, $2, $NF
      }'
    )
  fi

  [ ${#vms[@]} -eq 0 ] && {
    log "No VMID specified & No existing containers found!"
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
  "destroy"
  "quit"
)


OPTIONS_STOPPED=(
  "start"
  "status"
  "about"
  "update"
  "config"
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
      echo
      echo " VMID    :  $VMID"
      echo " Status  :  $LXC_STATUS"
    else
      echo " VMID    :  $VMID"
      echo " Host    :  $PCT_HOSTNAME"
      echo " Profile :  $PCT_PROFILE_NAME"
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

get_free_vmid()
{
    local start=${1:-$PCT_RANGE_BEGIN}

    {
        pct list 2>/dev/null | awk 'NR>1 {print $1}'
        qm list 2>/dev/null  | awk 'NR>1 {print $1}'
    } | sort -n | awk -v start="$start" '
    BEGIN {
        expected = start
        found = 0
    }
    {
        if ($1 < expected)
            next

        if ($1 == expected) {
            expected++
        } else if ($1 > expected) {
            print expected
            found = 1
            exit
        }
    }
    END {
        if (!found)
            print expected
    }'
}

# --- Main logic ---

if [ -z "$PCT_RANGE_BEGIN" ]; then
  PCT_RANGE_BEGIN=800
fi

if [ -z "$PCT_RANGE_END" ]; then
  PCT_RANGE_END=999
fi

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

if [ -n "$VMID" ]; then
  if [ -n "$VM_HOST" ]; then
    log_error_exit "Invalid parameter combination"
  fi

  if qm status "$VMID" >/dev/null 2>&1; then
    log_error_exit "VMID $VMID is a VM instead of a LXC container"
  fi
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

  create)

    if [ -z "$VMID" ]; then
      VMID=$(get_free_vmid $PCT_RANGE_BEGIN)
    fi

    if [ -z "$VMID" ]; then
      log_error_exit "No VMID specified!"
    fi

    if [ -z "$PCT_PROFILE_NAME" ]; then

      menu_profiles

      if [ -n "$PCT_SELECTED_PROFILE_NAME" ]; then
        PCT_PROFILE_NAME="$PCT_SELECTED_PROFILE_NAME"
        PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
      else
        log_error_exit "No Profile specified"
      fi

      PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
    fi
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

# command-line overrides

if [ -n "$PCT_SET_TAGS" ]; then
  PCT_TAGS="$PCT_SET_TAGS"
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

      if [ -z "$PCT_PROFILE_NAME" ]; then
        PCT_PROFILE_NAME="default"
        PCT_CONFIG_FILE="$HOME/.dompct/$PCT_PROFILE_NAME.cfg"
      fi

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
    create_cfg_file "$PCT_CONFIG_FILE" "$PCT_PROFILE_NAME"
    edit_file "$PCT_CONFIG_FILE"
  else
    run_action "$CMD"

    if [ -n "$PCT_SELECTED_PROFILE_NAME" ]; then
      create_cfg_file "$PCT_CONFIG_FILE" "$PCT_PROFILE_NAME"
      edit_file "$PCT_CONFIG_FILE"
    fi
  fi

else

  run_action "$CMD"
fi

exit 0

