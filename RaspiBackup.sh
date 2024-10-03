#!/bin/bash
#
# Utility script to backup Raspberry Pi's SD Card to a sparse image file
# mounted as a filesystem in a file, allowing for efficient incremental
# backups using rsync
#
# The backup is taken while the system is up, so it's a good idea to stop
# programs and services which modifies the filesystem and needed a consistant state
# of their file.
# Especially applications which use databases needs to be stopped (and the database systems too).
#
#  So it's a smart idea to put all these stop commands in a script and perfom it before
#  starting the backup. Or put the system into rescue mode using 'systemctl rescue'. 
#  After the backup terminates normally you may restart all stopped
#  applications or just reboot the system.
# 
# https://github.com/dolorosus/RaspiBackup
#
#
# in case COLORS.sh is missing
msgok() {
    echo -e "${TICK} ${1}${NOATT}"
}
msg() {
    echo -e "${IDENT} ${1}${NOATT}"
}
msgwarn() {
    echo -e "${WARN} ${1}${NOATT}"
}
# Echos an error string in red text and exit
msgfail() {
    echo -e "${CROSS} ${1}${NOATT}" >&2
    exit 1
}

# Creates a sparse "${IMAGE}"  and attaches to ${LOOPBACK}
# shellcheck disable=SC2120
do_create() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}    (${*})\n"

    msg "Creating sparse ${IMAGE}, of ${SIZE}M"
    dd if=/dev/zero of="${IMAGE}" bs=${BLOCKSIZE} count=0 seek=${SIZE}

    if [ -s "${IMAGE}" ]; then
        msg "Attaching ${IMAGE} to ${LOOPBACK}"
        losetup "${LOOPBACK}" "${IMAGE}"
    else
        msgfail "${IMAGE} has not been created or has zero size"
    fi

    if [ "${PARTSCHEME}" == "GPT" ]; then
        #
        # Use this on your own risk!
        #
        msg "Creating partitions on ${LOOPBACK} using GTP scheme"
        parted -s "${LOOPBACK}" mktable gpt
        parted -s "${LOOPBACK}" mkpart "BOOT" fat32 4MiB ${BOOTSIZE}MiB
        parted -s "${LOOPBACK}" mkpart "ROOT" ext4 ${BOOTSIZE}MiB 100%
        parted -s "${LOOPBACK}" set 1 legacy_boot on
    else
        msg "Creating partitions on ${LOOPBACK}"
        parted -s "${LOOPBACK}" mktable msdos
        parted -s "${LOOPBACK}" mkpart primary fat32 4MiB ${BOOTSIZE}MiB
        parted -s "${LOOPBACK}" mkpart primary ext4 ${BOOTSIZE}MiB 100%
        parted -s "${LOOPBACK}" set 1 boot on
    fi

    msg "Formatting partitions"
    partx --add "${LOOPBACK}"
    mkfs.vfat -n BOOT -F32 "${LOOPBACK}"p1
    mkfs.ext4 "${LOOPBACK}"p2
}

