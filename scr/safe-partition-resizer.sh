#!/usr/bin/env bash
# neo-safe-partition-resizer.sh -- deliberately narrow, live-media-only resizer
# Version 1.6.0.  It supports exactly the recorded Omarchy GPT partition:
# /dev/sda partition 2, LUKS2 -> single-device Btrfs.  It is intentionally
# not a generic partition editor or an ext4 resizer.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077
export LC_ALL=C LANG=C

VERSION=1.7.0
EXPECTED_MODEL='MTFDDAK128MAY-1AH1ZABHA'
EXPECTED_TRAN='sata'
# Captured by the script's read-only --print-fingerprint mode on this PC.
EXPECTED_SERIAL='14340D0020B8'
EXPECTED_WWN='0x500a07510d0020b8'
# Target identity is deliberately pinned as well as the physical disk.  These
# values came from the recorded Omarchy installation, not from a device name.
EXPECTED_TARGET_NUM='2'
EXPECTED_TARGET_PARTUUID='a0752dcd-4252-430e-8251-77e4c3307941'
EXPECTED_TARGET_FSTYPE='crypto_LUKS'
EXPECTED_TARGET_START='4196352'
MIN_DISK_BYTES=$((100 * 1024 * 1024 * 1024))
MAX_DISK_BYTES=$((140 * 1024 * 1024 * 1024))
SAFETY_MARGIN_BYTES=$((1024 * 1024 * 1024)) # one GiB beyond Btrfs's reported minimum
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
STATE=analysis
CHECKPOINT=0
TX_ACTIVE=0
OPERATION_COMMITTED=0
RECOVERY_WRITES_STARTED=0
ROLLBACK_ATTEMPTED=0
ROLLBACK_STATE=NOT_ATTEMPTED
SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")

TARGET_PART= TARGET_DISK= TARGET_NUM= TARGET_FSTYPE= TARGET_CONTAINER= TARGET_FILESYSTEM= TARGET_UUID= TARGET_PARTUUID=
TARGET_MODEL= TARGET_SERIAL= TARGET_WWN= TARGET_TRAN= TARGET_DISK_BYTES=
TARGET_START= TARGET_SECTORS= TARGET_BYTES= LOGICAL_SECTOR= PHYSICAL_SECTOR= USER_APPARENT_BYTES=
LUKS_UUID= MAP_NAME= MAP_DEV= FS_MOUNT= HOME_SOURCE= SELECTED_USER=
HOME_MOUNT= HOME_MAP_NAME= HOME_MAP_DEV= HOME_LUKS_PART=
IS_LUKS=0 BACKUP_FS_UUID= BACKUP_FS_TYPE= BACKUP_DISK_SERIAL= BACKUP_DISK_SIZE=
BTRFS_UUID=
BACKUP_PART= BACKUP_DISK= BACKUP_MOUNT= BACKUP_CREATED_MOUNT=0 BACKUP_ROOT=
IMAGE= IMAGE_SHA= GPT_BIN= GPT_DUMP= LOGFILE= DIAGFILE=
OLD_PART_SECTORS= NEW_PART_SECTORS= OLD_FS_BYTES= NEW_FS_BYTES= REQUEST_BYTES=
MIN_FS_BYTES= LUKS_OFFSET_SECTORS= LUKS_OFFSET_BYTES= LUKS_SECTOR_BYTES= BTRFS_SECTOR_BYTES= EXT4_BLOCK_SIZE=
OLD_PART_GUID= OLD_PART_TYPE= OLD_PART_NAME= OLD_PART_ATTRS=
EXT4_MIN_BLOCKS=
TRAILING_FREE_BEFORE= BTRFS_STATS_BASELINE=

declare -a LIVE_DISKS=() ELIGIBLE_PARTS=() BACKUP_CANDIDATES=()

