# functions to source
# snap srcpath snappath mark keep snapname
#
# e.g.: snap /abc/subvol1 /snapshots test 5 testsnapshot1
# creates a snapshot of /abc/subvol1 in /snapshots as testsnapshot1@test
##        keeping the last 5 snapshots marked with test
#

msg() {
    echo -e "[i] ${1}"
}

snap() {

    [ -z ${DEBUG} ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

    local src="${1:-$SRCPATH}"
    local spath="${2:-$SNAPPATH}"
    local mark="${3:-$MARK}"
    local keep=${4:-KEEP}
    local sname="${5:-$SNAPNAME}"

    local snaps2del
    local s

    snapdel "${src}" "${spath}" "${mark}" ${keep} "${sname}"

    btrfs subvolume snapshot -r "${src}" "${spath}/${sname}@${mark}"

}

snapdel() {

    local src="${1:-$SRCPATH}"
    local spath="${2:-$SNAPPATH}"
    local mark="${3:-$MARK}"
    local keep=${4:-KEEP}
    local sname="${5:-$SNAPNAME}"

    local s

    msg "removing outdated snapshots @${mark} from  ${spath} keeping the last ${keep}"
    snaps2del=$(ls -1d "${spath}"/*${mark} | head --lines=-${keep})
    for s in ${snaps2del}; do
        msg "delete snapshot ${s}"
        btrfs subvol delete "${s}"
    done
}

# snap  snappath snappath2 mark keep snapname
#
# e.g.: snap /snapshots /snapshots2 test 5 mysnap
#   will send /snapshots/mysnap@test to /snapshots2/mysnap@test
#        keeping the last 5 snapshots marked with test
#
snapsend() {

    [ -z ${DEBUG} ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

    local spath="${1:-$SNAPPATH}"
    local spath2="${2:-$SNAPPATH2}"
    local mark="${3:-$MARK}"
    local keep=${4:-$KEEP}
    local sname="${5:-$SNAPNAME}"

    local snaps2del
    local parent
    local s

    snapdel "${src}" "${spath}" "${mark}" ${keep} "${sname}"

    msg "Syncing_:${spath}"
    btrfs filesystem sync "${spath}"

    msg "Syncing_:${spath2}"
    btrfs filesystem sync "${spath2}"

    parent=$(ls -1tr "${spath2}" | tail -1)
    msg "Found ${parent} as parent"
    [ "${parent}" == "" ] || {
        [ -d "${spath}/${parent}" ] && {
            msg "btrfs send -p ${spath}/${parent} ${spath}/${sname}@${mark}|btrfs receive ${spath2}"
            btrfs send -p "${spath}/${parent}" "${spath}/${sname}@${mark}" | btrfs receive "${spath2}"
            return $?
        }
    }
    msg "No common parent found. Complete snapshot is sent."
    msg "btrfs send ${spath}/${sname}@${mark}|btrfs receive ${spath2}"
    btrfs send "${spath}/${sname}@${mark}" | btrfs receive "${spath2}"
    return $?

}

snapremote() {

    [ -z ${DEBUG} ] || msg "${FUNCNAME[*]}  parameter_: ${*}"

    local ruser="${1:-$REMOTEUSER}"
    local spath="${2:-$SNAPPATH}"
    local rpath="${3:-$REMOTESNAPPATH}"
    local mark="${4:-$MARK}"
    local keep="${5:-$KEEP}"
    local sname="${6:-$SNAPNAME}"

    local snaps2del
    local parent
    local s

    msg "sending snapshot ${spath}/${sname}@${mark} to ${ruser} ${rpath}"

    msg "removing outdated snapshots @${mark} from ${rpath} keeping the last ${keep}"
    #cleanup
    snaps2del=$(ssh ${ruser} ls -1d "${rpath}"/*@${mark} | head --lines=-${keep})
    for s in ${snaps2del}; do
        msg "delete snapshot ${s}"
        ssh ${ruser} btrfs subvol delete "${s}"
    done
    msg "Syncing ${rpath}"
    ssh ${ruser} btrfs filesystem sync "${rpath}"

    msg "looking for parent"
    parent=$(ssh ${ruser} ls -1 "${rpath}" | tail -1)
    msg "Parent is_:${parent}"
    [ "${parent}" == "" ] || {
        [ -d "${spath}/${parent}" ] && {
            msg "btrfs send -p ${spath}/${parent} ${spath}/${sname}@${mark}|ssh ${ruser} btrfs receive ${rpath}"
            btrfs send -p "${spath}/${parent}" "${spath}/${sname}@${mark}" | ssh ${ruser} btrfs receive "${rpath}"
            return $?
        }
    }
    msg "No common parent found. Complete snapshot is sent."
    #
    # send without parent
    #
    msg "btrfs send ${spath}/${sname}@${mark}|ssh ${ruser} btrfs receive ${rpath}"
    btrfs send "${spath}/${sname}@${mark}" | ssh ${ruser} btrfs receive "${rpath}"
    return $?

}
