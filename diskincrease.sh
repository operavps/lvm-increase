#!/bin/bash

# VPS DISK INCREASE - ALL IN ONE Supported:  Ubuntu (22 / 24 / 26)  Debian (11 / 12 / 13)  Fedora (44)  CentOS Stream (10)  AlmaLinux (8 / 9 / 10)  Rocky Linux (10)  Arch Linux

set -Eeuo pipefail

# GLOBALS

OS_ID=""
OS_VERSION=""
OS_NAME=""

ROOT_SOURCE=""
FILESYSTEM=""

VG=""
PV=""
DISK=""
PARTITION=""

NO_RESIZE_NEEDED=0

INITIAL_DISK_BYTES=0
FINAL_DISK_BYTES=0
ADDED_BYTES=0

INITIAL_DISK=""
FINAL_DISK=""
ADDED_DISK=""
FINAL_ROOT=""

# LOGGING

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# HUMAN SIZE

human_size() {

    local bytes="$1"

    if (( bytes >= 1099511627776 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fT", b/1099511627776}'
    elif (( bytes >= 1073741824 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fG", b/1073741824}'
    elif (( bytes >= 1048576 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fM", b/1048576}'
    elif (( bytes >= 1024 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fK", b/1024}'
    else
        echo "${bytes}B"
    fi
}

# CAPTURE INITIAL DISK

capture_initial_disk() {

    INITIAL_DISK_BYTES=$(lsblk -bdno SIZE "$DISK" 2>/dev/null |
        head -1 |
        xargs)

    [[ "$INITIAL_DISK_BYTES" =~ ^[0-9]+$ ]] || \
        error "Unable to determine initial disk size."

    INITIAL_DISK=$(human_size "$INITIAL_DISK_BYTES")
}

# CAPTURE FINAL DISK

capture_final_disk() {

    FINAL_DISK_BYTES=$(lsblk -bdno SIZE "$DISK" 2>/dev/null |
        head -1 |
        xargs)

    [[ "$FINAL_DISK_BYTES" =~ ^[0-9]+$ ]] || \
        error "Unable to determine final disk size."

    FINAL_DISK=$(human_size "$FINAL_DISK_BYTES")

    if (( FINAL_DISK_BYTES > INITIAL_DISK_BYTES )); then
        ADDED_DISK=$(human_size \
            $((FINAL_DISK_BYTES - INITIAL_DISK_BYTES)))
    else
        ADDED_DISK="0G"
    fi

    FINAL_ROOT=$(df -hP / | awk 'NR==2 {print $2}')

    [[ -n "$FINAL_ROOT" ]] || FINAL_ROOT="Unknown"
}

# FINAL SUCCESS

final_success() {

    capture_final_disk

    echo
    echo "========================================="
    echo "          STORAGE RESIZE SUCCESS"
    echo "========================================="
    echo "OS        : $OS_NAME"
    echo "Previous  : $INITIAL_DISK"
    echo "Added     : +$ADDED_DISK"
    echo "Total     : $FINAL_DISK"
    echo "Root FS   : $FINAL_ROOT"
    echo "Status    : Successfully extended"
    echo "========================================="
    echo
}

# FINAL NO RESIZE

final_no_resize() {

    capture_final_disk

    echo
    echo "========================================="
    echo "       STORAGE ALREADY AT MAXIMUM"
    echo "========================================="
    echo "OS        : $OS_NAME"
    echo "Total     : $FINAL_DISK"
    echo "Added     : 0G"
    echo "Root FS   : $FINAL_ROOT"
    echo "Status    : No additional storage detected"
    echo "========================================="
    echo
}

# CONFIRM EXTENSION

show_resize_confirmation() {

    local initial_bytes="$1"
    local added_bytes="$2"
    local final_bytes="$3"
    local os_name="$4"
    local answer

    echo
    echo "========================================="
    echo "     ADDITIONAL STORAGE DETECTED"
    echo "========================================="
    echo "OS        : $os_name"
    echo "Current   : $(human_size "$initial_bytes")"
    echo "Added     : +$(human_size "$added_bytes")"
    echo "New Total : $(human_size "$final_bytes")"
    echo "========================================="
    echo

    read -r -p "Do you want to extend the storage? [y/N]: " answer </dev/tty

    case "$answer" in
        y|Y)
            ;;
        *)
            echo
            echo "========================================="
            echo "       STORAGE RESIZE CANCELLED"
            echo "========================================="
            echo "OS        : $os_name"
            echo "Status    : No changes were made"
            echo "========================================="
            echo
            exit 0
            ;;
    esac
}

prepare_resize_confirmation() {
    local added_bytes="$1"
    local final_bytes
    local initial_bytes

    capture_final_disk
    final_bytes=$FINAL_DISK_BYTES
    if (( final_bytes > INITIAL_DISK_BYTES )); then
        added_bytes=$((final_bytes - INITIAL_DISK_BYTES))
        initial_bytes=$INITIAL_DISK_BYTES
    else
        initial_bytes=$((final_bytes - added_bytes))
    fi

    (( added_bytes > 0 )) || return 1
    show_resize_confirmation "$initial_bytes" "$added_bytes" "$final_bytes" "$OS_NAME"
}

preflight_growpart() {

    local disk="$1"
    local partition="$2"
    local output
    local status

    if output=$(growpart -N "$disk" "$partition" 2>&1); then
        status=0
    else
        status=$?
    fi

    if echo "$output" | grep -q "NOCHANGE"; then
        return 1
    fi

    (( status == 0 )) || return 0

    return 0
}

# FINAL FAILURE

final_failure() {

    echo
    echo "========================================="
    echo "          STORAGE RESIZE FAILED"
    echo "========================================="
    echo "OS        : ${OS_NAME:-Unknown}"
    echo "Status    : Resize could not be completed"
    echo "========================================="
    echo
}

# ERROR TRAP

trap '
    trap - ERR
    final_failure
    exit 1
' ERR

# ROOT CHECK

check_root() {

    if [[ $EUID -ne 0 ]]; then
        error "Script must be run as root."
    fi
}

# OS DETECTION

detect_os() {

    [[ -f /etc/os-release ]] || \
        error "/etc/os-release not found."

    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"

    case "$OS_ID" in

        ubuntu)

            case "$OS_VERSION" in
                22.04)
                    OS_NAME="Ubuntu 22"
                    ;;
                24.04)
                    OS_NAME="Ubuntu 24"
                    ;;
                26.04)
                    OS_NAME="Ubuntu 26"
                    ;;
                *)
                    error "Unsupported Ubuntu version."
                    ;;
            esac
            ;;

        debian)

            case "$OS_VERSION" in
                11)
                    OS_NAME="Debian 11"
                    ;;
                12)
                    OS_NAME="Debian 12"
                    ;;
                13)
                    OS_NAME="Debian 13"
                    ;;
                *)
                    error "Unsupported Debian version."
                    ;;
            esac
            ;;

        fedora)

            [[ "$OS_VERSION" == "44" ]] || \
                error "Unsupported Fedora version."

            OS_NAME="Fedora 44"
            ;;

        centos)

            [[ "$OS_VERSION" == "10" ]] || \
                error "Unsupported CentOS version."

            OS_NAME="CentOS Stream 10"
            ;;

        almalinux)

            case "$OS_VERSION" in
                8*)
                    OS_NAME="AlmaLinux 8"
                    ;;
                9*)
                    OS_NAME="AlmaLinux 9"
                    ;;
                10*)
                    OS_NAME="AlmaLinux 10"
                    ;;
                *)
                    error "Unsupported AlmaLinux version."
                    ;;
            esac
            ;;

        rocky)

            [[ "$OS_VERSION" == 10* ]] || \
                error "Unsupported Rocky Linux version."

            OS_NAME="Rocky Linux 10"
            ;;

        arch)

            OS_NAME="Arch Linux"
            ;;

        *)

            error "Unsupported operating system."
            ;;

    esac

    log "Detected OS: $OS_NAME"
}