# shellcheck disable=SC2120
change_bootenv() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    
    local editmanual=false
    local fstab_tmp=/tmp/fstab.$$
    local cmdline_tmp=/tmp/cmdline.$$
    mount_boot
    mount_root
    #
    # create a working copy of /etc/fstab
    #
    cp /etc/fstab $fstab_tmp
    #
    # assuming we have two partitions (/boot and /) ...
    #
    local -r BOOTDEV=$(findmnt --uniq --canonicalize --noheadings --output=SOURCE "${BOOTMP}") || msgfail "Could not find device for /boot"
    local -r ROOTDEV=$(findmnt --uniq --canonicalize --noheadings --output=SOURCE /) || msgfail "Could not find device for /"

    local -r BootPARTUUID=$(lsblk -n -o PARTUUID "${BOOTDEV}") || {
        msg "Could not find PARTUUID of ${BOOTDEV}"
        editmanual=true
    }
    local -r RootPARTUUID=$(lsblk -n -o PARTUUID "${ROOTDEV}") || {
        msg "Could not find PARTUUID of ${ROOTDEV}"
        editmanual=true
    }
    local -r dstBootPARTUUID=$(lsblk -n -o PARTUUID "${LOOPBACK}p1") || {
        msg "Could not find PARTUUID of ${LOOPBACK}p1"
        editmanual=true
    }
    local -r dstRootPARTUUID=$(lsblk -n -o PARTUUID "${LOOPBACK}p2") || {
        msg "Could not find PARTUUID of ${LOOPBACK}p2"
        editmanual=true
    }

    change_PARTUUID "${BootPARTUUID}" "$dstBootPARTUUID" "$fstab_tmp"
    #
    # Let' look if our partuuid for src is in fstab, if true then change the PARTUUID to
    #  the PARTUUID of the backup
    #
    change_PARTUUID "${RootPARTUUID}" "$dstRootPARTUUID" "$fstab_tmp"
    #
    # Something went wrong automatically changing wasn't possible
    # Now the Uuser has a second chance
    if ${editmanual}; then
        msgwarn "fstab cannot be changed automatically."
        msgwarn "correct fstab on destination manually."
        editmanual=false
    else
        cp "$fstab_tmp" "${MOUNTDIR}/etc/fstab"
        msgok "PARTUUIDs changed successful in ${MOUNTDIR}/etc/fstab"
    fi
    #
    # Changing /boot/cmdline.txt
    #

    cp "${BOOTMP}/cmdline.txt" "$cmdline_tmp" || {
        msgwarn "could not copy ${BOOTMP}/cmdline.txt to $cmdline_tmp"
        editmanual=true
    }
    change_PARTUUID "${RootPARTUUID}" "${dstRootPARTUUID}" "${cmdline_tmp}"

    if ${editmanual}; then
        msgwarn "cmdline.txt cannot be changed automatically."
        msgwarn "correct cmdline.txt on destination manually."
    else
        cp "$cmdline_tmp" "${MOUNTDIR}/${BOOTMP}/cmdline.txt"
        msgok "PARTUUID changed successful in ${MOUNTDIR}/${BOOTMP}/cmdline.txt"
    fi
}

change_PARTUUID() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    [ -z "${1}" -o -z "${2}" -o -z "${3}" ] && {
        echo "${FUNCNAME[*]}   Parameter_:${*}"
        echo "msgfail either par1 or par2 or par3 is empty"
        return 1
    }

    local -r srcUUID="${1}"
    local -r dstUUID="${2}"
    local -r file="${3}"

    grep -q "PARTUUID=${srcUUID}" "${file}" && {
        msg "Changeing PARTUUID from ${srcUUID} to ${dstUUID} in ${file}"
        sed -i "s/PARTUUID=${srcUUID}/PARTUUID=${dstUUID}/" "${file}" || {
            msgwarn "PARTUUID ${srcUUID} has not been changed in  ${file}"
            editmanual=true
        } || {
            msgwarn "PARTUUID=${srcUUID} not found in ${file}"
            editmanual=true
        }
    }
}

# Mounts the ${IMAGE} to ${LOOPBACK} (if needed) and ${MOUNTDIR}
# shellcheck disable=SC2120
do_mount() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    # Check if do_create has already attached the SD Image
    [ "$(losetup -f)" = "${LOOPBACK}" ] && {
        msg "Attaching ${IMAGE} to ${LOOPBACK}"
        losetup "${LOOPBACK}" "${IMAGE}"
        partx --add "${LOOPBACK}"
    }
    mount_root
    mount_boot
}
mount_boot() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}     ${*}"
    msg "Mounting ${LOOPBACK}p1  to ${MOUNTDIR}/${BOOTMP}"
    mkdir -p "${MOUNTDIR}/${BOOTMP}"&>/dev/null
    mount "${LOOPBACK}p1" "${MOUNTDIR}/${BOOTMP}"
}

mount_root() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}     ${*}"
    msg "Mounting ${LOOPBACK}p2 to ${MOUNTDIR}"
    mkdir -p "${MOUNTDIR}"&>/dev/null
    mount "${LOOPBACK}p2" "${MOUNTDIR}"
}

# Unmounts the ${IMAGE} from ${MOUNTDIR} and ${LOOPBACK}
# shellcheck disable=SC2120
do_umount() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}     ${*}"

    msg "Flushing to disk"
    sync

    umount_boot
    umount_root
    rmdir "${MOUNTDIR}"

    msg "Detaching ${IMAGE} from ${LOOPBACK}"
    partx --delete "${LOOPBACK}"
    losetup -d "${LOOPBACK}"
}

