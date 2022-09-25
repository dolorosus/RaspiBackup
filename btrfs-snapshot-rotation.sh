#!/bin/bash
#
#
SCRIPTNAME=${0##*/}
ORGNAME=$(readlink -f "${0}")

# Parse arguments:
SOURCE=$1
TARGET=$2
MARK=${3:-manual}
COUNT=${4:-8}
QUIET=${5}

SNAP=$(date "+%F--%H-%M-%S")

colors=${ORGNAME%%${ORGNAME##*/}}COLORS.sh
[ -f ${colors} ] && . ${colors}

usage() {
    
cat <<EOF
${SCRIPTNAME}: Take and rotate snapshots on a btrfs file system
  Usage:
  ${SCRIPTNAME} source target snap_name [count] [-q]
 
  SOURCE: path to make snaphost of
  TARGET: snapshot directory
  [MARK]: Marker appended to keep, defaults to  manual
  [-q]:   Be quiet.
Example for crontab:
15,30,45  * * * *   root    /usr/local/bin/btrfs-snapshot / /.btrfs quarterly 4 -q
0         * * * *   root    /usr/local/bin/btrfs-snapshot / /.btrfs hourly 8 -q
Example for anacrontab:
1             10      daily_snap      /usr/local/bin/btrfs-snapshot / /.btrfs daily 8
7             30      weekly_snap     /usr/local/bin/btrfs-snapshot / /.btrfs weekly 5
@monthly      90      monthly_snap    /usr/local/bin/btrfs-snapshot / /.btrfs monthly 3
EOF
    exit
}

doit() {

    ${1} >/dev/null
    if [ ${?} -eq 0 ] && [ -z "${QUIET}"]; then
        echo ${TICK} "$1"
    else
        echo ${CROSS} "$1"
    fi
}

# Basic argument checks:

[ ${@} -lt 2 ] && { usage }

[ ! -z "$6" ] && {
    echo ${CROSS} "Too many options."
    usage
}

[ -n "${QUIET}" ] && [ "${QUIET}" != "-q" ] && {
    echo ${CROSS} "Option 5 is either -q or empty. Given: \"${QUIET}\""
    usage
}

# $max_snap is the highest number of snapshots that will be kept for $MARK.
max_snap=$((COUNT - 1))

# Clean up older snapshots:
for i in $(find "${TARGET}" | sort | grep @"${MARK}"\$ | head -n -${max_snap}); do
    doit "btrfs subvolume delete ${i}"
done

# Create new snapshot:
doit "btrfs subvolume snapshot -r ${SOURCE} ${TARGET}/${SNAP}@${MARK}"
doit "btrfs subvolume sync ${TARGET} "
