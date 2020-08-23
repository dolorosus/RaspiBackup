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
#  starting the backup. After the backup terminates normally you may restart all stopped
#  applications or just reboot the system. 
#
#
# History removed
# no longer needed, because this script moved to github
#        
#
#
# Defaults
# Size of bootpartiotion in MB
BOOTSIZE=250

# in case COLORS.sh is missing
msgok () {
	echo -e "${TICK} ${1}${NOATT}"
}
msg () {
	echo -e "${IDENT} ${1}${NOATT}"
}
msgwarn () {
	echo -e "${WARN} ${1}${NOATT}"
}
# Echos an error string in red text and exit
error () {
	echo -e "${CROSS} ${1}${NOATT}" >&2
	exit 1
}

[ -f ./COLORS.sh ] && source ./COLORS.sh

# Creates a sparse "${IMAGE}"  and attaches to ${LOOPBACK}
do_create () {

BOOTSIZE=${BOOTSIZE:-250}


	msg "Creating sparse "${IMAGE}", the apparent size of $SDCARD"
	dd if=/dev/zero of="${IMAGE}" bs=${BLOCKSIZE} count=0 seek=${SIZE}

	if [ -s "${IMAGE}" ]; then
		msg "Attaching "${IMAGE}" to ${LOOPBACK}"
		losetup ${LOOPBACK} "${IMAGE}"
	else
		error "${IMAGE} has not been created or has zero size"
	fi

	msg "Creating partitions on ${LOOPBACK}"
	parted -s ${LOOPBACK} mktable msdos
	parted -s ${LOOPBACK} mkpart primary fat32 4MiB ${BOOTSIZE}MiB
	parted -s ${LOOPBACK} mkpart primary ext4 ${BOOTSIZE}MiB 100%
	msg "Formatting partitions"
	partx --add ${LOOPBACK}
	mkfs.vfat -n BOOT -F32 ${LOOPBACK}p1
	mkfs.ext4 ${LOOPBACK}p2

}

change_bootenv () {

	declare -a srcpartuuid
	declare -a dstpartuuid

	local partcnt
	local editmanual
	local part
	local fstab_tmp
	
	editmanual=false
	
	#
	# create a working copy of /etc/fstab
	#
	fstab_tmp=/tmp/fstab
	cp /etc/fstab $fstab_tmp

	#
	# assuming we have two partitions (/boot and /)
	#
	
	for ((p = 1; p <= 2; p++))
	do
		srcpartuuid[${p}]=$(lsblk -n -o PARTUUID "${SDCARD}${SUFFIX}${p}") || {
			msg "Could not find PARTUUID of ${SDCARD}${SUFFIX}${p}"
			editmanual=true
			}

		dstpartuuid[${p}]=$(lsblk -n -o PARTUUID "${LOOPBACK}p${p}") || {
			msg "Could not find PARTUUID of ${LOOPBACK}p${p}"
			editmanual=true
			} 
		#
		# Let' look if our partuuid for src is in fstab, if true then change the PARTUUID to
		#  the PARTUUID of the backup
		#
		grep -q "PARTUUID=${srcpartuuid[${p}]}" $fstab_tmp && {
			msg "Changeing PARTUUID from ${srcpartuuid[${p}]} to ${dstpartuuid[${p}]} in $fstab_tmp"
			sed -i "s/PARTUUID=${srcpartuuid[${p}]}/PARTUUID=${dstpartuuid[${p}]}/" $fstab_tmp||{
				msgwarn "PARTUUID ${dstpartuuid[2]} has not been changed in  $fstab_tmp"
				editmanual=true
			}
				
		}||{
			msgwarn "PARTUUID=${srcpartuuid[${p}]} not found in $fstab_tmp"
			editmanual=true
		}

	done
	#
	# Something went wrong automatically changing wasn't possible
	# Now the Uuser has a second chance 
	if ${editmanual}
	then
		msgwarn "fstab cannot be changed automatically."
		msgwarn "correct fstab on destination manually."
	else
		cp $fstab_tmp ${MOUNTDIR}/etc/fstab
		msgok "PARTUUIDs changed successful in fstab"
	fi 
	
	#
	# Changing /boot/cmdline.txt
	#
	editmanual=false
	cmdline_tmp=/tmp/cmdline.txt
	cp /boot/cmdline.txt $cmdline_tmp || {
		msgwarn "could not copy ${LOOPBACK}p1/cmdline.txt to $cmdline_tmp"
		editmanual=true
		}
	grep -q "PARTUUID=${srcpartuuid[2]}" $cmdline_tmp && {
			msg "Changeing PARTUUID from ${srcpartuuid[2]} to ${dstpartuuid[2]} in $cmdline_tmp"
			sed -i "s/PARTUUID=${srcpartuuid[2]}/PARTUUID=${dstpartuuid[2]}/" $cmdline_tmp||{
				msgwarn "PARTUUID ${dstpartuuid[2]} has not been changed in $cmdline_tmp"
				editmanual=true
			}
		}||{
				msgwarn "PARTUUID ${srcpartuuid[2]} not found in  $cmdline_tmp"
				editmanual=true
		}
	
	if ${editmanual}
	then
		msgwarn "cmdline.txt cannot be changed automatically."
		msgwarn "correct cmdline.txt on destination manually."
	else
		cp $cmdline_tmp ${MOUNTDIR}/boot/cmdline.txt
		msgok "PARTUUID changed successful in cmdline.txt"
	fi 
}