# REQUIRED COMMAND

require_command() {

    command -v "$1" >/dev/null 2>&1 || \
        error "Required command '$1' is not installed."
}

# APT REQUIREMENTS

install_apt_requirements() {

    local missing=0

    command -v growpart >/dev/null 2>&1 || missing=1
    command -v pvresize >/dev/null 2>&1 || missing=1
    command -v lvextend >/dev/null 2>&1 || missing=1
    command -v partprobe >/dev/null 2>&1 || missing=1
    command -v resize2fs >/dev/null 2>&1 || missing=1
    command -v fallocate >/dev/null 2>&1 || missing=1
    command -v blkid >/dev/null 2>&1 || missing=1
    command -v mkswap >/dev/null 2>&1 || missing=1
    command -v swapon >/dev/null 2>&1 || missing=1
    command -v swapoff >/dev/null 2>&1 || missing=1

    if (( missing == 1 )); then

        log "Installing required packages..."

        export DEBIAN_FRONTEND=noninteractive

        apt-get update -qq >/dev/null 2>&1

        apt-get install -y \
            cloud-guest-utils \
            lvm2 \
            parted \
            e2fsprogs \
            xfsprogs \
            util-linux \
            >/dev/null 2>&1
    fi

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command partprobe
    require_command resize2fs
    require_command fallocate
    require_command blkid
    require_command mkswap
    require_command swapon
    require_command swapoff
}