umount_boot() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}     ${*}"

    msg "Flushing to disk"
    sync
    msg "Unmounting ${LOOPBACK}p1 from ${MOUNTDIR}/${BOOTMP}"
    umount "${MOUNTDIR}/${BOOTMP}"

}

umount_root() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}     ${*}"

    msg "Flushing to disk"
    sync
    msg "Unmounting ${LOOPBACK}p2 from ${MOUNTDIR}"
    umount "${MOUNTDIR}"
}

# shellcheck disable=SC2120
do_check() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    local err

    # Check if do_create already attached the SD Image
    [ "$(losetup -f)" = "${LOOPBACK}" ] && {
        msg "Attaching ${IMAGE} to ${LOOPBACK}"
        losetup "${LOOPBACK}" "${IMAGE}"
        partx --add "${LOOPBACK}"
    }

    err=0

    fsck -y "${LOOPBACK}p1" || {
        msgwarn "Checking ${BOOTMP} failed"
        err=1
    }

    fsck -y "${LOOPBACK}p2" || {
        msgwarn "Checking / failed"
        err=2
    }

    msg "Detaching ${IMAGE} from ${LOOPBACK}"
    partx --delete "${LOOPBACK}"
    losetup -d "${LOOPBACK}"

    return ${err}
}

# shellcheck disable=SC2120
do_backup() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    local rsyncopt

    rsyncopt="-aEvx --del --stats"
    [ -n "${opt_log}" ] && rsyncopt="$rsyncopt --log-file ${LOG}"
    if mountpoint -q "${MOUNTDIR}"; then
        msg "Starting rsync backup of / and ${BOOTMP} to ${MOUNTDIR}"
        msg "rsync ${rsyncopt} ${BOOTMP}/ ${MOUNTDIR}/${BOOTMP}"
        rsync ${rsyncopt} "${BOOTMP}/" "${MOUNTDIR}/${BOOTMP}"
        umount_boot

        msg "\nrsync / to ${MOUNTDIR}"
        rsync ${rsyncopt} --exclude='.gvfs/**' \
            --exclude='tmp/**' \
            --exclude='proc/**' \
            --exclude='run/**' \
            --exclude='sys/**' \
            --exclude='mnt/**' \
            --exclude='lost+found/**' \
            --exclude='var/swap/**' \
            --exclude='var/log/**' \
            --exclude='home/*/.cache/**' \
            --exclude='root/.cache/**' \
            --exclude='var/cache/apt/archives/**' \
            --exclude='home/*/.vscode-server/**' \
            / "${MOUNTDIR}"/
    else
        msg "Skipping rsync since ${MOUNTDIR} is not a mount point"
    fi
}

# shellcheck disable=SC2120
do_showdf() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    msg ""
    df -mh "${LOOPBACK}p1" "${LOOPBACK}p2"
    msg ""
}

#
# resize image
#
# shellcheck disable=SC2120
do_resize() {

    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    local addsize=${1:-1000}

    do_check || msgfail "Filesystemcheck failed. Resize aborted."

    do_umount >/dev/null 2>&1

    msg "increasing size of ${IMAGE} by ${SIZE}M"
    truncate --size=+${addsize}M "${IMAGE}" || msgfail "Error adding ${addsize}M to ${IMAGE}"

    losetup "${LOOPBACK}" "${IMAGE}"
    partx --add "${LOOPBACK}"

    msg "resize partition 2 of ${IMAGE}"
    parted -sf "${LOOPBACK}" resizepart 2 100%

    msg "expanding filesystem"
    e2fsck -pf ${LOOPBACK}p2
    resize2fs ${LOOPBACK}p2

    msg "Detaching ${IMAGE} from ${LOOPBACK}"
    partx --delete ${LOOPBACK}
    losetup -d ${LOOPBACK}

}

