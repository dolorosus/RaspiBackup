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

setup() {

    IDENT="   "
    TICK="[✓]"
    CROSS="[✗]"
    INFO="[i]"
    WARN="[w]"
    msg() {
        echo "${IDENT} ${1}"
    }
    msgok() {
        echo "${TICK} ${1}"
    }

}


errexit() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}  parameter_: ${*}"

    case "${1}" in
    1)
        echo "${CROSS} You have to be root to run this script${NOATT}">&2
        ;;
    5)
        echo "${CROSS} snapfunc.sh (${snapfunc}) not found${NOATT}">&2
        ;;
    7)
        echo "${CROSS} BTRFS at least one error counter for ${destvol} is greater 0${NOATT}">&2
        ;;
    10)
        echo "${CROSS} More than one backupfile according to ${destpath}/${destpatt} found.">&2
        echo "Can't decide which one to use.${NOATT}">&2
        ;;

    11)
        echo "${CROSS} backupfile according to ${destpath}/${destpatt} is no flatfile.${NOATT}">&2
        ;;

    12)
        echo "${CROSS} backupfile according to ${destpath}/${destpatt} is empty.${NOATT}">&2
        ;;

    20)
        echo "${CROSS} No executable file $bckscript found.${NOATT}">&2
        ;;

    21)
        echo "${CROSS} Snapshot functions $snapscript not found.${NOATT}">&2
        ;;

    25)
        echo "${TICK} ${YELLOW}${action} $prog failed${NOATT}">&2
        ;;

    30)
        echo "${CROSS} something went wrong...">&2
        echo "the incomplete backupfile is named: ${destpath}/${tmppre}${bcknewname}">&2
        echo "Resolve the issue, rename the the backupfile and restart">&2
        echo "Good luck!${NOATT}">&2

        ;;

    *)
        echo "${CROSS} An unknown error occured${NOATT}">&2
        echo "   Write down what you did, open an Issue and append all logfiles${NOATT}">&2
        set -- 99
        ;;
    esac

    systemctl default
    exit ${1}
}

progs() {
    [ "${DEBUG}" ] && msg "${FUNCNAME[*]}  parameter_: ${*}"

    local action=${1:=start}
    #local grace=20
    local line=""

    [ "${action}" == "stop" ] && {
        msg "System is put to rescue mode."
        systemctl rescue
    }
    [ "${action}" == "start" ] && {
        msg "System is put to default mode."
        systemctl default
    }
    msg "waiting for 20s"
    #progress "waiting for ${grace}s"

    for i in {1..20}; do
        line="*${line}"
        echo -en "[${line:1:20}]\r"
        sleep 1s
    done

    echo ''
    msgok "done."

    return 0
}

do_backup() {
    [ ${DEBUG} ] && msg "${FUNCNAME[*]}  parameter_: ${*}"

    local creopt="${1}"

    # move the destination to a temporary filename while
    # the backup is working
    [ -z "${creopt}" ] && {
        msg "Moving ${bckfile} to ${destpath}/${tmppre}${bcknewname}"
        mv "${bckfile}" "${destpath}/${tmppre}${bcknewname}"
    }

    sync

    msg "Starting backup_: ${bckscript} start ${creopt} ${destpath}/${tmppre}${bcknewname}"
    backup="ko"
    ${bckscript} start ${creopt} "${destpath}/${tmppre}${bcknewname}" && {
        backup="ok"
        msg "Moving  ${destpath}/${tmppre}${bcknewname} to ${destpath}/${bcknewname}"
        mv "${destpath}/${tmppre}${bcknewname}" "${destpath}/${bcknewname}"
        msgok "Backup successful"
        msg "Backupfile is_: ${destpath}/${bcknewname}"
    }

    [ "${SKIPISO}" == "noskip" ] && progs start

    [ "${backup}" == "ok" ] && return 0
    errexit 30

}

# ===============================================================================================================
# Main
# ===============================================================================================================

declare -gx SKIPCHECK="noskip"
declare -gx SKIPISO="noskip"

opt=$(getopt --long skipcheck skipiso -- "$@")
eval set -- "$opt"
while shift; do
    case "${1}" in
    --skipcheck) SKIPCHECK="skip" ;;
    --skipiso) SKIPISO="skip" ;;
    esac