# Mounts the ${IMAGE} to ${LOOPBACK} (if needed) and ${MOUNTDIR}
do_mount () {
	# Check if do_create already attached the SD Image
	[ $(losetup -f) = ${LOOPBACK} ] && {
		msg "Attaching ${IMAGE} to ${LOOPBACK}"
		losetup ${LOOPBACK} "${IMAGE}"
		partx --add ${LOOPBACK}
	}

	msg "Mounting ${LOOPBACK}p1 and ${LOOPBACK}p2 to ${MOUNTDIR}"
	[ -n "${opt_mountdir}" ] || mkdir ${MOUNTDIR}
	mount ${LOOPBACK}p2 ${MOUNTDIR}
	mkdir -p ${MOUNTDIR}/boot
	mount ${LOOPBACK}p1 ${MOUNTDIR}/boot
}

# Rsyncs content of ${SDCARD} to ${IMAGE} if properly mounted
do_backup () {

	local rsyncopt
	
	rsyncopt="-aEvx --del --stats"
	[ -n "${opt_log}" ] && rsyncopt="$rsyncopt --log-file ${LOG}"

	if mountpoint -q ${MOUNTDIR}; then
		msg "Starting rsync backup of / and /boot/ to ${MOUNTDIR}"
		msg "rsync /boot/ ${MOUNTDIR}/boot/"
		rsync ${rsyncopt}  /boot/ ${MOUNTDIR}/boot/
		msg ""
		msg "rsync / to ${MOUNTDIR}"
		rsync ${rsyncopt} --exclude='.gvfs/**' \
			--exclude='tmp/**' \
			--exclude='proc/**' \
			--exclude='run/**' \
			--exclude='sys/**' \
			--exclude='mnt/**' \
			--exclude='lost+found/**' \
			--exclude='var/swap ' \
			--exclude='home/*/.cache/**' \
			--exclude='var/cache/apt/archives/**' \
			 / ${MOUNTDIR}/

	else
		msg "Skipping rsync since ${MOUNTDIR} is not a mount point"
	fi
}

do_showdf () {

	echo -n "${NOATT}"
	df -m ${LOOPBACK}p1 ${LOOPBACK}p2
	echo ""
}

# Unmounts the ${IMAGE} from ${MOUNTDIR} and ${LOOPBACK}
do_umount () {
	msg "Flushing to disk"
	sync; sync

	msg "Unmounting ${LOOPBACK}p1 and ${LOOPBACK}p2 from ${MOUNTDIR}"
	umount ${MOUNTDIR}/boot
	umount ${MOUNTDIR}
	[ -n "${opt_mountdir}" ] || rmdir ${MOUNTDIR}

	msg "Detaching ${IMAGE} from ${LOOPBACK}"
	partx --delete ${LOOPBACK}
	losetup -d ${LOOPBACK}
}