die() {
  local msg=$*
  printf '\nREFUSE: %s\n' "$msg" >&2
  if (( TX_ACTIVE )); then
    note "Controlled stop during transaction: $msg"
    collect_diagnostics "controlled-stop"
    rollback_if_safe "controlled stop"
    failure_report "$msg" 1
  elif (( OPERATION_COMMITTED )); then
    printf 'Storage modification may have completed; final post-commit verification failed. Review the report and backup before rebooting.\n' >&2
  elif (( RECOVERY_WRITES_STARTED )); then
    printf 'Recovery writes may have started; do not reboot. Review the recovery log and backup before taking further action.\n' >&2
  else
    printf 'No changes were made.\n' >&2
  fi
  exit 1
}
note() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "${LOGFILE:-/dev/null}"; }
run() { note "+ $*"; "$@" >>"$LOGFILE" 2>&1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"; }
is_uint() { [[ ${1:-} =~ ^[0-9]+$ ]]; }
canon() { readlink -f -- "$1"; }
human() { numfmt --to=iec-i --suffix=B "$1"; }

cleanup() {
  local rc=$?
  set +e
  [[ -n ${FS_MOUNT:-} ]] && findmnt -rn --target "$FS_MOUNT" >/dev/null 2>&1 && umount "$FS_MOUNT"
  [[ -n ${HOME_MOUNT:-} && $HOME_MOUNT != ${FS_MOUNT:-} ]] && findmnt -rn --target "$HOME_MOUNT" >/dev/null 2>&1 && umount "$HOME_MOUNT"
  [[ -n ${MAP_NAME:-} ]] && cryptsetup status "$MAP_NAME" >/dev/null 2>&1 && cryptsetup close "$MAP_NAME"
  [[ -n ${HOME_MAP_NAME:-} ]] && cryptsetup status "$HOME_MAP_NAME" >/dev/null 2>&1 && cryptsetup close "$HOME_MAP_NAME"
  [[ ${BACKUP_CREATED_MOUNT:-0} == 1 && -n ${BACKUP_MOUNT:-} ]] && findmnt -rn --target "$BACKUP_MOUNT" >/dev/null 2>&1 && umount "$BACKUP_MOUNT"
  [[ -n ${FS_MOUNT:-} && -d ${FS_MOUNT:-} ]] && rmdir "$FS_MOUNT" 2>/dev/null
  [[ -n ${HOME_MOUNT:-} && $HOME_MOUNT != ${FS_MOUNT:-} && -d ${HOME_MOUNT:-} ]] && rmdir "$HOME_MOUNT" 2>/dev/null
  [[ ${BACKUP_CREATED_MOUNT:-0} == 1 && -n ${BACKUP_MOUNT:-} && -d ${BACKUP_MOUNT:-} ]] && rmdir "$BACKUP_MOUNT" 2>/dev/null
  return "$rc"
}

on_signal() {
  trap - INT TERM
  if (( TX_ACTIVE )); then
    note "SIGNAL received during destructive transaction; forward work stopped at checkpoint $CHECKPOINT."
    collect_diagnostics "signal"
    rollback_if_safe "interrupted by signal"
    failure_report "Interrupted by signal" 130
  fi
  exit 130
}

on_error() {
  local rc=$? line=$1 cmd=$2
  trap - ERR
  if (( TX_ACTIVE )); then
    note "FAILED rc=$rc line=$line command=$cmd checkpoint=$CHECKPOINT"
    collect_diagnostics "failure"
    rollback_if_safe "command failure"
    failure_report "$cmd" "$rc"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap on_signal INT TERM
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require_root_and_tools() {
  (( EUID == 0 )) || die "Run this program as root from a Live USB."
  local c
  for c in lsblk blkid findmnt blockdev sfdisk sgdisk parted partprobe partx udevadm cryptsetup btrfs mount umount sha256sum dd awk sed grep sort uniq flock numfmt jq df stat wc find mktemp sync dmsetup readlink du tar xargs basename dirname tr tail cat rm cp diff touch date tee; do need "$c"; done
}

verify_gpt_integrity() {
  local context=${1:-GPT} output
  if ! output=$(sgdisk -v "$TARGET_DISK" 2>&1); then
    die "$context verification command failed: $output"
  fi
  grep -qi 'No problems found' <<<"$output" || die "$context integrity validation failed: $output"
}

print_fingerprint() {
  printf 'Read-only disk fingerprint candidates:\n'
  lsblk -d -o PATH,MODEL,SERIAL,WWN,TRAN,SIZE,PTTYPE
  printf '\nThe destructive path requires exact MODEL, SERIAL, WWN, TRAN, size range, and GPT matches.\n'
}

# Return physical disks beneath a block device / mapper device.  This is used
# only for exclusions; failure to resolve means the candidate is not trusted.
ancestor_disks() {
  local dev=$1 base pk slave
  dev=$(canon "$dev" 2>/dev/null || true); [[ -b $dev ]] || return 0
  base=${dev##*/}
  if [[ -d /sys/class/block/$base/slaves ]]; then
    for slave in /sys/class/block/"$base"/slaves/*; do
      [[ -e $slave ]] || continue
      ancestor_disks "/dev/${slave##*/}"
    done
    return 0
  fi
  pk=$(lsblk -ndo PKNAME "$dev" 2>/dev/null || true)
  if [[ -n $pk ]]; then ancestor_disks "/dev/$pk"; else printf '%s\n' "$dev"; fi
}

add_live_disk() { local d; d=$(canon "$1" 2>/dev/null || true); [[ -n $d ]] && LIVE_DISKS+=("$d"); }
array_contains() { local x=$1 y; shift; for y in "$@"; do [[ $x == "$y" ]] && return 0; done; return 1; }

detect_live_environment() {
  local src d marker=0 live_usb=0
  LIVE_DISKS=()
  [[ -e /run/archiso || -e /run/live || -e /cdrom || -e /run/casper ]] && marker=1
  src=$(findmnt -nro SOURCE / 2>/dev/null || true)
  [[ $src == overlay || $src == /dev/loop* || $src == /dev/sr* ]] && marker=1
  while read -r d; do add_live_disk "$d"; done < <(ancestor_disks "$src")
  while read -r src; do
    while read -r d; do add_live_disk "$d"; done < <(ancestor_disks "$src")
  done < <(findmnt -rn -o SOURCE -T /cdrom 2>/dev/null; findmnt -rn -o SOURCE -T /run/live 2>/dev/null; findmnt -rn -o SOURCE -T /run/archiso 2>/dev/null; findmnt -rn -o SOURCE -T /run/archiso/bootmnt 2>/dev/null)
  mapfile -t LIVE_DISKS < <(printf '%s\n' "${LIVE_DISKS[@]:-}" | sed '/^$/d' | sort -u)
  (( marker )) || die "A recognized live/recovery environment was not detected. Boot a Live USB; installed systems are never eligible."
  ((${#LIVE_DISKS[@]})) || die "Could not prove which disk backs the live environment. Refusing to protect against using live media as a backup."
  for d in "${LIVE_DISKS[@]}"; do [[ $(lsblk -ndo TRAN "$d" 2>/dev/null || true) == usb ]] && live_usb=1; done
  (( live_usb )) || die "The detected live medium is not proven to be USB-backed. This tool requires a real Live USB."
}

disk_matches_fingerprint() {
  local disk=$1 model size pttype tran serial wwn
  model=$(lsblk -ndo MODEL "$disk" | sed 's/[[:space:]]*$//')
  size=$(blockdev --getsize64 "$disk")
  pttype=$(lsblk -ndo PTTYPE "$disk")
  tran=$(lsblk -ndo TRAN "$disk" | sed 's/[[:space:]]*$//')
  serial=$(lsblk -ndo SERIAL "$disk" | sed 's/[[:space:]]*$//')
  wwn=$(lsblk -ndo WWN "$disk" | sed 's/[[:space:]]*$//')
  [[ -n $EXPECTED_SERIAL || -n $EXPECTED_WWN ]] || return 1
  [[ -z $EXPECTED_SERIAL || $serial == "$EXPECTED_SERIAL" ]] || return 1
  [[ -z $EXPECTED_WWN || $wwn == "$EXPECTED_WWN" ]] || return 1
  [[ $model == "$EXPECTED_MODEL" ]] && [[ $tran == "$EXPECTED_TRAN" ]] && ((size >= MIN_DISK_BYTES && size <= MAX_DISK_BYTES)) && [[ $pttype == gpt ]]
}

device_uses_partition() {
  local dev=$1 target=$2 base slave
  dev=$(canon "$dev" 2>/dev/null || true)
  [[ $dev == "$target" ]] && return 0
  [[ -b $dev ]] || return 1
  base=${dev##*/}
  for slave in /sys/class/block/"$base"/slaves/*; do
    [[ -e $slave ]] || continue
    device_uses_partition "/dev/${slave##*/}" "$target" && return 0
  done
  return 1
}

partition_active_or_mounted() {
  local p=$1 b src
  b=${p##*/}
  findmnt -rn -S "$p" >/dev/null 2>&1 && return 0
  [[ -d /sys/class/block/$b/holders ]] && compgen -G "/sys/class/block/$b/holders/*" >/dev/null && return 0
  # A mount source can be a mapper whose slave is the target partition.
  while read -r src; do
    device_uses_partition "$src" "$(canon "$p")" && return 0
  done < <(findmnt -rn -o SOURCE)
  return 1
}

discover_targets() {
  local line p typ disk fstype partn partuuid start
  ELIGIBLE_PARTS=()
  while read -r line; do
    p=$(awk '{print $1}' <<<"$line"); typ=$(awk '{print $2}' <<<"$line")
    [[ $typ == part && -b $p ]] || continue
    disk=$(lsblk -ndo PKNAME "$p" 2>/dev/null || true); [[ -n $disk ]] || continue
    disk=/dev/$disk
    array_contains "$(canon "$disk")" "${LIVE_DISKS[@]}" && continue
    disk_matches_fingerprint "$disk" || continue
    partition_active_or_mounted "$p" && continue
    fstype=$(blkid -o value -s TYPE "$p" 2>/dev/null || true)
    partn=$(lsblk -ndo PARTN "$p" 2>/dev/null || true)
    partuuid=$(blkid -o value -s PARTUUID "$p" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    start=$(cat "/sys/class/block/${p##*/}/start" 2>/dev/null || true)
    [[ $fstype == "$EXPECTED_TARGET_FSTYPE" ]] || continue
    [[ $partn == "$EXPECTED_TARGET_NUM" ]] || continue
    [[ $partuuid == "$EXPECTED_TARGET_PARTUUID" ]] || continue
    [[ $start == "$EXPECTED_TARGET_START" ]] || continue
    ELIGIBLE_PARTS+=("$(canon "$p")")
  done < <(lsblk -nrpo PATH,TYPE)
  ((${#ELIGIBLE_PARTS[@]} == 1)) || die "The exact recorded Omarchy target (partition $EXPECTED_TARGET_NUM / PARTUUID $EXPECTED_TARGET_PARTUUID) was not uniquely found on the verified internal disk."
}

describe_target() {
  local p=$1 type map tmp min usage
  printf '   %s\n   Size: %s\n   PARTUUID: %s\n' "$p" "$(human "$(blockdev --getsize64 "$p")")" "$(blkid -o value -s PARTUUID "$p" 2>/dev/null || echo unknown)"
  type=$(blkid -o value -s TYPE "$p" 2>/dev/null || true)
  printf '   Encryption: LUKS2 -> single-device Btrfs (opening is deferred until after selection)\n'
  cryptsetup isLuks --type luks2 "$p" || die "$p identifies as crypto_LUKS but is not valid LUKS2"
}

select_target() {
  discover_targets
  printf '\nNEO PARTITION RESIZER\n\nVerified exact recorded Omarchy target (selected automatically):\n\n'
  describe_target "${ELIGIBLE_PARTS[0]}"
  TARGET_PART=${ELIGIBLE_PARTS[0]}
  TARGET_DISK=/dev/$(lsblk -ndo PKNAME "$TARGET_PART")
  disk_matches_fingerprint "$TARGET_DISK" || die "Target disk fingerprint changed or is not this Omarchy disk"
  TARGET_MODEL=$(lsblk -ndo MODEL "$TARGET_DISK" | sed 's/[[:space:]]*$//')
  TARGET_SERIAL=$(lsblk -ndo SERIAL "$TARGET_DISK" | sed 's/[[:space:]]*$//')
  TARGET_WWN=$(lsblk -ndo WWN "$TARGET_DISK" | sed 's/[[:space:]]*$//')
  TARGET_TRAN=$(lsblk -ndo TRAN "$TARGET_DISK" | sed 's/[[:space:]]*$//')
  TARGET_DISK_BYTES=$(blockdev --getsize64 "$TARGET_DISK")
  partition_active_or_mounted "$TARGET_PART" && die $'TARGET IS CURRENTLY IN USE\n\nThe selected partition belongs to the currently running operating system or has active holders. Boot from a Live USB and run this program again.'
  TARGET_FSTYPE=$(blkid -o value -s TYPE "$TARGET_PART")
  [[ $TARGET_FSTYPE == "$EXPECTED_TARGET_FSTYPE" ]] || die "Target container type does not match recorded Omarchy target"
  TARGET_CONTAINER=crypto_LUKS; TARGET_FILESYSTEM=unknown; IS_LUKS=1
  TARGET_UUID=$(blkid -o value -s UUID "$TARGET_PART" 2>/dev/null || true)
  TARGET_PARTUUID=$(blkid -o value -s PARTUUID "$TARGET_PART")
  TARGET_NUM=$(lsblk -ndo PARTN "$TARGET_PART")
  LOGICAL_SECTOR=$(blockdev --getss "$TARGET_DISK")
  PHYSICAL_SECTOR=$(blockdev --getpbsz "$TARGET_DISK")
  TARGET_START=$(cat "/sys/class/block/${TARGET_PART##*/}/start")
  TARGET_SECTORS=$(cat "/sys/class/block/${TARGET_PART##*/}/size")
  TARGET_BYTES=$(blockdev --getsize64 "$TARGET_PART")
  OLD_PART_SECTORS=$TARGET_SECTORS
  [[ $TARGET_NUM == "$EXPECTED_TARGET_NUM" ]] || die "Target partition number does not match recorded target"
  [[ ${TARGET_PARTUUID,,} == "$EXPECTED_TARGET_PARTUUID" ]] || die "Target PARTUUID does not match recorded target"
  [[ $TARGET_START == "$EXPECTED_TARGET_START" ]] || die "Target start sector does not match recorded target"
  [[ $((TARGET_SECTORS * LOGICAL_SECTOR)) == "$TARGET_BYTES" ]] || die "Kernel partition geometry is inconsistent"
  verify_gpt_integrity 'Pre-operation GPT'
}

disk_of() { /dev/$(lsblk -ndo PKNAME "$1" 2>/dev/null); }
is_safe_backup_partition() {
  local p=$1 d type
  d=$(disk_of "$p")
  [[ -b $p && $d != "$TARGET_DISK" ]] || return 1
  array_contains "$(canon "$d")" "${LIVE_DISKS[@]}" && return 1
  type=$(blkid -o value -s TYPE "$p" 2>/dev/null || true)
  [[ $type =~ ^(ext4|exfat|ntfs|xfs|btrfs)$ ]] || return 1
  # A pre-mounted removable filesystem is allowed only if it is not any live
  # root/media mount.  It must still be writable when selected.
  local mp
  mp=$(findmnt -rn -S "$p" -o TARGET 2>/dev/null || true)
  if [[ -n $mp ]]; then
    [[ $mp == / || $mp == /cdrom || $mp == /run/live* || $mp == /run/archiso* || $mp == /run/casper* ]] && return 1
  fi
  return 0
}

find_backup_candidates() {
  local p typ tran d
  BACKUP_CANDIDATES=()
  while read -r p typ; do
    [[ $typ == part && -b $p ]] || continue
    d=$(disk_of "$p"); tran=$(lsblk -ndo TRAN "$d" 2>/dev/null || true)
    [[ $tran == usb ]] || continue
    is_safe_backup_partition "$p" && BACKUP_CANDIDATES+=("$(canon "$p")")
  done < <(lsblk -nrpo PATH,TYPE)
}

mount_backup() {
  local p=$1 existing
  BACKUP_PART=$p; BACKUP_DISK=$(disk_of "$p")
  BACKUP_FS_UUID=$(blkid -o value -s UUID "$p")
  BACKUP_FS_TYPE=$(blkid -o value -s TYPE "$p")
  BACKUP_DISK_SERIAL=$(lsblk -ndo SERIAL "$BACKUP_DISK" | sed 's/[[:space:]]*$//')
  BACKUP_DISK_SIZE=$(blockdev --getsize64 "$BACKUP_DISK")
  existing=$(findmnt -rn -S "$p" -o TARGET 2>/dev/null || true)
  if [[ -n $existing ]]; then
    BACKUP_MOUNT=$existing
  else
    BACKUP_MOUNT=$(mktemp -d /mnt/neo-resizer-backup.XXXXXX)
    mount -o rw,nosuid,nodev "$p" "$BACKUP_MOUNT"
    BACKUP_CREATED_MOUNT=1
  fi
  [[ -w $BACKUP_MOUNT ]] || die "Backup filesystem is not writable: $BACKUP_MOUNT"
  touch "$BACKUP_MOUNT/.neo-resizer-write-test" && rm -f "$BACKUP_MOUNT/.neo-resizer-write-test"
}

verify_backup_mount_identity() {
  local mounted_source tran
  [[ $(blkid -o value -s UUID "$BACKUP_PART" 2>/dev/null || true) == "$BACKUP_FS_UUID" ]] || die "Backup USB filesystem identity changed"
  [[ $(blkid -o value -s TYPE "$BACKUP_PART" 2>/dev/null || true) == "$BACKUP_FS_TYPE" ]] || die "Backup USB filesystem type changed"
  [[ $(blockdev --getsize64 "$BACKUP_DISK") == "$BACKUP_DISK_SIZE" ]] || die "Backup USB disk size changed"
  [[ -z $BACKUP_DISK_SERIAL || $(lsblk -ndo SERIAL "$BACKUP_DISK" | sed 's/[[:space:]]*$//') == "$BACKUP_DISK_SERIAL" ]] || die "Backup USB disk serial changed"
  mounted_source=$(findmnt -rn -S "$BACKUP_PART" -o TARGET 2>/dev/null || true)
  [[ $mounted_source == "$BACKUP_MOUNT" ]] || die "Backup mount no longer belongs to the selected backup partition"
  tran=$(lsblk -ndo TRAN "$BACKUP_DISK" | sed 's/[[:space:]]*$//')
  [[ $tran == usb ]] || die "Backup disk is no longer USB transport"
  array_contains "$(canon "$BACKUP_DISK")" "${LIVE_DISKS[@]}" && die "Backup disk now resolves to live media"
}

verify_backup_identity() {
  verify_backup_mount_identity
  [[ -w $BACKUP_MOUNT ]] || die "Backup USB is no longer writable"
}

verify_target_identity() {
  [[ $(lsblk -ndo MODEL "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$TARGET_MODEL" ]] || die "Target disk model changed"
  [[ $(lsblk -ndo SERIAL "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$TARGET_SERIAL" ]] || die "Target disk serial changed"
  [[ $(lsblk -ndo WWN "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$TARGET_WWN" ]] || die "Target disk WWN changed"
  [[ $(lsblk -ndo TRAN "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$TARGET_TRAN" ]] || die "Target disk transport changed"
  [[ $(blockdev --getsize64 "$TARGET_DISK") == "$TARGET_DISK_BYTES" ]] || die "Target disk capacity changed"
}

normalized_partition_layout() {
  local disk=$1 json num info type guid name attrs node start size
  json=$(mktemp /tmp/neo-resizer-layout.XXXXXX)
  sfdisk --json "$disk" >"$json"
  while IFS=$'\t' read -r node start size; do
    num=$(lsblk -ndo PARTN "$node")
    info=$(sgdisk -i "$num" "$disk")
    type=$(awk -F: '/Partition GUID code/{print $2}' <<<"$info" | awk '{print $1}')
    guid=$(awk -F: '/Partition unique GUID/{gsub(/^[[:space:]]+/,"",$2);print $2}' <<<"$info")
    name=$(awk -F: '/Partition name/{sub(/^[[:space:]]*/,"",$2);gsub(/\047/,"",$2);print $2}' <<<"$info")
    attrs=$(awk -F: '/Attribute flags/{gsub(/^[[:space:]]+/,"",$2);print $2}' <<<"$info")
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$num" "$start" "$size" "$type" "$guid" "$name" "$attrs"
  done < <(jq -r '.partitiontable.partitions[] | [.node,.start,.size] | @tsv' "$json" | sort -V)
  rm -f "$json"
}

verify_layout_only_target_changed() {
  local before=$BACKUP_ROOT/metadata/partition-layout-before.txt after target_before target_after expected
  before=$BACKUP_ROOT/metadata/partition-layout-before.txt
  after=$(mktemp /tmp/neo-resizer-layout-after.XXXXXX)
  normalized_partition_layout "$TARGET_DISK" >"$after"
  diff -u <(grep -v "^$TARGET_NUM|" "$before") <(grep -v "^$TARGET_NUM|" "$after") >/dev/null || { rm -f "$after"; die "An unrelated partition identity or geometry changed unexpectedly"; }
  target_before=$(grep "^$TARGET_NUM|" "$before")
  target_after=$(grep "^$TARGET_NUM|" "$after")
  expected=$(awk -F'|' -v n="$TARGET_NUM" -v s="$NEW_PART_SECTORS" 'BEGIN{OFS="|"} $1==n {$3=s; print}' "$before")
  [[ $target_after == "$expected" ]] || { rm -f "$after"; die "Target partition changed by more than the planned end boundary"; }
  cp "$after" "$BACKUP_ROOT/metadata/partition-layout-after.txt"
  rm -f "$after"
}

select_backup() {
  local a i
  while :; do
    udevadm settle
    find_backup_candidates
    if ((${#BACKUP_CANDIDATES[@]} == 0)); then
      read -r -p $'\nNo suitable non-live USB backup partition detected. Insert one, then press Enter to rescan. ' _
      continue
    fi
    printf '\nSafe USB backup partitions (live USB and target disk are excluded):\n'
    for i in "${!BACKUP_CANDIDATES[@]}"; do
      printf '%d. %s  filesystem=%s  capacity=%s  transport=USB\n' "$((i+1))" "${BACKUP_CANDIDATES[i]}" "$(blkid -o value -s TYPE "${BACKUP_CANDIDATES[i]}")" "$(human "$(blockdev --getsize64 "${BACKUP_CANDIDATES[i]}")")"
    done
    if ((${#BACKUP_CANDIDATES[@]} == 1)); then a=1; read -r -p 'One safe candidate detected. Press Enter to use it, or type q to stop: ' _; else read -r -p 'Select backup USB partition: ' a; fi
    [[ ${_:-} == q ]] && die "Stopped by user"
    is_uint "$a" && ((a >= 1 && a <= ${#BACKUP_CANDIDATES[@]})) || { printf 'Invalid selection.\n'; continue; }
    mount_backup "${BACKUP_CANDIDATES[a-1]}"
    return
  done
}

open_luks() {
  local mode=${1:-rw}
  (( IS_LUKS )) || return 0
  cryptsetup isLuks --type luks2 "$TARGET_PART" || die "Selected LUKS partition is not LUKS2"
  LUKS_UUID=$(cryptsetup luksUUID "$TARGET_PART")
  MAP_NAME="neo-resizer-${LUKS_UUID//-/}"
  MAP_NAME=${MAP_NAME:0:60}
  MAP_DEV=/dev/mapper/$MAP_NAME
  [[ ! -e $MAP_DEV ]] || die "Temporary LUKS mapper name already exists: $MAP_NAME"
  printf '\nOpening LUKS2 container. Enter its passphrase only at cryptsetup prompt.\n'
  if [[ $mode == ro ]]; then cryptsetup open --readonly "$TARGET_PART" "$MAP_NAME"; else cryptsetup open "$TARGET_PART" "$MAP_NAME"; fi
  cryptsetup status "$MAP_NAME" >/dev/null
}

mount_filesystem_ro_for_discovery() {
  local dev
  FS_MOUNT=$(mktemp -d /mnt/neo-resizer-fs.XXXXXX)
  dev=$MAP_DEV
  blkid -o value -s TYPE "$dev" | grep -qx btrfs || die "Recorded LUKS2 payload is not Btrfs"
  mount -o ro,subvolid=5 "$dev" "$FS_MOUNT"
  TARGET_FILESYSTEM=btrfs
  HOME_MOUNT=$FS_MOUNT
}

select_user() {
  local -a homes=() users=() paths=(); local d i a
  [[ -n ${HOME_MOUNT:-} ]] || die "No Omarchy home source is mounted"
  [[ -d $HOME_MOUNT/home ]] && homes+=("$HOME_MOUNT/home")
  [[ -d $HOME_MOUNT/@home ]] && homes+=("$HOME_MOUNT/@home")
  for d in "${homes[@]:-}"; do
    while read -r -d '' p; do users+=("${p##*/}"); paths+=("$p"); done < <(find "$d" -mindepth 1 -maxdepth 1 -type d -print0)
  done
  ((${#users[@]})) || die "No user home directories were found in the selected installation"
  printf '\nUsers detected in selected installation:\n'
  for i in "${!users[@]}"; do printf '%d. %s (%s)\n' "$((i+1))" "${users[i]}" "${paths[i]}"; done
  read -r -p 'Select user to back up: ' a
  is_uint "$a" && ((a >= 1 && a <= ${#users[@]})) || die "Invalid user selection"
  SELECTED_USER=${users[a-1]}; HOME_SOURCE=${paths[a-1]}
  USER_APPARENT_BYTES=$(du -sb --apparent-size "$HOME_SOURCE" | awk '{print $1}')
  is_uint "$USER_APPARENT_BYTES" || die "Cannot measure selected home directory"
}

collect_diagnostics() {
  local tag=${1:-state} out=${DIAGFILE:-/tmp/neo-resizer-${RUN_ID}-${tag}.txt}
  ( set +e
    echo "===== $tag $(date -Is) ====="; uname -a; echo
    echo '===== lsblk ====='; lsblk -e7 -o NAME,PATH,MAJ:MIN,SIZE,TYPE,TRAN,MODEL,SERIAL,PTTYPE,PARTN,PARTUUID,FSTYPE,FSVER,UUID,MOUNTPOINTS; echo
    echo '===== blkid ====='; blkid; echo
    echo '===== findmnt ====='; findmnt; echo
    echo '===== GPT ====='; sfdisk --dump "$TARGET_DISK"; sgdisk -p "$TARGET_DISK"; sgdisk -i "$TARGET_NUM" "$TARGET_DISK"; echo
    echo '===== kernel geometry ====='; cat "/sys/class/block/${TARGET_PART##*/}/start"; cat "/sys/class/block/${TARGET_PART##*/}/size"; echo
    echo '===== dm tree ====='; dmsetup ls --tree 2>&1 || true; echo
    [[ -n ${MAP_NAME:-} ]] && cryptsetup status "$MAP_NAME" 2>&1 || true
    [[ ${TARGET_FILESYSTEM:-} == btrfs && -n ${MAP_DEV:-} && -b ${MAP_DEV:-} ]] && { btrfs filesystem show "$MAP_DEV" 2>&1; btrfs device stats "$MAP_DEV" 2>&1; btrfs inspect-internal dump-super -f "$MAP_DEV" 2>&1; }
    [[ ${TARGET_FILESYSTEM:-} == btrfs && -n ${FS_MOUNT:-} ]] && findmnt -rn --target "$FS_MOUNT" >/dev/null 2>&1 && btrfs filesystem usage "$FS_MOUNT" 2>&1
    dmesg | tail -n 250 || true
  ) | tee "$out" >>"${LOGFILE:-/dev/null}" 2>&1
  return 0
}

backup_metadata() {
  local md=$BACKUP_ROOT/metadata backup_luks_uuid= backup_btrfs_uuid= backup_btrfs_bytes=
  mkdir -p "$md" "$BACKUP_ROOT/logs" "$BACKUP_ROOT/rollback" "$BACKUP_ROOT/user-backup"
  LOGFILE=$BACKUP_ROOT/logs/operation.log; DIAGFILE=$BACKUP_ROOT/logs/diagnostics-before.txt
  note "neo safe partition resizer version $VERSION run=$RUN_ID"
  run sgdisk --backup="$md/gpt-before.bin" "$TARGET_DISK"
  run sfdisk --dump "$TARGET_DISK"
  sfdisk --dump "$TARGET_DISK" >"$md/gpt-before.sfdisk"
  normalized_partition_layout "$TARGET_DISK" >"$md/partition-layout-before.txt"
  lsblk -J -O >"$md/lsblk-before.json"; blkid -o full >"$md/blkid-before.txt"; findmnt -J >"$md/findmnt-before.json"
  backup_luks_uuid=$(cryptsetup luksUUID "$TARGET_PART")
  backup_btrfs_uuid=$(btrfs_uuid)
  backup_btrfs_bytes=$(btrfs_device_bytes)
  { echo "disk=$TARGET_DISK"; echo "model=$TARGET_MODEL"; echo "serial=$TARGET_SERIAL"; echo "wwn=$TARGET_WWN"; echo "tran=$TARGET_TRAN"; echo "disk_bytes=$TARGET_DISK_BYTES"; echo "logical_sector=$LOGICAL_SECTOR"; echo "physical_sector=$PHYSICAL_SECTOR"; echo "target=$TARGET_PART"; echo "target_num=$TARGET_NUM"; echo "start=$TARGET_START"; echo "sectors=$TARGET_SECTORS"; echo "partuuid=$TARGET_PARTUUID"; echo "luks_uuid=$backup_luks_uuid"; echo "btrfs_uuid=$backup_btrfs_uuid"; echo "btrfs_device_bytes=$backup_btrfs_bytes"; } >"$md/identity-before.env"
  sgdisk -i "$TARGET_NUM" "$TARGET_DISK" >"$md/partition-before.txt"
  run cryptsetup luksHeaderBackup "$TARGET_PART" --header-backup-file "$md/luks-header.img"
  cryptsetup luksDump --dump-json-metadata "$TARGET_PART" >"$md/luks-metadata.json"
  cryptsetup luksDump "$TARGET_PART" >"$md/luks-dump.txt"
  cryptsetup status "$MAP_NAME" >"$md/luks-status.txt"
  btrfs inspect-internal dump-super -f "$MAP_DEV" >"$md/btrfs-super-before.txt"
  btrfs filesystem show "$MAP_DEV" >"$md/btrfs-show-before.txt"
  btrfs filesystem usage "$FS_MOUNT" >"$md/btrfs-usage-before.txt"
  collect_diagnostics before
}

write_recovery_tool() {
  local rdir=$BACKUP_ROOT/recovery
  mkdir -p "$rdir"
  cp -- "$SCRIPT_PATH" "$rdir/neo-resize-recovery.sh"
  printf '%s\n' \
    'Emergency recovery tool generated by neo-safe-partition-resizer.' \
    '' \
    'Use only from a Live USB. It restores the pre-operation GPT and complete partition image.' \
    'It cannot run automatically after power loss, kernel panic, or unplugging media.' \
    '' \
    "Command: sudo bash ./neo-resize-recovery.sh --recover --backup-root '$BACKUP_ROOT' --disk '$TARGET_DISK' --partition '$TARGET_PART'" \
    'The tool requires exact disk identity matches and an explicit RECOVER confirmation.' >"$rdir/README.txt"
}

copy_user_backup() {
  local archive=$BACKUP_ROOT/user-backup/$SELECTED_USER.tar before files
  before=$(du -sb --apparent-size "$HOME_SOURCE" | awk '{print $1}')
  note "Backing up $HOME_SOURCE apparent bytes=$before"
  # A POSIX tar archive retains Linux metadata even if the removable USB is
  # exFAT/NTFS; it does not follow symlinks outside the home directory.
  tar --create --file="$archive" --acls --xattrs --xattrs-include='*' --numeric-owner --sparse \
    --directory="$(dirname "$HOME_SOURCE")" -- "$SELECTED_USER"
  tar --compare --file="$archive" --acls --xattrs --xattrs-include='*' --numeric-owner \
    --directory="$(dirname "$HOME_SOURCE")" -- "$SELECTED_USER" >"$BACKUP_ROOT/logs/user-backup-verify.log"
  [[ -s $archive ]] || die "User backup archive was not created"
  files=$(find "$HOME_SOURCE" -xdev -printf . | wc -c)
  printf 'source_apparent_bytes=%s\narchive_bytes=%s\nfiles=%s\nverification=tar-compare-ok\n' "$before" "$(stat -c %s "$archive")" "$files" >"$BACKUP_ROOT/user-backup/verification.txt"
}

verify_backup_capacity_preflight() {
  local free required
  # Before writing any backup artifact, reserve room for both the complete
  # encrypted partition image and an uncompressed upper bound for the selected
  # home archive, plus metadata/headroom.  The later image check uses actual
  # remaining space again after the archive has been verified.
  free=$(df -B1 --output=avail "$BACKUP_MOUNT" | tail -1 | tr -d ' ')
  is_uint "$free" && is_uint "$USER_APPARENT_BYTES" || die "Cannot determine backup USB free space or selected-home size"
  required=$((TARGET_BYTES + USER_APPARENT_BYTES + 1024 * 1024 * 1024))
  (( free >= required )) || die "Backup USB capacity is insufficient before backup: available $(human "$free"); required at least $(human "$required") for the full verified partition image, selected home, and safety headroom. Use a larger external USB."
  printf '\nBACKUP CAPACITY PREFLIGHT\nAvailable: %s\nRequired minimum: %s\nRollback image: %s\nSelected home (apparent): %s\nResult: [ OK ]\n' \
    "$(human "$free")" "$(human "$required")" "$(human "$TARGET_BYTES")" "$(human "$USER_APPARENT_BYTES")"
}

check_capacity_and_create_image() {
  local free image_bytes
  free=$(df -B1 --output=avail "$BACKUP_MOUNT" | tail -1 | tr -d ' ')
  # The complete user backup has already been written and verified.  Remaining
  # free space must now hold the full raw image plus metadata headroom.
  image_bytes=$TARGET_BYTES
  (( free >= image_bytes + 512*1024*1024 )) || die "Backup USB free space ($(human "$free")) is insufficient for the required raw rollback image ($(human "$image_bytes")); the user backup already occupies space on this USB. No destructive operation is allowed."
  IMAGE=$BACKUP_ROOT/rollback/target-partition-before.img
  note "Creating raw rollback image. This may take a long time."
  dd if="$TARGET_PART" of="$IMAGE" bs=16M iflag=fullblock status=progress conv=fsync
  [[ $(stat -c %s "$IMAGE") == "$TARGET_BYTES" ]] || die "Rollback image byte length does not equal source partition"
  IMAGE_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
  printf '%s  rollback/target-partition-before.img\n' "$IMAGE_SHA" >"$BACKUP_ROOT/rollback/image.sha256"
  (cd "$BACKUP_ROOT" && sha256sum metadata/gpt-before.bin >rollback/gpt-before.sha256)
  printf 'source_partition=%s\nsource_partition_bytes=%s\nimage_bytes=%s\nsource_image_sha256=%s\n' "$TARGET_PART" "$TARGET_BYTES" "$(stat -c %s "$IMAGE")" "$IMAGE_SHA" >"$BACKUP_ROOT/rollback/image-audit.txt"
}

verify_backup_set() {
  local req
  verify_backup_identity
  for req in "$BACKUP_ROOT/metadata/gpt-before.bin" "$BACKUP_ROOT/metadata/gpt-before.sfdisk" "$BACKUP_ROOT/metadata/identity-before.env" "$BACKUP_ROOT/user-backup/$SELECTED_USER.tar" "$IMAGE"; do [[ -e $req ]] || die "Required backup artifact missing: $req"; done
  [[ -s $BACKUP_ROOT/metadata/luks-header.img ]] || die "LUKS header backup missing"
  (cd "$BACKUP_ROOT" && sha256sum -c rollback/image.sha256 >/dev/null) || die "Rollback image checksum failed"
  (cd "$BACKUP_ROOT" && sha256sum -c rollback/gpt-before.sha256 >/dev/null) || die "GPT backup checksum failed"
  # Logs are deliberately excluded: they remain mutable during the operation.
  (cd "$BACKUP_ROOT" && find metadata rollback user-backup -type f ! -name '*.sha256' -print0 | sort -z | xargs -0 sha256sum >backup-artifacts.sha256)
  (cd "$BACKUP_ROOT" && sha256sum -c backup-artifacts.sha256 >/dev/null)
  printf '\nBACKUP VALIDATION\nUser backup              [ OK ]\nGPT backup               [ OK ]\nLUKS header backup       [ OK ]\nPartition metadata       [ OK ]\nRollback image           [ OK ]\nChecksums                [ OK ]\nRollback protection: READY\n'
  CHECKPOINT=1
}

parse_size() {
  # Only exact binary units are accepted.  The result is bytes, never a
  # rounded human number.  Decimal fractions and bare numbers are forbidden.
  local v=$1 n unit max_n
  [[ $v =~ ^([0-9]+)[[:space:]]*(MiB|GiB|TiB)$ ]] || return 1
  n=${BASH_REMATCH[1]}; unit=${BASH_REMATCH[2]}
  case $unit in
    MiB) max_n=$((TARGET_BYTES / 1024 / 1024)); (( n > 0 && n <= max_n )) || return 1; printf '%s\n' "$((n * 1024 * 1024))" ;;
    GiB) max_n=$((TARGET_BYTES / 1024 / 1024 / 1024)); (( n > 0 && n <= max_n )) || return 1; printf '%s\n' "$((n * 1024 * 1024 * 1024))" ;;
    TiB) max_n=$((TARGET_BYTES / 1024 / 1024 / 1024 / 1024)); (( n > 0 && n <= max_n )) || return 1; printf '%s\n' "$((n * 1024 * 1024 * 1024 * 1024))" ;;
  esac
}

partition_fields() {
  local json=$1
  jq -er --arg p "$TARGET_PART" '.partitiontable.partitions[] | select(.node == $p) | [.start,.size] | @tsv' "$json"
}

load_partition_attributes() {
  local info
  info=$(sgdisk -i "$TARGET_NUM" "$TARGET_DISK")
  OLD_PART_GUID=$(awk -F: '/Partition unique GUID/{gsub(/^[[:space:]]+/,"",$2); print $2}' <<<"$info")
  OLD_PART_TYPE=$(awk -F: '/Partition GUID code/{print $2}' <<<"$info" | awk '{print $1}')
  OLD_PART_NAME=$(awk -F: '/Partition name/{sub(/^[[:space:]]*/,"",$2); gsub(/\047/,"",$2); print $2}' <<<"$info")
  OLD_PART_ATTRS=$(awk -F: '/Attribute flags/{gsub(/^[[:space:]]+/,"",$2); print $2}' <<<"$info")
  [[ -n $OLD_PART_GUID && -n $OLD_PART_TYPE ]] || die "Could not record GPT partition identity"
}

read_luks_geometry() {
  local map_bytes part_bytes metadata offset_bytes segment_size status_offset expected_map
  metadata=$(cryptsetup luksDump --dump-json-metadata "$TARGET_PART")
  offset_bytes=$(jq -er '[.segments[] | select(.type == "crypt") | select(.size == "dynamic") | .offset | tonumber] | if length == 1 then .[0] else error("expected one dynamic crypt segment") end' <<<"$metadata") || die "LUKS2 metadata does not describe exactly one dynamic crypt data segment"
  segment_size=$(jq -r '[.segments[] | select(.type == "crypt") | .size] | join(",")' <<<"$metadata")
  is_uint "$offset_bytes" && (( offset_bytes > 0 )) || die "Invalid LUKS2 JSON payload offset"
  [[ $segment_size == dynamic ]] || die "Only a dynamic-size LUKS2 data segment is supported"
  LUKS_OFFSET_BYTES=$offset_bytes
  (( LUKS_OFFSET_BYTES % LOGICAL_SECTOR == 0 )) || die "LUKS payload offset is not aligned to the disk logical sector"
  LUKS_OFFSET_SECTORS=$((LUKS_OFFSET_BYTES / LOGICAL_SECTOR))
  status_offset=$(cryptsetup luksDump "$TARGET_PART" | awk '/offset:/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/){print $i; exit}}')
  [[ $status_offset == "$offset_bytes" ]] || die "LUKS JSON payload offset disagrees with cryptsetup data-segment report"
  LUKS_SECTOR_BYTES=$(jq -er '[.segments[] | select(.type == "crypt") | .sector_size] | unique | if length == 1 then .[0] else error("sector size") end' <<<"$metadata") || die "Cannot read LUKS2 data-segment sector size"
  is_uint "$LUKS_SECTOR_BYTES" || die "Invalid LUKS sector size"
  [[ $(cryptsetup status "$MAP_NAME" | awk -F: '/sector size/{gsub(/[^0-9]/,"",$2);print $2;exit}') == "$LUKS_SECTOR_BYTES" ]] || die "Active LUKS mapping sector size disagrees with LUKS2 metadata"
  map_bytes=$(blockdev --getsize64 "$MAP_DEV")
  part_bytes=$(blockdev --getsize64 "$TARGET_PART")
  expected_map=$((part_bytes - LUKS_OFFSET_BYTES))
  (( expected_map > 0 )) || die "LUKS payload offset exceeds the partition"
  [[ $map_bytes == "$expected_map" ]] || die "LUKS mapper size does not equal partition size minus metadata payload offset"
  (( expected_map % LUKS_SECTOR_BYTES == 0 )) || die "Current LUKS mapping is not sector aligned"
}

btrfs_device_bytes() {
  btrfs inspect-internal dump-super -f "$MAP_DEV" | awk '$1 == "dev_item.total_bytes" {gsub(/[^0-9]/,"",$2); print $2; exit}'
}

btrfs_sector_bytes() { btrfs inspect-internal dump-super -f "$MAP_DEV" | awk '$1 == "sectorsize" {gsub(/[^0-9]/,"",$2); print $2; exit}'; }

verify_single_btrfs_device() {
  local devices devid
  devices=$(btrfs inspect-internal dump-super -f "$MAP_DEV" | awk '$1 == "num_devices" {print $2; exit}')
  devid=$(btrfs inspect-internal dump-super -f "$MAP_DEV" | awk '$1 == "dev_item.devid" {print $2; exit}')
  BTRFS_SECTOR_BYTES=$(btrfs_sector_bytes)
  [[ $devices == 1 && $devid == 1 ]] || die "Only a single-device Btrfs filesystem with devid 1 is supported"
  is_uint "$BTRFS_SECTOR_BYTES" || die "Cannot read Btrfs sector size"
  (( BTRFS_SECTOR_BYTES % LUKS_SECTOR_BYTES == 0 )) || die "Btrfs and LUKS sector sizes are incompatible"
}

btrfs_uuid() { btrfs filesystem show "$MAP_DEV" | awk '/uuid:/{for(i=1;i<=NF;i++) if($i=="uuid:"){print $(i+1); exit}}'; }

btrfs_stats_values() {
  btrfs device stats "$MAP_DEV" | awk '
    /(write_io_errs|read_io_errs|flush_io_errs|corruption_errs|generation_errs)/ {
      key=$1; sub(/^.*\./, "", key); sub(/:$/, "", key)
      value=$NF; gsub(/[^0-9]/, "", value)
      if (value !~ /^[0-9]+$/) exit 2
      print key "=" value
    }' | sort
}

verify_btrfs_stats_schema() {
  local expected=$'corruption_errs\nflush_io_errs\ngeneration_errs\nread_io_errs\nwrite_io_errs' actual
  actual=$(awk -F= '{print $1}' <<<"$BTRFS_STATS_BASELINE" | sort)
  [[ $actual == "$expected" ]] || die "Btrfs device statistics did not contain exactly the five required error counters"
}

minimum_btrfs_bytes() {
  local out n
  out=$(btrfs inspect-internal min-dev-size --id 1 "$MAP_DEV" 2>&1) || die "btrfs inspect-internal min-dev-size failed; this system cannot prove a safe shrink minimum"
  n=$(awk -F: '/min_dev_size/ {gsub(/[^0-9]/,"",$2); print $2; exit}' <<<"$out")
  is_uint "$n" && ((n > 0)) || die "Could not parse Btrfs minimum device size: $out"
  printf '%s\n' "$n"
}

preflight_filesystem_integrity() {
  btrfs check --readonly "$MAP_DEV"
  [[ $(btrfs_device_bytes) == "$OLD_FS_BYTES" ]] || die "Btrfs device geometry changed during preflight"
  BTRFS_STATS_BASELINE=$(btrfs_stats_values)
  [[ $(wc -l <<<"$BTRFS_STATS_BASELINE") == 5 ]] || die "Could not record all five Btrfs device error counters"
  verify_btrfs_stats_schema
}

trailing_free_sectors() {
  local json=$1 current_end boundary first lastlba
  current_end=$((TARGET_START + TARGET_SECTORS)) # exclusive
  first=$(jq -r --argjson e "$current_end" '[.partitiontable.partitions[] | select(.start >= $e) | .start] | min // empty' "$json")
  lastlba=$(jq -r '.partitiontable.lastlba // empty' "$json")
  if [[ -n $first ]]; then boundary=$first; else is_uint "$lastlba" || die "sfdisk JSON does not expose GPT lastlba"; boundary=$((lastlba + 1)); fi
  ((boundary >= current_end)) || die "GPT partition geometry overlaps"
  printf '%s\n' "$((boundary - current_end))"
}

assert_growth_geometry() {
  local json=$1 new_end=$((TARGET_START + NEW_PART_SECTORS - 1)) lastlba starts
  lastlba=$(jq -er '.partitiontable.lastlba' "$json")
  (( new_end <= lastlba )) || die "Proposed partition end exceeds GPT last usable LBA"
  starts=$(jq -r --argjson lo "$((TARGET_START + TARGET_SECTORS))" --argjson hi "$new_end" --arg p "$TARGET_PART" '[.partitiontable.partitions[] | select(.node != $p and .start >= $lo and .start <= $hi) | .node] | join(",")' "$json")
  [[ -z $starts ]] || die "Proposed growth region contains another partition: $starts"
}

choose_operation_and_geometry() {
  local op raw current_map target_map reduction_sectors free_sectors json=$BACKUP_ROOT/metadata/partition-table.json
  sfdisk --json "$TARGET_DISK" >"$json"
  read -r TARGET_START TARGET_SECTORS < <(partition_fields "$json")
  TRAILING_FREE_BEFORE=$(trailing_free_sectors "$json")
  [[ $TARGET_SECTORS == "$OLD_PART_SECTORS" ]] || die "On-disk GPT and kernel partition size disagree before operation"
  OLD_PART_SECTORS=$TARGET_SECTORS; TARGET_BYTES=$((TARGET_SECTORS * LOGICAL_SECTOR))
  load_partition_attributes
  read_luks_geometry
  verify_single_btrfs_device
  OLD_FS_BYTES=$(btrfs_device_bytes); is_uint "$OLD_FS_BYTES" || die "Cannot read Btrfs devid 1 total_bytes"
  BTRFS_UUID=$(btrfs_uuid); [[ $BTRFS_UUID =~ ^[0-9a-fA-F-]{36}$ ]] || die "Cannot read Btrfs UUID"
  MIN_FS_BYTES=$(minimum_btrfs_bytes)
  preflight_filesystem_integrity
  printf '\nOperation:\n1. Decrease / Shrink partition\n2. Increase / Grow partition\n'
  read -r -p 'Select: ' op
  [[ $op == 1 || $op == 2 ]] || die "Invalid operation"
  if [[ $op == 1 ]]; then
    read -r -p 'Requested reduction (example: 50 GiB): ' raw
  else
    read -r -p 'Requested increase (example: 20 GiB): ' raw
  fi
  REQUEST_BYTES=$(parse_size "$raw") || die "Size must be an exact positive MiB, GiB, or TiB value (for example: 50 GiB)"
  (( REQUEST_BYTES % LOGICAL_SECTOR == 0 )) || die "Requested bytes are not exactly representable in disk sectors"
  reduction_sectors=$((REQUEST_BYTES / LOGICAL_SECTOR))
  (( reduction_sectors > 0 )) || die "Requested change is too small"
  if [[ $op == 1 ]]; then
    (( reduction_sectors < OLD_PART_SECTORS )) || die "Shrink would create a zero or negative partition"
    NEW_PART_SECTORS=$((OLD_PART_SECTORS - reduction_sectors))
    (( (NEW_PART_SECTORS * LOGICAL_SECTOR) % PHYSICAL_SECTOR == 0 )) || die "Requested final partition boundary is not physically aligned; no rounding is performed"
    target_map=$((NEW_PART_SECTORS * LOGICAL_SECTOR - LUKS_OFFSET_BYTES))
    (( target_map > 0 )) || die "Shrink would remove the LUKS payload"
    NEW_FS_BYTES=$target_map
    (( NEW_FS_BYTES % LUKS_SECTOR_BYTES == 0 )) || die "Final LUKS mapping size is not aligned to the LUKS sector size"
    (( NEW_FS_BYTES % BTRFS_SECTOR_BYTES == 0 )) || die "Final Btrfs device size is not aligned to the Btrfs sector size"
    (( NEW_FS_BYTES >= MIN_FS_BYTES + SAFETY_MARGIN_BYTES )) || die "Requested Btrfs shrink is below reported minimum plus $(human "$SAFETY_MARGIN_BYTES") safety margin"
    STATE=shrink
  else
    free_sectors=$TRAILING_FREE_BEFORE
    (( reduction_sectors <= free_sectors )) || die "Cannot grow target partition: adjacent trailing free space is insufficient or another partition occupies the requested region. No changes were made."
    NEW_PART_SECTORS=$((OLD_PART_SECTORS + reduction_sectors))
    (( (NEW_PART_SECTORS * LOGICAL_SECTOR) % PHYSICAL_SECTOR == 0 )) || die "Requested final partition boundary is not physically aligned; no rounding is performed"
    NEW_FS_BYTES=$((NEW_PART_SECTORS * LOGICAL_SECTOR - LUKS_OFFSET_BYTES))
    (( NEW_FS_BYTES % LUKS_SECTOR_BYTES == 0 && NEW_FS_BYTES % BTRFS_SECTOR_BYTES == 0 )) || die "Final LUKS/Btrfs growth geometry is not sector aligned"
    assert_growth_geometry "$json"
    STATE=grow
  fi
}

show_plan() {
  local max_reduce=0 free_after=$TRAILING_FREE_BEFORE fs_min_label fs_method
  if [[ $STATE == shrink ]]; then
    max_reduce=$((OLD_FS_BYTES - MIN_FS_BYTES - SAFETY_MARGIN_BYTES))
    (( max_reduce < 0 )) && max_reduce=0
  else free_after=$((TRAILING_FREE_BEFORE - REQUEST_BYTES / LOGICAL_SECTOR)); fi
  fs_min_label='Btrfs device minimum'; fs_method='btrfs min-dev-size, single devid 1'
  printf '\n============================================================\nNEO SAFE PARTITION RESIZER\n============================================================\n\nTarget: %s\nDisk: %s (%s)\nContainer: %s\nFilesystem: %s\nCurrent partition: %s\nCurrent filesystem device: %s\nOperation: %s\nRequested change: %s\nTarget partition: %s\nTarget filesystem/mapping: %s\n%s: %s\nMinimum calculation: %s\nRequired safety margin: %s\nMaximum safe reduction: %s\nTrailing free before: %s\nTrailing free after: %s\nBackup: %s\nUser backup: %s.tar (verified metadata archive)\nRollback image: VERIFIED\n\nSafety checks:\n  Live USB environment           PASS\n  Target not active              PASS\n  Hardware fingerprint           PASS\n  Backup identity/verification   PASS\n  Filesystem pre-check           PASS\n  Partition alignment            PASS\n============================================================\n\nFINAL CONFIRMATION\nThe next operation can modify your storage.\nType exactly RESIZE to continue: ' \
    "$TARGET_PART" "$TARGET_DISK" "$(lsblk -ndo MODEL "$TARGET_DISK")" "$TARGET_CONTAINER" "$TARGET_FILESYSTEM" "$(human "$((OLD_PART_SECTORS * LOGICAL_SECTOR))")" "$(human "$OLD_FS_BYTES")" "${STATE^^}" "$(human "$REQUEST_BYTES")" "$(human "$((NEW_PART_SECTORS * LOGICAL_SECTOR))")" "$(human "$NEW_FS_BYTES")" "$fs_min_label" "$(human "$MIN_FS_BYTES")" "$fs_method" "$(human "$SAFETY_MARGIN_BYTES")" "$(human "$max_reduce")" "$(human "$((TRAILING_FREE_BEFORE * LOGICAL_SECTOR))")" "$(human "$((free_after * LOGICAL_SECTOR))")" "$BACKUP_ROOT" "$SELECTED_USER"
}

sync_and_verify_kernel_gpt() {
  local actual_start actual_size disk_start disk_size info json
  partprobe "$TARGET_DISK"
  partx -u "$TARGET_DISK"
  udevadm settle
  actual_start=$(cat "/sys/class/block/${TARGET_PART##*/}/start")
  actual_size=$(cat "/sys/class/block/${TARGET_PART##*/}/size")
  [[ $actual_start == "$TARGET_START" && $actual_size == "$NEW_PART_SECTORS" ]] || die "PARTITION TABLE SYNCHRONIZATION FAILED: GPT on disk and kernel partition geometry disagree. No further storage modifications will be attempted."
  json=$(mktemp /tmp/neo-resizer-gpt.XXXXXX)
  sfdisk --json "$TARGET_DISK" >"$json"
  read -r disk_start disk_size < <(partition_fields "$json")
  rm -f "$json"
  [[ $disk_start == "$TARGET_START" && $disk_size == "$NEW_PART_SECTORS" ]] || die "On-disk GPT partition boundary differs from calculated geometry"
  verify_gpt_integrity 'Post-partition-change GPT'
  info=$(sgdisk -i "$TARGET_NUM" "$TARGET_DISK")
  grep -Fq "Partition unique GUID: $OLD_PART_GUID" <<<"$info" || die "Partition GUID changed unexpectedly"
  grep -Fq "Partition GUID code: $OLD_PART_TYPE" <<<"$info" || die "Partition type changed unexpectedly"
  grep -Fq "Attribute flags: $OLD_PART_ATTRS" <<<"$info" || die "Partition attributes changed unexpectedly"
  grep -Fq "Partition name: '$OLD_PART_NAME'" <<<"$info" || die "Partition name changed unexpectedly"
  [[ $(blkid -o value -s PARTUUID "$TARGET_PART") == "$TARGET_PARTUUID" ]] || die "Partition UUID changed unexpectedly"
  verify_layout_only_target_changed
}

change_partition_end() {
  local end=$((TARGET_START + NEW_PART_SECTORS - 1))
  verify_backup_identity
  verify_target_identity
  (( end > TARGET_START )) || die "Calculated invalid partition end"
  note "Changing only GPT partition $TARGET_NUM end to sector $end"
  parted -s "$TARGET_DISK" unit s resizepart "$TARGET_NUM" "${end}s"
  CHECKPOINT=5
  sync_and_verify_kernel_gpt
  CHECKPOINT=6
}

mount_rw() {
  FS_MOUNT=$(mktemp -d /mnt/neo-resizer-rw.XXXXXX)
  if [[ $TARGET_FILESYSTEM == btrfs ]]; then mount -o rw,subvolid=5 "$MAP_DEV" "$FS_MOUNT"; else die "Internal error: mount_rw called for non-Btrfs"; fi
}
unmount_fs() { [[ -n ${FS_MOUNT:-} ]] && findmnt -rn --target "$FS_MOUNT" >/dev/null 2>&1 && umount "$FS_MOUNT"; [[ -n ${FS_MOUNT:-} ]] && rmdir "$FS_MOUNT" 2>/dev/null || true; FS_MOUNT=; }
close_luks() { [[ -n ${MAP_NAME:-} ]] && cryptsetup status "$MAP_NAME" >/dev/null 2>&1 && cryptsetup close "$MAP_NAME"; }
close_home_source() { [[ -n ${HOME_MOUNT:-} && $HOME_MOUNT != ${FS_MOUNT:-} ]] && findmnt -rn --target "$HOME_MOUNT" >/dev/null 2>&1 && umount "$HOME_MOUNT"; [[ -n ${HOME_MOUNT:-} && $HOME_MOUNT != ${FS_MOUNT:-} ]] && rmdir "$HOME_MOUNT" 2>/dev/null || true; [[ -n ${HOME_MAP_NAME:-} ]] && cryptsetup status "$HOME_MAP_NAME" >/dev/null 2>&1 && cryptsetup close "$HOME_MAP_NAME"; }

verify_btrfs_filesystem() {
  local expected=$1 got
  btrfs check --readonly "$MAP_DEV"
  got=$(btrfs_device_bytes); [[ $got == "$expected" ]] || die "Btrfs devid 1 total_bytes ($got) differs from expected size ($expected)"
  [[ $(btrfs_stats_values) == "$BTRFS_STATS_BASELINE" ]] || die "Btrfs device error counters changed during operation"
}

verify_btrfs_mapping_geometry() {
  local expected=$1
  [[ $(blockdev --getsize64 "$MAP_DEV") == "$expected" ]] || die "LUKS mapper size does not match expected Btrfs device size"
}

verify_rw_reopened_geometry() {
  read_luks_geometry
  verify_single_btrfs_device
  verify_btrfs_mapping_geometry "$OLD_FS_BYTES"
  [[ $(btrfs_uuid) == "$BTRFS_UUID" ]] || die "Btrfs UUID changed while reopening the writable mapping"
  [[ $(btrfs_device_bytes) == "$OLD_FS_BYTES" ]] || die "Btrfs size changed while reopening the writable mapping"
}

shrink_btrfs_luks() {
  verify_backup_identity
  verify_target_identity
  mount_rw
  note "[BTRFS] Shrinking filesystem; extents may be relocated and this can take time."
  btrfs filesystem resize "1:${NEW_FS_BYTES}" "$FS_MOUNT"
  CHECKPOINT=3
  unmount_fs
  # The mapper is intentionally still old/larger here; verify only Btrfs.
  verify_btrfs_filesystem "$NEW_FS_BYTES"
  CHECKPOINT=4
  close_luks
  change_partition_end
  open_luks
  verify_btrfs_mapping_geometry "$NEW_FS_BYTES"
  verify_btrfs_filesystem "$NEW_FS_BYTES"
  CHECKPOINT=8
}

grow_btrfs_luks() {
  verify_backup_identity
  verify_target_identity
  close_luks
  change_partition_end
  open_luks
  verify_btrfs_mapping_geometry "$NEW_FS_BYTES"
  CHECKPOINT=7
  mount_rw
  note "[BTRFS] Growing filesystem."
  btrfs filesystem resize max "$FS_MOUNT"
  unmount_fs
  verify_btrfs_mapping_geometry "$NEW_FS_BYTES"
  verify_btrfs_filesystem "$NEW_FS_BYTES"
  CHECKPOINT=8
}

rollback_identity_matches() {
  local md=$BACKUP_ROOT/metadata/identity-before.env key val model serial wwn tran bytes start partuuid
  [[ -r $md && -r $IMAGE && -r $BACKUP_ROOT/rollback/image.sha256 && -r $BACKUP_ROOT/metadata/gpt-before.bin && -r $BACKUP_ROOT/rollback/gpt-before.sha256 ]] || return 1
  (cd "$BACKUP_ROOT" && sha256sum -c rollback/image.sha256 >/dev/null 2>&1) || return 1
  (cd "$BACKUP_ROOT" && sha256sum -c rollback/gpt-before.sha256 >/dev/null 2>&1) || return 1
  model=$(awk -F= '$1=="model" {sub(/^[^=]*=/,"",$0); print $0}' "$md")
  serial=$(awk -F= '$1=="serial" {sub(/^[^=]*=/,"",$0); print $0}' "$md")
  wwn=$(awk -F= '$1=="wwn" {sub(/^[^=]*=/,"",$0); print $0}' "$md")
  tran=$(awk -F= '$1=="tran" {sub(/^[^=]*=/,"",$0); print $0}' "$md")
  bytes=$(awk -F= '$1=="disk_bytes" {print $2}' "$md")
  start=$(awk -F= '$1=="start" {print $2}' "$md")
  partuuid=$(awk -F= '$1=="partuuid" {print $2}' "$md")
  [[ $(lsblk -ndo MODEL "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$model" ]] || return 1
  [[ -z $serial || $(lsblk -ndo SERIAL "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$serial" ]] || return 1
  [[ -z $wwn || $(lsblk -ndo WWN "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$wwn" ]] || return 1
  [[ -z $tran || $(lsblk -ndo TRAN "$TARGET_DISK" | sed 's/[[:space:]]*$//') == "$tran" ]] || return 1
  [[ $(blockdev --getsize64 "$TARGET_DISK") == "$bytes" ]] || return 1
  [[ $(cat "/sys/class/block/${TARGET_PART##*/}/start" 2>/dev/null) == "$start" ]] || return 1
  [[ $(blkid -o value -s PARTUUID "$TARGET_PART" 2>/dev/null || true) == "$partuuid" ]] || return 1
  is_uint "$start" && [[ $partuuid == "$TARGET_PARTUUID" ]]
}

rollback_if_safe() {
  local why=$1 restored_hash old_map_bytes old_btrfs_uuid
  (( ROLLBACK_ATTEMPTED )) && return
  ROLLBACK_ATTEMPTED=1
  note "Automatic rollback assessment: $why"
  unmount_fs || true
  close_luks || true
  # Do not restore the whole GPT if any non-target partition changed outside
  # this transaction's strictly predicted old/new target-end states.
  if ! rollback_gpt_state_is_safe; then
    ROLLBACK_STATE=NOT_ATTEMPTED_UNEXPECTED_GPT
    note "Automatic rollback NOT ATTEMPTED: current GPT contains unexpected partition changes. Manual recovery required."
    return
  fi
  if ! rollback_identity_matches; then
    ROLLBACK_STATE=NOT_ATTEMPTED_IDENTITY_UNPROVEN
    note "Automatic rollback NOT ATTEMPTED: disk/image identity could not be proven."
    return
  fi
  if ! sgdisk --load-backup="$BACKUP_ROOT/metadata/gpt-before.bin" "$TARGET_DISK" >>"$LOGFILE" 2>&1; then
    ROLLBACK_STATE=GPT_RESTORE_WRITE_FAILED
    note "Automatic rollback FAILED while restoring GPT."
    return
  fi
  ROLLBACK_STATE=ON_DISK_GPT_RESTORED_KERNEL_SYNC_PENDING_IMAGE_NOT_RESTORED
  if ! partprobe "$TARGET_DISK" >>"$LOGFILE" 2>&1 || ! partx -u "$TARGET_DISK" >>"$LOGFILE" 2>&1; then
    ROLLBACK_STATE=ON_DISK_GPT_RESTORED_KERNEL_SYNC_FAILED_IMAGE_NOT_RESTORED
    note "Automatic rollback stopped: on-disk GPT restored, kernel synchronization failed, raw image NOT restored. Do not reboot; use standalone recovery after resolving kernel reread."
    return
  fi
  udevadm settle
  # The old GPT must be visible before writing every byte of the old partition.
  if [[ $(cat "/sys/class/block/${TARGET_PART##*/}/start" 2>/dev/null) != "$TARGET_START" || $(cat "/sys/class/block/${TARGET_PART##*/}/size" 2>/dev/null) != "$OLD_PART_SECTORS" ]]; then
    ROLLBACK_STATE=ON_DISK_GPT_RESTORED_KERNEL_GEOMETRY_UNPROVEN_IMAGE_NOT_RESTORED
    note "Automatic rollback FAILED: restored kernel partition geometry is not proven."
    return
  fi
  if ! dd if="$IMAGE" of="$TARGET_PART" bs=16M iflag=fullblock conv=fsync status=progress >>"$LOGFILE" 2>&1; then
    ROLLBACK_STATE=GPT_RESTORED_IMAGE_WRITE_FAILED
    note "Automatic rollback FAILED while writing raw partition image."
    return
  fi
  restored_hash=$(sha256sum "$TARGET_PART" | awk '{print $1}')
  if [[ $restored_hash != "$IMAGE_SHA" ]]; then note "Automatic rollback FAILED: raw partition read-back hash differs from verified image."; return; fi
  if ! cryptsetup isLuks --type luks2 "$TARGET_PART" >>"$LOGFILE" 2>&1; then note "Automatic rollback FAILED: restored LUKS header does not validate."; return; fi
  if [[ $(cryptsetup luksUUID "$TARGET_PART") != "$LUKS_UUID" ]]; then note "Automatic rollback FAILED: restored LUKS UUID differs."; return; fi
  # Use a fresh mapper so its size is derived from restored partition geometry.
  if ! cryptsetup open "$TARGET_PART" "$MAP_NAME" >>"$LOGFILE" 2>&1; then note "Automatic rollback FAILED: cannot reopen restored LUKS container."; return; fi
  old_map_bytes=$((OLD_PART_SECTORS * LOGICAL_SECTOR - LUKS_OFFSET_BYTES))
  if [[ $(blockdev --getsize64 "$MAP_DEV") != "$old_map_bytes" ]]; then note "Automatic rollback FAILED: restored mapper size differs."; close_luks || true; return; fi
  if ! btrfs check --readonly "$MAP_DEV" >>"$LOGFILE" 2>&1; then note "Automatic rollback FAILED: restored Btrfs readonly check failed."; close_luks || true; return; fi
  if [[ $(btrfs_uuid) != "$BTRFS_UUID" ]]; then note "Automatic rollback FAILED: restored Btrfs UUID differs."; close_luks || true; return; fi
  if [[ $(btrfs_device_bytes) != "$OLD_FS_BYTES" ]]; then note "Automatic rollback FAILED: restored Btrfs devid size differs."; close_luks || true; return; fi
  close_luks || true
  ROLLBACK_STATE=COMPLETED_FULL_STACK_VERIFIED
  note "Automatic full storage rollback COMPLETED: GPT, raw image read-back hash, and restored filesystem stack verified."
}

rollback_gpt_state_is_safe() {
  local before=$BACKUP_ROOT/metadata/partition-layout-before.txt now old new target
  [[ -r $before ]] || return 1
  now=$(mktemp /tmp/neo-resizer-rollback-layout.XXXXXX)
  normalized_partition_layout "$TARGET_DISK" >"$now" || { rm -f "$now"; return 1; }
  diff -u <(grep -v "^$TARGET_NUM|" "$before") <(grep -v "^$TARGET_NUM|" "$now") >/dev/null || { rm -f "$now"; return 1; }
  target=$(grep "^$TARGET_NUM|" "$now")
  old=$(grep "^$TARGET_NUM|" "$before")
  new=$(awk -F'|' -v n="$TARGET_NUM" -v s="$NEW_PART_SECTORS" 'BEGIN{OFS="|"} $1==n {$3=s; print}' "$before")
  rm -f "$now"
  [[ $target == "$old" || $target == "$new" ]]
}

verify_pretransaction_state() {
  local now=$BACKUP_ROOT/metadata/partition-layout-precommit.txt
  verify_backup_identity
  verify_target_identity
  verify_gpt_integrity 'Pre-transaction GPT'
  partition_active_or_mounted "$TARGET_PART" && die "Target became mounted or acquired active holders before transaction"
  normalized_partition_layout "$TARGET_DISK" >"$now"
  diff -u "$BACKUP_ROOT/metadata/partition-layout-before.txt" "$now" >/dev/null || die "GPT differs from the verified pre-operation layout immediately before transaction"
}

verify_recovery_backup_location() {
  local src disk tran
  src=$(findmnt -nro SOURCE -T "$BACKUP_ROOT" 2>/dev/null || true)
  [[ -n $src && $src != overlay ]] || die "Recovery backup root is not on a real mounted filesystem"
  while read -r disk; do
    [[ $(lsblk -ndo TRAN "$disk" 2>/dev/null || true) == usb ]] || continue
    array_contains "$(canon "$disk")" "${LIVE_DISKS[@]}" && continue
    [[ $(canon "$disk") != $(canon "$TARGET_DISK") ]] || continue
    return 0
  done < <(ancestor_disks "$src")
  die "Recovery backup root is not proven to be on a non-live external USB device"
}

failure_report() {
  local failure=$1 rc=$2
  printf '\n============================================================\nNEO PARTITION RESIZER — OPERATION FAILED\n============================================================\nCheckpoint reached: %s\nFailure: %s\nExit status: %s\nAutomatic rollback state: %s\nBackup: %s\nDiagnostics: %s\nBackup location: %s\n\nDo NOT reboot until reviewing the recovery state.\n============================================================\n' "$CHECKPOINT" "$failure" "$rc" "$ROLLBACK_STATE" "${BACKUP_ROOT:-unknown}" "${DIAGFILE:-not collected}" "${BACKUP_ROOT:-unknown}" | tee -a "${LOGFILE:-/dev/null}"
}

final_report() {
  local log_sink=/dev/null diagnostics_status='[ WARN ] Backup USB is readable but no longer writable; final diagnostics were printed only.'
  if [[ -w $BACKUP_MOUNT ]]; then
    DIAGFILE=$BACKUP_ROOT/logs/diagnostics-final.txt
    collect_diagnostics final
    log_sink=$LOGFILE
    diagnostics_status='[ OK ] Stored at logs/diagnostics-final.txt'
  else
    printf '%s\n' "$diagnostics_status" >&2
  fi
  printf '\n============================================================\nNEO PARTITION RESIZER — FINAL REPORT\n============================================================\nStorage operation: [ OK ] COMPLETED\nTarget: %s\nOperation: %s\nPrevious partition size: %s\nNew partition size: %s\nRequested change: %s\nFilesystem: %s\nPrevious filesystem size: %s\nNew filesystem size: %s\nFilesystem integrity: [ OK ]\nLUKS: [ OK ]\nPartition table: [ OK ]\nKernel partition view: [ OK ]\nGPT verification: [ OK ]\nUser backup: [ OK ]\nRollback backup: [ OK ]\nChecksums: [ OK ]\nNo unexpected partition modifications: [ OK ]\nFinal diagnostic storage: %s\nBackup location: %s\n============================================================\n' \
    "$TARGET_PART" "${STATE^^}" "$(human "$((OLD_PART_SECTORS * LOGICAL_SECTOR))")" "$(human "$((NEW_PART_SECTORS * LOGICAL_SECTOR))")" "$(human "$REQUEST_BYTES")" "$TARGET_FILESYSTEM" "$(human "$OLD_FS_BYTES")" "$(human "$NEW_FS_BYTES")" "$diagnostics_status" "$BACKUP_ROOT" | tee -a "$log_sink"
}

standalone_recovery() {
  local disk= part= root= arg ok meta expected actual old_start old_size saved_luks saved_btrfs saved_btrfs_bytes
  require_root_and_tools
  while (($#)); do
    case $1 in
      --backup-root) root=${2:?}; shift 2 ;;
      --disk) disk=${2:?}; shift 2 ;;
      --partition) part=${2:?}; shift 2 ;;
      *) die "Usage: $0 --recover --backup-root /mount/neo-resize-backup-... --disk /dev/sdX --partition /dev/sdXN" ;;
    esac
  done
  [[ -d $root && -b $disk && -b $part ]] || die "Recovery backup root, disk, or partition is invalid"
  BACKUP_ROOT=$(canon "$root"); TARGET_DISK=$(canon "$disk"); TARGET_PART=$(canon "$part")
  TARGET_NUM=$(lsblk -ndo PARTN "$TARGET_PART"); LOGFILE=$BACKUP_ROOT/logs/recovery.log
  meta=$BACKUP_ROOT/metadata/identity-before.env
  IMAGE=$BACKUP_ROOT/rollback/target-partition-before.img
  [[ -r $meta && -r $IMAGE && -r $BACKUP_ROOT/rollback/image.sha256 && -r $BACKUP_ROOT/metadata/gpt-before.bin ]] || die "Recovery set is incomplete"
  TARGET_START=$(awk -F= '$1=="start" {print $2}' "$meta")
  OLD_PART_SECTORS=$(awk -F= '$1=="sectors" {print $2}' "$meta")
  TARGET_PARTUUID=$(awk -F= '$1=="partuuid" {print $2}' "$meta")
  [[ $TARGET_NUM == $(awk -F= '$1=="target_num" {print $2}' "$meta") ]] || die "Recovery partition number differs from the saved target number"
  TARGET_MODEL=$(awk -F= '$1=="model" {sub(/^[^=]*=/,"",$0);print}' "$meta")
  TARGET_SERIAL=$(awk -F= '$1=="serial" {sub(/^[^=]*=/,"",$0);print}' "$meta")
  TARGET_WWN=$(awk -F= '$1=="wwn" {sub(/^[^=]*=/,"",$0);print}' "$meta")
  TARGET_TRAN=$(awk -F= '$1=="tran" {sub(/^[^=]*=/,"",$0);print}' "$meta")
  TARGET_DISK_BYTES=$(awk -F= '$1=="disk_bytes" {print $2}' "$meta")
  LOGICAL_SECTOR=$(awk -F= '$1=="logical_sector" {print $2}' "$meta")
  PHYSICAL_SECTOR=$(awk -F= '$1=="physical_sector" {print $2}' "$meta")
  saved_luks=$(awk -F= '$1=="luks_uuid" {print $2}' "$meta")
  saved_btrfs=$(awk -F= '$1=="btrfs_uuid" {print $2}' "$meta")
  saved_btrfs_bytes=$(awk -F= '$1=="btrfs_device_bytes" {print $2}' "$meta")
  is_uint "$TARGET_START" && is_uint "$OLD_PART_SECTORS" && is_uint "$TARGET_DISK_BYTES" && is_uint "$LOGICAL_SECTOR" || die "Recovery identity metadata is malformed"
  detect_live_environment
  array_contains "$(canon "$TARGET_DISK")" "${LIVE_DISKS[@]}" && die "Recovery target is the live USB"
  verify_recovery_backup_location
  partition_active_or_mounted "$TARGET_PART" && die "Recovery target is mounted or has active holders; boot a Live USB and close all mappings"
  (cd "$BACKUP_ROOT" && sha256sum -c rollback/gpt-before.sha256 >/dev/null && sha256sum -c rollback/image.sha256 >/dev/null && sha256sum -c backup-artifacts.sha256 >/dev/null) || die "Recovery backup artifact checksum verification failed"
  rollback_identity_matches || die "Recovery target identity or image checksum cannot be proven"
  read -r -p 'This restores the old GPT and complete partition image. Type RECOVER: ' ok
  [[ $ok == RECOVER ]] || die "Recovery confirmation not received"
  RECOVERY_WRITES_STARTED=1
  sgdisk --load-backup="$BACKUP_ROOT/metadata/gpt-before.bin" "$TARGET_DISK"
  partprobe "$TARGET_DISK"; partx -u "$TARGET_DISK"; udevadm settle
  [[ $(cat "/sys/class/block/${TARGET_PART##*/}/start") == "$TARGET_START" && $(cat "/sys/class/block/${TARGET_PART##*/}/size") == "$OLD_PART_SECTORS" ]] || die "Recovered GPT is not visible in the kernel"
  verify_gpt_integrity 'Recovered GPT'
  normalized_partition_layout "$TARGET_DISK" >"/tmp/neo-resizer-recovery-layout-${RUN_ID}.txt"
  diff -u "$BACKUP_ROOT/metadata/partition-layout-before.txt" "/tmp/neo-resizer-recovery-layout-${RUN_ID}.txt" >/dev/null || die "Recovered GPT layout differs from the recorded pre-operation layout"
  dd if="$IMAGE" of="$TARGET_PART" bs=16M iflag=fullblock conv=fsync status=progress
  expected=$(awk '{print $1}' "$BACKUP_ROOT/rollback/image.sha256")
  actual=$(sha256sum "$TARGET_PART" | awk '{print $1}')
  [[ $actual == "$expected" ]] || die "Recovery raw-image read-back hash failed; do not boot"
  [[ -n $saved_luks && -n $saved_btrfs && -n $saved_btrfs_bytes ]] || die "Recovery set does not describe the required LUKS2 -> Btrfs target"
  cryptsetup isLuks --type luks2 "$TARGET_PART" || die "Recovered LUKS2 header does not validate"
  [[ $(cryptsetup luksUUID "$TARGET_PART") == "$saved_luks" ]] || die "Recovered LUKS UUID differs"
  IS_LUKS=1; LUKS_UUID=$saved_luks; MAP_NAME="neo-recovery-${saved_luks//-/}"; MAP_NAME=${MAP_NAME:0:60}; MAP_DEV=/dev/mapper/$MAP_NAME
  cryptsetup open "$TARGET_PART" "$MAP_NAME"
  read_luks_geometry
  verify_single_btrfs_device
  [[ $(blockdev --getsize64 "$MAP_DEV") == "$saved_btrfs_bytes" ]] || die "Recovered mapper size differs"
  btrfs check --readonly "$MAP_DEV"
  [[ $(btrfs_uuid) == "$saved_btrfs" ]] || die "Recovered Btrfs UUID differs"
  [[ $(btrfs_device_bytes) == "$saved_btrfs_bytes" ]] || die "Recovered Btrfs device size differs"
  close_luks
  printf 'RECOVERY VERIFIED: GPT, raw image read-back hash, and filesystem stack all passed verification. Safe to shut down or reboot.\n'
}

main() {
  if [[ ${1:-} == --print-fingerprint ]]; then print_fingerprint; return; fi
  if [[ ${1:-} == --recover ]]; then shift; standalone_recovery "$@"; return; fi
  require_root_and_tools
  detect_live_environment
  select_target
  select_backup
  BACKUP_ROOT="$BACKUP_MOUNT/neo-resize-backup-${RUN_ID}-$(basename "$TARGET_PART")"
  mkdir -p "$BACKUP_ROOT"
  # Hold an advisory lock so two copies cannot operate concurrently from the
  # same live environment. The lock is intentionally outside the target.
  exec 9>"$BACKUP_ROOT/.operation.lock"
  flock -n 9 || die "Another resizer instance is using this backup set"
  open_luks ro
  mount_filesystem_ro_for_discovery
  select_user
  verify_backup_capacity_preflight
  backup_metadata
  write_recovery_tool
  copy_user_backup
  # The verified raw image is intentionally taken only after both filesystem
  # and dm-crypt layers are closed. No target filesystem is active at this point.
  unmount_fs
  close_luks
  close_home_source
  sync
  verify_backup_identity
  check_capacity_and_create_image
  verify_backup_set
  # Analysis remains read-only until the user explicitly commits.
  open_luks ro
  choose_operation_and_geometry
  CHECKPOINT=2
  show_plan
  local confirm
  read -r confirm
  [[ $confirm == RESIZE ]] || die "Final confirmation was not received"
  close_luks
  verify_pretransaction_state
  open_luks rw
  verify_rw_reopened_geometry
  TX_ACTIVE=1
  if [[ $STATE == shrink ]]; then shrink_btrfs_luks; else grow_btrfs_luks; fi
  verify_gpt_integrity 'Final GPT'
  CHECKPOINT=9
  TX_ACTIVE=0
  OPERATION_COMMITTED=1
  verify_backup_mount_identity
  (cd "$BACKUP_ROOT" && sha256sum -c backup-artifacts.sha256 >/dev/null) || die "Final verified backup-artifact checksum verification failed"
  final_report
  [[ -w $BACKUP_MOUNT ]] && note "Completed successfully. The raw rollback image remains available; it is a full pre-operation partition image, not merely metadata recovery."
}

main "$@"