done

declare -r SKIPCHECK
declare -r SKIPISO

hostname

[ ${EUID} -eq 0 ] || errexit 1

declare -xr stamp=$(date +%y%m%d_%H%M%S)
declare -xr destvol="/x6/"
declare -xr destpath="${destvol}/BACKUPS/system"
declare -xr snappath="${destvol}/BACKUPS/.snapshots/system"
declare -xr rempath="/media/usbSyncth/.snapshots/Raspi4Images"

declare -xr bckprefix="MyRaspi4"
declare -xr destpatt="${bckprefix}-2*_[0-9]*.img"
declare -xr bcknewname="${bckprefix}-${stamp}.img"
declare -xr tmppre="#"

declare -xr bckscript="/home/pi/scripts/RaspiBackup.sh"
declare -xr versions=7

declare -xr remusr="root@192.168.26.3"

declare -xr MYNAME=${0##*/}
declare -xr ORGNAME=$(realpath "${0}")
declare -xr scriptbase="${ORGNAME%%${ORGNAME##*/}}"
declare -xr colors="${scriptbase}/COLORS.sh"
declare -xr snapfunc="${scriptbase}/snapFunc.sh"

declare -xr BTRFS="/usr/local/bin/btrfs"

[ -f "${snapfunc}" ] || errexit 5
source "${snapfunc}"

[ -f "${colors}" ] && {
    source "${colors}"
    msgheader "${MYNAME}"
}

mark=$(echo ${0} | sed 's/\(.*cron.\)\(.*\)\(\/.*\)/\2/')
case "${mark}" in
"daily") keep=7 ;;
"weekly") keep=3 ;;
"monthly") keep=3 ;;
*)
    mark="manual"
    keep=7
    ;;
esac

readonly mark
readonly keep

setup

#
# Please, do not disturb
#
trap "progs start" SIGTERM SIGINT
#
# Bailout in case of uncaught error
#

set +e

msg "using ${BTRFS} $(${BTRFS} --version)"

$BTRFS device stat --check ${destvol} || {
    msg "PreCheck for errors btrfs device stat found error(s)"
    msg "use  btrfs device stat --reset ${destvol} to reset counter."
    errexit 7
}
[ "${SKIPISO}" == "noskip" ] && {
    msg "System will be isolated."
    progs stop
}

[ "$(ls -1 ${destpath}/${destpatt} | wc -l)" == "0" ] && {
    msg "No backupfile found."
    msg "creating a new one"
    do_backup "-c"
    progs start
    exit 0
}

[ "${SKIPCHECK}" == "noskip" ] && {
    msg "some checks"
    msg "get devicename for ${destvol}"
    destdev=$(findmnt -o SOURCE --uniq --noheadings "${destvol}")

    msg "checking mounted filesystem readonly on ${destdev} "
    $BTRFS check --readonly --force --progress "${destdev}"
    msg "scrub filesystem on ${destdev} "
    $BTRFS scrub start -B "${destpath}"
}

$BTRFS device stat --check ${destvol} || {
    msg "PostCheck btrfs device stat found error(s)"
    msg "use  btrfs device stat --reset ${destvol} to reset counter."
    errexit 7
}

[ "$(ls -1 ${destpath}/${destpatt} | wc -l)" == "1" ] || errexit 10

bckfile="$(ls -1 ${destpath}/${destpatt})"
[ -f "${bckfile}" ] || errexit 11
[ -s "${bckfile}" ] || errexit 12

#
msg "some more checks..."
[ -x "${bckscript}" ] || errexit 20

msgok "All preflight checks successful"

msg "Rotate the logfiles"
logrotate -f /etc/logrotate.conf

msg "Finally start the backup"
do_backup

msg "Creating a snapshot of current backupfile and deleting the oldest snapshot"
snap "${destpath}" "${snappath}" "${mark}" ${keep} "${stamp}"

msg "sending the snapshot to ${remusr}"
snapremote "${remusr}" "${snappath}" "${rempath}" "${mark}" ${keep} "${stamp}"

msgok "All's Well That Ends Well"
exit 0
# ===============================================================================================================
# End of WeeklyBackup.sh
# ===============================================================================================================
