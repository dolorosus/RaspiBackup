#!/bin/bash
#
#	*EXAMPLE* Script for daily backup
#
#	Before the backup takes place a snapshot of the current backupfile is taken.
#	This is done by calling a script $snapscript.
#	Using a snapshot supporting filesystem (btrfs,xfs...) is recommended
#	for the backupdestination. If BTRFS is used you may have a look to
#           https://github.com/dolorosus/btrfs-snapshot-rotation
#
#	After the snapshot is taken, the system will be isolated to rescue mode.
#   Thus results in:
#       - you will be no longer able to login from ssh
#       - existing login sessions remain unchanged.
#
#   Recommendation: use 'screen' or 'tmux' so that the backup will be finished
#   even if the connection fails.
#
#
#	Also you should take a closer look to *setup()*. Change the variables according
#	your filesystem structure.
#

exec &> >(tee "${0%%.sh}.out")
MYANME=${0##*/}

setup() {
    export skipcheck=${1:-"noskip"}
    export stamp=$(date +%y%m%d_%H%M%S)
    export destvol="/mnt/USB64"
    export destpath="${destvol}/BACKUPS"
    export snappath="${destvol}/.snapshots/BACKUPS"
    export bckprefix="MyRaspi4"
    export destpatt="${bckprefix}-2*_[0-9]*.img"
    export bcknewname="${bckprefix}-${stamp}.img"
    export tmppre="#"

    export bckscript="/home/pi/scripts/RaspiBackup.sh"
    export snapscript="/home/pi/scripts/btrfs-snapshot-rotation.sh"
    export mark="manual"
    export versions=7

}

msg() {
    echo "${IDENT} ${1}${NOATT}"
}
msgok() {
    echo "${TICK} ${1}${NOATT}"
}
orgname=$(readlink -f "${0}")
colors=${orgname%%${orgname##*/}}COLORS.sh
[ -f ${colors} ] && . ${colors}

errexit() {

    case "${1}" in
    1)
        echo "${CROSS} You have to be root to run this script${NOATT}"
        exit ${1}
        ;;

    10)
        echo "${CROSS} More than one backupfile according to ${destpath}/${destpatt} found."
        echo "Can't decide which one to use.${NOATT}"
        exit ${1}
        ;;

    11)
        echo "${CROSS} backupfile according to ${destpath}/${destpatt} is no flatfile.${NOATT}"
        exit ${1}
        ;;

    12)
        echo "${CROSS} backupfile according to ${destpath}/${destpatt} is empty.${NOATT}"
        exit ${1}
        ;;

    20)
        echo "${CROSS} No executable file $bckscript found.${NOATT}"
        exit ${1}
        ;;

    21)
        echo "${CROSS} No executable file $snapscript found.${NOATT}"
        exit ${1}
        ;;

    25)
        echo "${TICK} ${YELLOW}${action} $prog failed${NOATT}"
        ;;

    30)
        echo "${CROSS}vsomething went wrong..."
        echo "the incomplete backupfile is named: ${destpath}/${tmppre}${bcknewname}"
        echo "Resolve the issue, rename the the backupfile and restart"
        echo "Good luck!${NOATT}"
        exit ${1}
        ;;

    *)
        echo "${CROSS} An unknown error occured${NOATT}"
        exit 99
        ;;
    esac
}

progs() {

    local action=${1:=start}
    local grace=60
    local setopt=$-

    [ "${action}" == "stop" ] && {
        msg "System is put to rescue mode."
        systemctl isolate rescue
    }
    [ "${action}" == "start" ] && {
        msg "System is put to default mode."
        systemctl isolate default
    }
    msg "waiting for ${grace}s"
    for ((i = 0; i <= ${grace}; i++)); do
        echo -n '.'
        sleep 1s
    done
    echo ''
    msgok "done."

    return 0
}

do_inital_backup() {

    #
    # Determine how many blocks the backupfile needs and add some blocks for safety
    #
    local creopt="-c -s $(($(df -k --output=used / | tail -1) / 1024 + 550))"
    progs stop

    msg "starting backup_: ${bckscript} start ${creopt} ${destpath}/${tmppre}${bcknewname}"
    backup="ko"
    ${bckscript} start ${creopt} "${destpath}/${tmppre}${bcknewname}" && {
        msg "moving  ${destpath}/${tmppre}bcknewname} to ${destpath}/${bcknewname}"
        mv "${destpath}/${tmppre}${bcknewname}" "${destpath}/${bcknewname}"
        msgok "Backup successful"
        msg "Backupfile is_: ${destpath}/${bcknewname}"
        backup="ok"
    }

    progs start

    [ "${backup}" == "ok" ] && return 0
    errexit 30
}

do_backup() {

    local creopt="${1}"

    # move the destination to a temporary filename while
    # the backup is working
    [ -z "${creopt}" ] && {
        msg "Moving ${bckfile} to ${destpath}/${tmppre}${bcknewname}"
        mv "${bckfile}" "${destpath}/${tmppre}${bcknewname}"
    }
    msg "Starting backup_: ${bckscript} start ${creopt} ${destpath}/${tmppre}${bcknewname}"
    backup="ko"
    ${bckscript} start ${creopt} "${destpath}/${tmppre}${bcknewname}" && {
        backup="ok"
        msg "Moving  ${destpath}/${tmppre}${bcknewname} to ${destpath}/${bcknewname}"
        mv "${destpath}/${tmppre}${bcknewname}" "${destpath}/${bcknewname}"
        msgok "Backup successful"
        msg "Backupfile is_: ${destpath}/${bcknewname}"
    }

    progs start

    [ "${backup}" == "ok" ] && return 0
    errexit 30

}

# ===============================================================================================================
# Main
# ===============================================================================================================
#
# Please, do not disturb
#
trap "progs start" SIGTERM SIGINT

setup "${1}"

#
# Bailout in case of uncaught error
#
set +e

[ $(/usr/bin/id -u) != "0" ] && errexit 1

msg "System will be isolated."
progs stop

[ "$(ls -1 ${destpath}/${destpatt} | wc -l)" == "0" ] && {
    do_inital_backup
    progs start
    exit 0
}

[ x"${skipcheck}" == x"noskip" ] && {
    msg "some checks"
    msg "get devicename for ${destvol}"
    destdev=$(grep "${destvol}" /etc/mtab | cut -d \  -f 1)

    msg "unmount ${destvol}"
    umount ${destvol}

    msg "checking filesystem on ${destdev}"
    btrfs check "${destdev}"

    msg "mounting ${destdev} ${destvol}"
    mount ${destdev} ${destvol}

    msg "verify block checksums on ${destvol}"
    btrfs scrub start -B ${destvol}
}

[ "$(ls -1 ${destpath}/${destpatt} | wc -l)" == "1" ] || errexit 10

bckfile="$(ls -1 ${destpath}/${destpatt})"
[ -f "${bckfile}" ] || errexit 11
[ -s "${bckfile}" ] || errexit 12

#
msg "some more checks..."
#
[ -x "${bckscript}" ] || errexit 20
[ -x "${snapscript}" ] || errexit 21

msgok "All preflight checks successful"
#
msg "Createing a snapshot of current backupfile and deleteing the oldest snapshot"
#
${snapscript} ${destpath} ${destvol}/.snapshots/BACKUPS ${mark} ${versions}

#
msg "Rotate the logfiles"
#
logrotate -f /etc/logrotate.conf

#
msg "Finally start the backup"
#
do_backup

#
msgok "All's Well That Ends Well"
#
exit 0
# ===============================================================================================================
# End of WeeklyBackup.sh
# ===============================================================================================================