# Tries to cleanup after Ctrl-C interrupt
ctrl_c() {
    [ "${DEBqUG}" ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

    if [ -s "${IMAGE}.gz.tmp" ]; then
        rm "${IMAGE}.gz.tmp"
    else
        do_umount
    fi

    [ -n "${opt_log}" ] && msg "See rsync log in ${LOG}"

    msgfail "SD Image backup process interrupted"
}

# Prints usage information
# shellcheck disable=SC2120
usage() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}     (${*})\n"

    cat <<EOF
    ${MYNAME}

    Usage:

        ${MYNAME} ${BOLD}start${NOATT} [-clzdf] [-L logfile]  sdimage
        ${MYNAME} ${BOLD}mount${NOATT} [-c] sdimage [mountdir]
        ${MYNAME} ${BOLD}umount${NOATT} sdimage [mountdir]
        ${MYNAME} ${BOLD}check${NOATT} sdimage
        ${MYNAME} ${BOLD}showdf${NOATT} sdimage
        ${MYNAME} ${BOLD}resize${NOATT} [-r Mb] sdimage

        Commands:

            ${BOLD}start${NOATT}      starts complete backup of RPi's SD Card to 'sdimage'
            ${BOLD}mount${NOATT}      mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
            ${BOLD}umount${NOATT}     unmounts the 'sdimage' from 'mountdir'
            ${BOLD}chbootenv${NOATT}  changes PARTUUID entries in fstab and cmdline.txt in the image
            ${BOLD}showdf${NOATT}     shows allocation of the image
            ${BOLD}check${NOATT}      check the filesystems of sdimage
            ${BOLD}resize${NOATT}     expand the image

        Options:

            ${BOLD}-c${NOATT}         creates the SD Image if it does not exist
            ${BOLD}-l${NOATT}         writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
            ${BOLD}-L logfile${NOATT} writes rsync log to 'logfile'
            ${BOLD}-s Mb${NOATT}      specifies the size of image in MB (default: 250M+ size of / +500M) )
            ${BOLD}-r Mb${NOATT}      the image will be resized by this amount of megabytes

    Examples:

        ${MYNAME} start -c /path/to/rpi_backup.img
            starts backup to 'rpi_backup.img', creating it if it does not exist

        ${MYNAME} start -c -s 8000 /path/to/rpi_backup.img
            starts backup to 'rpi_backup.img', creating it
            with a size of 8000mb if it does not exist

        ${MYNAME} start /path/to/\$(uname -n).img
            uses the RPi's hostname as the SD Image filename

        ${MYNAME} resize  /path/to/rpi_backup.img
            expand rpi_backup.img by 1000M

        ${MYNAME} resize -s 2000 /path/to/rpi_backup.img
            expand rpi_backup.img by 2000M

        ${MYNAME} mount /path/to/\$(uname -n).img /mnt/rpi_image
            mounts the RPi's SD Image in /mnt/rpi_image

EOF
}

#####################################################################################################
# Main
#####################################################################################################
exec &> >(tee "${0%%.sh}.out")
mypath=$(readlink -f "${0}")
#
TICK="[ok]"
CROSS="[X] "
INFO="[i]"
WARN="[w]"
QST="[?]"
IDENT="$   "

colors=${mypath%%"${mypath##*/}"}COLORS.sh
[ -f "${colors}" ] && . "${colors}"

# Make sure we have root rights
[ ${EUID} -eq 0 ] || msgfail "Sorry user, I'm afraid I can't do this... Please run as root. Try sudo !!"
#
# Check for dependencies
#
for c in dd losetup parted partx mkfs.vfat mkfs.ext4 mountpoint rsync lsblk; do
    command -v ${c} >/dev/null 2>&1 || msgfail "Required program ${c} is not installed"
done

# Read the command from command line
case "${1}" in

start | mount | umount | check | chbootenv | showdf | resize)
    opt_command=${1}
    ;;

"-h" | "--help")
    usage
    exit 0
    ;;
*)
    msgfail "Invalid command or option: ${1}\nSee '${MYNAME} --help for usage"
    ;;
esac
shift 1

# Read the options from command line
while getopts ":cdlL:i:r:s:" opt; do
    case ${opt} in
    c) opt_create=1 ;;
    d) opt_delete=1 ;;
    l) opt_log=1 ;;
    L)
        opt_log=1
        LOG=${OPTARG}
        ;;
    r) RSIZE=${OPTARG} ;;
    s) SIZEARG=${OPTARG} ;;
    i) msgwarn "-i is no longer used. The source will always be the boot device" ;;

    \?) msgfail "Invalid option: -${OPTARG}\nSee '${MYNAME} --help' for usage" ;;
    :) msgfail "Option -${OPTARG} requires an argument\nSee '${MYNAME} --help' for usage" ;;
    esac