# DNF REQUIREMENTS

install_dnf_requirements() {

    local packages=(
        cloud-utils-growpart
        e2fsprogs
        lvm2
        parted
        xfsprogs
        util-linux
    )

    local missing=0

    for package in "${packages[@]}"; do

        if ! rpm -q "$package" >/dev/null 2>&1; then
            missing=1
            break
        fi

    done

    if (( missing == 1 )); then

        log "Installing required packages..."

        dnf install -y \
            "${packages[@]}" \
            >/dev/null 2>&1
    fi

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command partprobe
    require_command resize2fs
    require_command fallocate
    require_command blkid
    require_command mkswap
    require_command swapon
    require_command swapoff
}

# ARCH REQUIREMENTS

install_arch_requirements() {

    local missing=0

    command -v growpart >/dev/null 2>&1 || missing=1
    command -v pvresize >/dev/null 2>&1 || missing=1
    command -v lvextend >/dev/null 2>&1 || missing=1
    command -v resize2fs >/dev/null 2>&1 || missing=1
    command -v partprobe >/dev/null 2>&1 || missing=1
    command -v fallocate >/dev/null 2>&1 || missing=1
    command -v blkid >/dev/null 2>&1 || missing=1
    command -v mkswap >/dev/null 2>&1 || missing=1
    command -v swapon >/dev/null 2>&1 || missing=1
    command -v swapoff >/dev/null 2>&1 || missing=1

    if (( missing == 1 )); then

        log "Installing required packages..."

        pacman -Sy --noconfirm archlinux-keyring \
            >/dev/null 2>&1 || true

        pacman -S --noconfirm \
            cloud-guest-utils \
            e2fsprogs \
            lvm2 \
            parted \
            xfsprogs \
            util-linux \
            >/dev/null 2>&1
    fi

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command resize2fs
    require_command partprobe
    require_command fallocate
    require_command blkid
    require_command mkswap
    require_command swapon
    require_command swapoff
}

# RESCAN DISK

rescan_disk() {

    local disk_name

    disk_name=$(basename "$DISK")

    if [[ -w "/sys/class/block/$disk_name/device/rescan" ]]; then
        echo 1 > "/sys/class/block/$disk_name/device/rescan"
    fi

    partprobe "$DISK" >/dev/null 2>&1 || true

    udevadm settle >/dev/null 2>&1 || true

    sleep 2
}

# DETECT LVM