#
# resize image
#
do_resize () {
	local SIZE=${1:-1000}
	
	do_umount >/dev/null 2>&1
	
	msg "increasing size of ${IMAGE} by ${SIZE}M"
	truncate --size=+${SIZE}M "${IMAGE}" || error "Error adding ${SIZE}M to ${IMAGE}"
	
	losetup ${LOOPBACK} "${IMAGE}"
	msg "resize partition 2 of ${IMAGE}"
	parted -s ${LOOPBACK} resizepart 2 100%
	partx --add ${LOOPBACK}
	
	msg "expanding filesystem"
	e2fsck -f ${LOOPBACK}p2
	resize2fs ${LOOPBACK}p2

	msg "Detaching ${IMAGE} from ${LOOPBACK}"
	partx --delete ${LOOPBACK}
	losetup -d ${LOOPBACK}
}

# Compresses ${IMAGE} to ${IMAGE}.gz using a temp file during compression
do_compress () {
	msg "Compressing ${IMAGE} to ${IMAGE}.gz"
	pv -tpreb "${IMAGE}" | gzip > "${IMAGE}.gz.tmp"
	[ -s "${IMAGE}.gz.tmp" ] && { 
		mv -f "${IMAGE}.gz.tmp" "${IMAGE}.gz"
		[ -n "${opt_delete}" ] && rm -f "${IMAGE}"
	}
}

# Tries to cleanup after Ctrl-C interrupt
ctrl_c () {

	msg "Ctrl-C detected."

	if [ -s "${IMAGE}.gz.tmp" ]; then
		rm "${IMAGE}.gz.tmp"
	else
		do_umount
	fi

	[ -n "${opt_log}" ] && msg "See rsync log in ${LOG}"
	
	error "SD Image backup process interrupted"
}

# Prints usage information
usage () {
cat<<EOF    
	${MYNAME}
	
	Usage:
	
		${MYNAME} ${BOLD}start${NOATT} [-clzdf] [-L logfile] [-i sdcard] sdimage
		${MYNAME} ${BOLD}mount${NOATT} [-c] sdimage [mountdir]
		${MYNAME} ${BOLD}umount${NOATT} sdimage [mountdir]
		${MYNAME} ${BOLD}gzip${NOATT} [-df] sdimage
	
		Commands:
	
			${BOLD}start${NOATT}      starts complete backup of RPi's SD Card to 'sdimage'
			${BOLD}mount${NOATT}      mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
			${BOLD}gzip${NOATT}       compresses the 'sdimage' to 'sdimage'.gz (only useful for archiving the image)
			${BOLD}chbootenv${NOATT}  changes PARTUUID entries in fstab and cmdline.txt in the image
			${BOLD}showdf${NOATT}     shows allocation of the image
			${BOLD}resize${NOATT}     expand the image
	
		Options:
	
			${BOLD}-c${NOATT}         creates the SD Image if it does not exist
			${BOLD}-l${NOATT}         writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
			${BOLD}-z${NOATT}         compresses the SD Image (after backup) to 'sdimage'.gz
			${BOLD}-d${NOATT}         deletes the SD Image after successful compression
			${BOLD}-f${NOATT}         forces overwrite of 'sdimage'.gz if it exists
			${BOLD}-L logfile${NOATT} writes rsync log to 'logfile'
			${BOLD}-i sdcard${NOATT}  specifies the SD Card location (default: $SDCARD)
			${BOLD}-s Mb${NOATT}      specifies the size of image in MB (default: Size of $SDCARD)
			${BOLD}-r Mb${NOATT}      the image will be resized by this value 		
	
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

# Make sure we have root rights
if [ $(id -u) -ne 0 ]; then
	error "Please run as root. Try sudo."
fi

#
# Check for dependencies
#
for c in dd losetup parted sfdisk partx mkfs.vfat mkfs.ext4 mountpoint rsync
do
	command -v ${c} >/dev/null 2>&1 || error "Required program ${c} is not installed"
done



# Read the command from command line
case "${1}" in
	
	start|mount|umount|gzip|chbootenv|showdf|resize) opt_command=${1}
	;;
	
	-h|--help)
		usage
		exit 0
	;;

	*)
		error "Invalid command or option: ${1}\nSee '${MYNAME} --help for usage"
	;;
