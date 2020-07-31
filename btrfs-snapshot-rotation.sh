#!/bin/bash


# Parse arguments:
SOURCE=$1
TARGET=$2
SNAP=$3
COUNT=${4:-8}
QUIET=$5

[ -f ./COLORS.sh ] && source ./COLORS.sh

usage() {
    scriptname=$(/usr/bin/basename -- "$0")
cat <<EOF
$scriptname: Take and rotate snapshots on a btrfs file system
  Usage:
  $scriptname source target snap_name [count] [-q]
 
  source: path to make snaphost of
  target: snapshot directory
  snap_name: Base name for snapshots, to be appended to 
             date "+%F--%H-%M-%S"
  count:     Number of snapshots in the timestamp-@snap_name format to
             keep at one time for a given snap_name. 
  [-q]:      Be quiet.
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

	$1 >/dev/null
	if [ $? -eq 0 ] && [ -z "$QUIET"] ; then
		echo ${TICK} "$1"
	else
		echo ${CROSS} "$1"
	fi
}

# Basic argument checks:
if [ -z "$COUNT" ] ; then
	echo ${CROSS} "COUNT is not provided."
	usage
fi

if [ ! -z "$6" ] ; then
	echo ${CROSS} "Too many options."
	usage
fi

if [ -n "$QUIET" ] && [ "x$QUIET" != "x-q"  ] ; then
	echo ${CROSS} "Option 4 is either -q or empty. Given: \"$QUIET\""
	usage
fi

# $max_snap is the highest number of snapshots that will be kept for $SNAP.
max_snap=$((COUNT -1))

# Clean up older snapshots:
for i in $(find "$TARGET"|sort |grep @"${SNAP}"\$|head -n -${max_snap}); do
	doit "btrfs subvolume delete $i"
done
doit "btrfs subvolume sync $TARGET"

# Create new snapshot:
doit "btrfs subvolume snapshot -r $SOURCE $TARGET/$(date "+%F--%H-%M-%S-@${SNAP}")"
doit "btrfs subvolume sync $TARGET "