done
shift $((OPTIND - 1))
#
# setting defaults
#
declare -gxr BOOTSIZE=550
declare -gxr ROOTSIZE=$(df -m --output=used / | tail -1) || msgfail "size of / could not determined"
declare -gxr SIZE=${SIZEARG:-$((BOOTSIZE + ROOTSIZE + 1000))} || msgfail "size of imagefile could not calculated"
declare -gxr RSIZE=${RSIZE:-1000}
declare -gxr BLOCKSIZE=1M
declare -gxr PARTSCHEME="GPT"

 mountpoint -q "/boot/firmware"  && declare -gxr BOOTMP="/boot/firmware"
 mountpoint -q "/boot"  && declare -gxr BOOTMP="/boot"
[ -z ${BOOTMP} ] && msgfail "could not find mountpoint for boot partition"

#
# Preflight checks
#
# Read the sdimage path from command line
#   and check for existance
#
declare -r IMAGE=${1}
[ -z "${IMAGE}" ] && msgfail "No sdimage specified"

# Check if image exists
if [ "${opt_command}" = umount ] || [ "${opt_command}" = gzip ]; then
    [ -f "${IMAGE}" ] || msgfail "${IMAGE} does not exist"
else
    if [ ! -f "${IMAGE}" ] && [ ! -n "${opt_create}" ]; then
        msgfail "${IMAGE} does not exist\nUse -c to allow creation"
    fi
fi

#
# Identify which loopback device to use
#
LOOPBACK=$(losetup -j "${IMAGE}" | grep -o ^[^:]*)
if [ "${opt_command}" = "umount" ]; then
    [ -z "${LOOPBACK}" ] && msgfail "No /dev/loop<X> attached to ${IMAGE}"
elif [ ! -z "${LOOPBACK}" ]; then
    msgfail "${IMAGE} already attached to ${LOOPBACK} mounted on $(grep ${LOOPBACK}p2 /etc/mtab | cut -d ' ' -f 2)/"
else
    LOOPBACK=$(losetup -f)
fi

#
# Read the optional mountdir from command line
#
MOUNTDIR="${2}"
if [ -z "${MOUNTDIR}" ]; then
    MOUNTDIR=/mnt/$(basename "${IMAGE}")/
    readonly MOUNTDIR
else
    opt_mountdir=1
    [ -d "${MOUNTDIR}" ] || msgfail "Mount point ${MOUNTDIR} does not exist"
fi

# Check if default mount point exists
if [ "${opt_command}" = "umount" ]; then
    [ -d "${MOUNTDIR}" ] || msgfail "Default mount point ${MOUNTDIR} does not exist"
else
    if [ -z "${opt_mountdir}" ] && [ -d "${MOUNTDIR}" ]; then
        msgfail "Default mount point ${MOUNTDIR} already exists"
    fi
fi

#####################################################################################################
#
#  All preflight checks done
#
#####################################################################################################
#
# Trap keyboard interrupt (ctrl-c)
trap ctrl_c SIGINT SIGTERM

# Do the requested functionality
case ${opt_command} in
start)
    msg "Starting SD Image backup process"
    if [ ! -f "${IMAGE}" ] && [ -n "${opt_create}" ]; then
        do_create
    fi
    do_mount
    do_backup
    change_bootenv
    do_showdf
    do_umount
    msgok "SD Image backup process completed."
    if [ -n "${opt_log}" ]; then
        msg "See rsync log in ${LOG}"
    fi
    ;;
mount)
    if [ ! -f "${IMAGE}" ] && [ -n "${opt_create}" ]; then
        do_create
    fi
    do_mount
    msgok "SD Image has been mounted and can be accessed at:\n    ${MOUNTDIR}"
    ;;
umount)
    do_umount
    ;;
check)
    do_check
    ;;
chbootenv)
    do_mount
    change_bootenv
    do_umount
    ;;
showdf)
    do_mount
    do_showdf
    do_umount
    ;;
resize)
    do_resize "$RSIZE"
    ;;
*)
    msgfail "Unknown command: ${opt_command}"
    ;;
esac

exit 0
