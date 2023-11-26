#!/bin/bash
#
#	*EXAMPLE* Script for daily backup
#
#	Before the backup takes place a snapshot of the current backupfile is taken.
#	This is done by calling a script $snapscript.
#	Using a snapshot supporting filesystem (btrfs,xfs...) is recommended
#	for the backupdestination. Refer to snapfunc.sh
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

setup() {

    [ ${DEBUG} ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

    export skipcheck=${1:-"noskip"}
    export stamp=$(date +%y%m%d_%H%M%S)
    export destvol="/x6/"
    export destpath="${destvol}/BACKUPS/system"
    export snappath="${destvol}/BACKUPS/.snapshots/system"

    export bckprefix="MyRaspi4"
    export destpatt="${bckprefix}-2*_[0-9]*.img"
    export bcknewname="${bckprefix}-${stamp}.img"
    export tmppre="#"

    export bckscript="/home/pi/scripts/RaspiBackup.sh"
    export mark="manual"
    export versions=7

}

msg() {
    echo "${IDENT} ${1}${NOATT}"
}
msgok() {
    echo "${TICK} ${1}${NOATT}"
}

errexit() {

    case "${1}" in
    1)
        echo "${CROSS} "I'm sorry user, I'm afraid I can't do that. You have to be root to run this script${NOATT}"
        ;;

    10)
        echo "${CROSS} More than one backupfile according to ${destpath}/${destpatt} found."
        echo "Can't decide which one to use.${NOATT}"
        ;;

    11)
        echo "${CROSS} backupfile according to ${destpath}/${destpatt} is no flatfile.${NOATT}"
        ;;

    12)
        echo "${CROSS} backupfile according to ${destpath}/${destpatt} is empty.${NOATT}"
        ;;

    20)
        echo "${CROSS} No executable file $bckscript found.${NOATT}"
        ;;

    21)
        echo "${CROSS} Snapshot functions $snapscript not found.${NOATT}"
        ;;

    25)
        echo "${TICK} ${YELLOW}${action} $prog failed${NOATT}"
        ;;

    30)
        echo "${CROSS} something went wrong..."
        echo "the incomplete backupfile is named: ${destpath}/${tmppre}${bcknewname}"
        echo "Resolve the issue, rename the the backupfile and restart"
        echo "Good luck!${NOATT}"

        ;;

    *)
        echo "${CROSS} An unknown error occured${NOATT}"
        set -- 99
        ;;
    esac

    systemctl default
    exit ${1}
}

progs() {

    [ ${DEBUG} ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

    local action=${1:=start}
    local grace=20
    local setopt=$-

    [ "${action}" == "stop" ] && {
        msg "System is put to rescue mode."
        systemctl rescue
    }
    [ "${action}" == "start" ] && {
        msg "System is put to default mode."
        systemctl default
    }
    msg "waiting for ${grace}s"
    #progress "waiting for ${grace}s"
    for ((i = 0; i <= ${grace}; i++)); do
        echo -n '.'
    done
    echo ''
    for ((i = 0; i <= ${grace}; i++)); do
        echo -n '.'
        sleep 1s
    done
    echo ''
    msgok "done."

    return 0
}

do_backup() {

    [ ${DEBUG} ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

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

exec &> >(tee "${0%%.sh}.out")

MYNAME=${0##*/}
ORGNAME=$(readlink -f "${0}")
SCRIPTDIR=${ORGNAME%%${ORGNAME##*/}}

snapfunc="${SCRIPTDIR}snapFunc.sh"
[ -f "${snapfunc}" ] || errexit 21
source "${snapfunc}"

colors="${SCRIPTDIR}COLORS.sh"
[ -f ${colors} ] && source ${colors}

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
    msg "No backupfile found."
    msg "creating a new one"
    do_backup "-c"
    progs start
    exit 0
}

[ "${skipcheck}" = "noskip" ] && {
    msg "some checks"
    msg "get devicename for ${destvol}"
    destdev=$(findmnt -o SOURCE --uniq --noheadings "${destvol}")

    msg "checking mounted filesystem on ${destdev} "
    btrfs check --readonly --force --check-data-csum  --progress "${destdev}"
}

[ "$(ls -1 ${destpath}/${destpatt} | wc -l)" == "1" ] || errexit 10

bckfile="$(ls -1 ${destpath}/${destpatt})"
[ -f "${bckfile}" ] || errexit 11
[ -s "${bckfile}" ] || errexit 12

#
msg "some more checks..."
#
[ -x "${bckscript}" ] || errexit 20

msgok "All preflight checks successful"
#
#
msg "Rotate the logfiles"
#
logrotate -f /etc/logrotate.conf

#
msg "Finally start the backup"
#
do_backup

msg "Creating a snapshot of current backupfile and deleting the oldest snapshot"
#
snap "${destpath}" "${snappath}" "${mark}" ${versions} "${stamp}"

msgok "All's Well That Ends Well"
#
exit 0
# ===============================================================================================================
# End of WeeklyBackup.sh
# ===============================================================================================================