detect_lvm() {

    ROOT_SOURCE=$(findmnt -n -o SOURCE /)
    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    if ! lvs "$ROOT_SOURCE" >/dev/null 2>&1; then
        error "Root filesystem is not an LVM logical volume."
    fi

    VG=$(lvs --noheadings -o vg_name "$ROOT_SOURCE" | xargs)

    [[ -n "$VG" ]] || \
        error "Unable to determine Volume Group."

    PV=$(pvs \
        --noheadings \
        -o pv_name \
        --select "vg_name=$VG" |
        head -1 |
        xargs)

    [[ -n "$PV" ]] || \
        error "Unable to determine Physical Volume."

    DISK="/dev/$(lsblk -dn -o PKNAME "$PV" | xargs)"

    [[ -b "$DISK" ]] || \
        error "Unable to determine physical disk."

    local device

    device=$(basename "$PV")

    if [[ "$device" =~ ^nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    elif [[ "$device" =~ ^mmcblk[0-9]+p([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    elif [[ "$device" =~ ^[a-z]+([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    else

        error "Unable to determine partition number."

    fi
}

# CHECK ADDITIONAL SPACE

has_additional_space() {

    local disk_size
    local partition_size

    disk_size=$(blockdev --getsize64 "$DISK")
    partition_size=$(blockdev --getsize64 "$PV")

    (( disk_size > partition_size ))
}

# GROW PARTITION

grow_partition() {

    local disk_sectors
    local partition_sectors
    local difference
    local output
    local status

    disk_sectors=$(blockdev --getsz "$DISK")
    partition_sectors=$(blockdev --getsz "$PV")

    difference=$((disk_sectors - partition_sectors))

    if (( difference <= 2048 )); then
        NO_RESIZE_NEEDED=1
        return 0
    fi

    if output=$(growpart "$DISK" "$PARTITION" 2>&1); then
        status=0
    else
        status=$?
    fi

    if echo "$output" | grep -q "NOCHANGE"; then
        NO_RESIZE_NEEDED=1
        return 0
    fi

    if (( status != 0 )); then
        echo "$output" >&2
        error "Unable to extend partition."
    fi

    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true
    sleep 2
}

# RESIZE PV

resize_pv() {

    pvresize "$PV" >/dev/null 2>&1
}

# EXTEND ROOT LV

extend_root_lv() {

    local free_extents

    free_extents=$(vgs \
        --noheadings \
        -o vg_free_count \
        "$VG" |
        xargs)

    if [[ "$free_extents" == "0" ]]; then
        return 0
    fi

    lvextend -l +100%FREE "$ROOT_SOURCE" >/dev/null 2>&1
}

# EXT4

grow_ext4() {

    resize2fs "$ROOT_SOURCE" >/dev/null 2>&1
}

# XFS

grow_xfs() {

    xfs_growfs / >/dev/null 2>&1
}

# STORAGE LAYOUT

root_uses_lvm() {
    local root
    root=$(findmnt -n -o SOURCE /)
    lvs "$root" >/dev/null 2>&1
}

detect_plain_root() {
    local device

    ROOT_SOURCE=$(findmnt -n -o SOURCE /)
    FILESYSTEM=$(findmnt -n -o FSTYPE /)
    [[ -b "$ROOT_SOURCE" ]] || error "Root source is not a block device: $ROOT_SOURCE"

    DISK="/dev/$(lsblk -dn -o PKNAME "$ROOT_SOURCE" | head -1 | xargs)"
    [[ -b "$DISK" ]] || error "Unable to determine the disk for $ROOT_SOURCE."

    device=$(basename "$ROOT_SOURCE")
    PARTITION=${device##*[!0-9]}
    [[ "$PARTITION" =~ ^[0-9]+$ ]] || error "Unable to determine the root partition number."
}

migrate_trailing_swap() {
    local part number start kind type uuid root_end swap_bytes=0
    local -a swaps=()
    local -a extended_partitions=()

    root_end=$(parted -ms "$DISK" unit s print 2>/dev/null | awk -F: -v p="$PARTITION" '$1 == p {gsub("s", "", $3); print $3; exit}')
    [[ "$root_end" =~ ^[0-9]+$ ]] || error 'Unable to determine the root partition boundary.'

    while IFS=: read -r number start _ _ kind _; do
        [[ "$number" =~ ^[0-9]+$ ]] || continue
        start=${start%s}
        [[ "$start" =~ ^[0-9]+$ ]] || continue
        (( start > root_end )) || continue
        if [[ "$kind" == extended ]]; then
            extended_partitions+=("$number")
            continue
        fi
        if [[ "$DISK" =~ nvme|mmcblk ]]; then part="${DISK}p${number}"; else part="${DISK}${number}"; fi
        type=$(blkid -s TYPE -o value "$part" 2>/dev/null || true)
        [[ "$type" == swap ]] || error "Partition $part follows the root partition and is not swap; it cannot be moved safely."
        swaps+=("$part:$number")
        swap_bytes=$((swap_bytes + $(blockdev --getsize64 "$part")))
    done < <(parted -ms "$DISK" unit s print 2>/dev/null | tail -n +3)

    (( ${#swaps[@]} )) || return 0
    [[ ! -e /swapfile ]] || error '/swapfile already exists; refusing to replace the swap partition.'
    log "Replacing trailing swap partition with a persistent $(human_size "$swap_bytes") swap file."
    cp -a /etc/fstab /etc/fstab.disk-resizer.bak

    fallocate -l "$swap_bytes" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    for part in "${swaps[@]}"; do
        number=${part##*:}
        part=${part%:*}
        swapoff "$part" 2>/dev/null || true
        uuid=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
        [[ -z "$uuid" ]] || sed -i "\|$uuid|d" /etc/fstab
        sed -i "\|$part|d" /etc/fstab
        parted -s "$DISK" rm "$number"
    done
    for number in "${extended_partitions[@]}"; do
        parted -s "$DISK" rm "$number"
    done
    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true

    growpart "$DISK" "$PARTITION" >/dev/null
    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true
    sleep 2

    case "$FILESYSTEM" in
        ext2|ext3|ext4) resize2fs "$ROOT_SOURCE" >/dev/null ;;
        xfs) xfs_growfs / >/dev/null ;;
        *) error "Unsupported filesystem: $FILESYSTEM" ;;
    esac
}

resize_plain_root() {
    local disk_sectors root_end last_end added_sectors

    detect_plain_root
    capture_initial_disk
    rescan_disk

    disk_sectors=$(blockdev --getsz "$DISK")
    root_end=$(parted -ms "$DISK" unit s print 2>/dev/null | awk -F: -v p="$PARTITION" '$1 == p {gsub("s", "", $3); print $3; exit}')
    last_end=$(parted -ms "$DISK" unit s print 2>/dev/null | awk -F: '$1 ~ /^[0-9]+$/ {gsub("s", "", $3); if ($3 > end) end=$3} END {print end}')
    [[ "$root_end" =~ ^[0-9]+$ && "$last_end" =~ ^[0-9]+$ ]] || error 'Unable to determine partition boundaries.'
    if (( last_end > root_end )); then
        added_sectors=$((disk_sectors - last_end - 1))
    else
        added_sectors=$((disk_sectors - root_end - 1))
    fi
    (( added_sectors > 2048 )) || { final_no_resize; return 0; }

    prepare_resize_confirmation "$((added_sectors * 512))"

    if (( last_end > root_end )); then
        migrate_trailing_swap
    else
        growpart "$DISK" "$PARTITION" >/dev/null
        partprobe "$DISK" >/dev/null 2>&1 || true
        udevadm settle >/dev/null 2>&1 || true
        sleep 2
        case "$FILESYSTEM" in
            ext2|ext3|ext4) resize2fs "$ROOT_SOURCE" >/dev/null ;;
            xfs) xfs_growfs / >/dev/null ;;
            *) error "Unsupported filesystem: $FILESYSTEM" ;;
        esac
    fi

    final_success
}

# UBUNTU 22

resize_ubuntu22() {

    ROOT_SOURCE=$(findmnt -n -o SOURCE /)
    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    DISK="/dev/$(lsblk -dn -o PKNAME "$ROOT_SOURCE" | xargs)"

    [[ -b "$DISK" ]] || \
        error "Unable to determine disk."

    local device

    device=$(basename "$ROOT_SOURCE")

    if [[ "$device" =~ ^nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    elif [[ "$device" =~ ^[a-z]+([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    else

        error "Unable to determine partition."

    fi

    capture_initial_disk

    rescan_disk

    local disk_size
    local partition_size

    disk_size=$(blockdev --getsize64 "$DISK")
    partition_size=$(blockdev --getsize64 "$ROOT_SOURCE")

    if (( disk_size <= partition_size )); then

        final_no_resize
        return 0

    fi

    if ! preflight_growpart "$DISK" "$PARTITION"; then
        final_no_resize
        return 0
    fi

    local disk_sectors
    local partition_start
    local partition_sectors
    local added_sectors

    disk_sectors=$(blockdev --getsz "$DISK")
    partition_start=$(lsblk -no START "$ROOT_SOURCE" | head -1 | xargs)
    partition_sectors=$(blockdev --getsz "$ROOT_SOURCE")
    added_sectors=$((disk_sectors - partition_start - partition_sectors))
    prepare_resize_confirmation "$((added_sectors * 512))"

    if ! growpart "$DISK" "$PARTITION" >/dev/null 2>&1; then

        final_no_resize
        return 0

    fi

    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true
    sleep 2

    resize2fs "$ROOT_SOURCE" >/dev/null 2>&1

    final_success
}

# UBUNTU 24 / 26

resize_ubuntu_lvm() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    if ! preflight_growpart "$DISK" "$PARTITION"; then
        final_no_resize
        return 0
    fi

    local current_bytes
    local total_bytes
    local added_bytes

    current_bytes=$(blockdev --getsize64 "$PV")
    total_bytes=$(blockdev --getsize64 "$DISK")
    added_bytes=$((total_bytes - current_bytes))

    (( added_bytes > 0 )) || {
        final_no_resize
        return 0
    }

    prepare_resize_confirmation "$added_bytes"

    grow_partition

    if [[ "$NO_RESIZE_NEEDED" == "1" ]]; then

        final_no_resize
        return 0

    fi

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

# DEBIAN 11 / 12 / 13

resize_debian_generic() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected Debian root filesystem."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    local table_type

    table_type=$(parted -ms "$DISK" print 2>/dev/null |
        awk -F: 'NR==2 {print $6}')

    if [[ "$table_type" == "msdos" ]]; then

        if (( PARTITION >= 5 )); then

            local extended_output=""
            local logical_output=""

            if ! preflight_growpart "$DISK" 2; then
                final_no_resize
                return 0
            fi

            prepare_resize_confirmation "$(( $(blockdev --getsize64 "$DISK") - $(blockdev --getsize64 "$PV") ))"

            extended_output=$(growpart "$DISK" 2 2>&1) || true

            if echo "$extended_output" | grep -q "NOCHANGE"; then

                final_no_resize
                return 0

            fi

            if ! echo "$extended_output" | grep -q "CHANGED"; then

                echo "$extended_output" >&2
                error "Unable to extend Debian extended partition."

            fi

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true
            sleep 2

            logical_output=$(growpart \
                "$DISK" \
                "$PARTITION" \
                2>&1) || true

            if echo "$logical_output" | grep -q "NOCHANGE"; then

                final_no_resize
                return 0

            fi

            if ! echo "$logical_output" | grep -q "CHANGED"; then

                echo "$logical_output" >&2
                error "Unable to extend Debian LVM partition."

            fi

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true
            sleep 2

        else

            local primary_output=""

            if ! preflight_growpart "$DISK" "$PARTITION"; then
                final_no_resize
                return 0
            fi

            prepare_resize_confirmation "$(( $(blockdev --getsize64 "$DISK") - $(blockdev --getsize64 "$PV") ))"

            primary_output=$(growpart \
                "$DISK" \
                "$PARTITION" \
                2>&1) || true

            if echo "$primary_output" | grep -q "NOCHANGE"; then

                final_no_resize
                return 0

            fi

            if ! echo "$primary_output" | grep -q "CHANGED"; then

                echo "$primary_output" >&2
                error "Unable to extend Debian LVM partition."

            fi

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true
            sleep 2

        fi

    elif [[ "$table_type" == "gpt" ]]; then

        local gpt_output=""

        if ! preflight_growpart "$DISK" "$PARTITION"; then
            final_no_resize
            return 0
        fi

        prepare_resize_confirmation "$(( $(blockdev --getsize64 "$DISK") - $(blockdev --getsize64 "$PV") ))"

        gpt_output=$(growpart \
            "$DISK" \
            "$PARTITION" \
            2>&1) || true

        if echo "$gpt_output" | grep -q "NOCHANGE"; then

            final_no_resize
            return 0

        fi

        if ! echo "$gpt_output" | grep -q "CHANGED"; then

            echo "$gpt_output" >&2
            error "Unable to extend Debian LVM partition."

        fi

        partprobe "$DISK" >/dev/null 2>&1 || true
        udevadm settle >/dev/null 2>&1 || true
        sleep 2

    else

        error "Unsupported Debian partition table."

    fi

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

# FEDORA / CENTOS / ALMALINUX / ROCKY

resize_rhel_xfs() {

    detect_lvm

    [[ "$FILESYSTEM" == "xfs" ]] || \
        error "Unexpected filesystem."

    capture_initial_disk

    rescan_disk

    local disk_sectors
    local pv_end_sector
    local available_sectors
    local minimum_growth

    disk_sectors=$(blockdev --getsz "$DISK")

    pv_end_sector=$(parted -ms "$DISK" unit s print 2>/dev/null |
        awk -F: -v p="$PARTITION" '
            $1 == p {
                gsub("s","",$3)
                print $3
                exit
            }
        ')

    if [[ -z "$pv_end_sector" ]]; then

        error "Unable to determine LVM partition boundary."

    fi

    available_sectors=$((disk_sectors - pv_end_sector - 1))

    minimum_growth=2048

    if (( available_sectors <= minimum_growth )); then

        final_no_resize
        return 0

    fi

    log "Additional storage detected."

    prepare_resize_confirmation "$((available_sectors * 512))"

    local placeholder

    if [[ "$DISK" =~ nvme|mmcblk ]]; then

        placeholder="${DISK}p4"

    else

        placeholder="${DISK}4"

    fi

    if [[ -b "$placeholder" ]]; then

        local placeholder_size

        placeholder_size=$(blockdev --getsize64 "$placeholder")

        if (( placeholder_size <= 4096 )); then

            parted -s "$DISK" rm 4 >/dev/null 2>&1 || true

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true

            sleep 2

        else

            error "Unexpected partition 4 detected."

        fi
    fi

    local output=""
    local status=0

    if output=$(growpart "$DISK" "$PARTITION" 2>&1); then

        status=0

    else

        status=$?

    fi

    if echo "$output" | grep -q "NOCHANGE"; then

        final_no_resize
        return 0

    fi

    if (( status != 0 )); then

        echo "$output" >&2

        error "Unable to extend LVM partition."

    fi

    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true

    sleep 2

    resize_pv
    extend_root_lv
    grow_xfs

    final_success
}

# ARCH LINUX

resize_arch() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    if ! preflight_growpart "$DISK" "$PARTITION"; then
        final_no_resize
        return 0
    fi

    prepare_resize_confirmation "$(( $(blockdev --getsize64 "$DISK") - $(blockdev --getsize64 "$PV") ))"

    grow_partition

    if [[ "$NO_RESIZE_NEEDED" == "1" ]]; then

        final_no_resize
        return 0

    fi

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

# MAIN

main() {
    check_root
    detect_os

    case "$OS_ID" in
        ubuntu)
            install_apt_requirements
            if root_uses_lvm; then resize_ubuntu_lvm; else resize_plain_root; fi
            ;;
        debian)
            install_apt_requirements
            if root_uses_lvm; then resize_debian_generic; else resize_plain_root; fi
            ;;
        fedora|centos|almalinux|rocky)
            install_dnf_requirements
            if root_uses_lvm; then resize_rhel_xfs; else resize_plain_root; fi
            ;;
        arch)
            install_arch_requirements
            if root_uses_lvm; then resize_arch; else resize_plain_root; fi
            ;;
        *)
            error "Unsupported operating system."
            ;;
    esac
}

# RUN

main "$@"