esac
shift 1



# Read the options from command line
while getopts ":czdflL:i:r:s:" opt; do
	case ${opt} in
		c)  opt_create=1;;
		z)  opt_compress=1;;
		d)  opt_delete=1;;
		f)  opt_force=1;;
		l)  opt_log=1;;
		L)  opt_log=1
			LOG=${OPTARG};;
		i)  SDCARD=${OPTARG};;
		r)  RSIZE=${OPTARG};;
		s)  SIZE=${OPTARG}
			BLOCKSIZE=1M ;;
		\?) error "Invalid option: -${OPTARG}\nSee '${MYNAME} --help' for usage";;
		:)  error "Option -${OPTARG} requires an argument\nSee '${MYNAME} --help' for usage";;
	esac
done
shift $((OPTIND-1))
#
# setting defaults if -i or -s is ommitted
#
SDCARD=${SDCARD:-"/dev/mmcblk0"}
SIZE=${SIZE:-$(blockdev --getsz $SDCARD)}
BLOCKSIZE=${BLOCKSIZE:-$(blockdev --getss $SDCARD)}
RSIZE=${RSIZE:-1000}

case "${SDCARD}" in
	"/dev/mmc"*) SUFFIX="p";;
	"/dev/sd"*)  SUFFIX="";;
	"/dev/disk/by-id/"*) SUFFIX="-part";;
	*) SUFFIX="p";;
esac

# Preflight checks
#
# Read the sdimage path from command line
#   and check for existance
#
IMAGE=${1}
[ -z "${IMAGE}" ] && error "No sdimage specified"

# Check if sdimage exists
if [ ${opt_command} = umount ] || [ ${opt_command} = gzip ]; then
	[ -f "${IMAGE}" ] || error "${IMAGE} does not exist"
else
	if [ ! -f "${IMAGE}" ] && [ ! -n "${opt_create}" ]; then
		error "${IMAGE} does not exist\nUse -c to allow creation"
	fi
fi

#
# Checks for compressing the image
#
if [ -n "${opt_compress}" ] || [ ${opt_command} = gzip ]; then
	for c in pv gzip
	do
		command -v ${c} >/dev/null 2>&1 || error "Required program ${c} is not installed"
	done
	
	if [ -s "${IMAGE}".gz ] && [ ! -n "${opt_force}" ]; then
		error "${IMAGE}.gz already exists\nUse -f to force overwriting"
	fi
fi


#
# Identify which loopback device to use
#
LOOPBACK=$(losetup -j "${IMAGE}" | grep -o ^[^:]*)
if [ ${opt_command} = umount ]; then
	[ -z ${LOOPBACK} ] && error "No /dev/loop<X> attached to ${IMAGE}"
elif [ ! -z ${LOOPBACK} ]; then
	error "${IMAGE} already attached to ${LOOPBACK} mounted on $(grep ${LOOPBACK}p2 /etc/mtab | cut -d ' ' -f 2)/"
else
	LOOPBACK=$(losetup -f)
fi

#
# Read the optional mountdir from command line
#
MOUNTDIR=${2}
if [ -z ${MOUNTDIR} ]; then
	MOUNTDIR=/mnt/$(basename "${IMAGE}")/
else
	opt_mountdir=1
	[  -d ${MOUNTDIR} ] || error "Mount point ${MOUNTDIR} does not exist"
fi

# Check if default mount point exists
if [ ${opt_command} = umount ]; then
	[  -d ${MOUNTDIR} ] || error "Default mount point ${MOUNTDIR} does not exist"
else
	if [ ! -n "${opt_mountdir}" ] && [ -d ${MOUNTDIR} ]; then
		error "Default mount point ${MOUNTDIR} already exists"
	fi
fi

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
		if [ -n "${opt_compress}" ]; then
			do_compress
		fi
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

	gzip)
		do_compress
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
		do_resize $RSIZE
	;;

	*)
		error "Unknown command: ${opt_command}"
	;;
esac

exit 0
