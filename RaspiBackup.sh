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
# no longer needed, because this script was moved to github
#        
#
#
# Defaults
SDCARD=/dev/mmcblk0
#
# Size of bootpartiotion in MB
BOOTSIZE=250

setup () {
	#
	# Define some fancy colors only if connected to a terminal.
	# Thus output to file is no more cluttered
	#
		[ -t 1 ] && {
			RED=$(tput setaf 1)
			GREEN=$(tput setaf 2)
			YELLOW=$(tput setaf 3)
			BLUE=$(tput setaf 4)
			MAGENTA=$(tput setaf 5)
			CYAN=$(tput setaf 6)
			WHITE=$(tput setaf 7)
			RESET=$(tput setaf 9)
			BOLD=$(tput bold)
			NOATT=$(tput sgr0)
		}||{
			RED=""
			GREEN=""
			YELLOW=""
			BLUE=""
			MAGENTA=""
			CYAN=""
			WHITE=""
			RESET=""
			BOLD=""
			NOATT=""
		}
		MYNAME=$(basename $0)
}

# Echo success messages in green
success () {
	echo -e "${GREEN}${1}${NOATT}\n"
}

# Echos traces with yellow text to distinguish from other output
trace () {
	echo -e "${YELLOW}${1}${NOATT}"
}

# Echos an error string in red text and exit
error () {
	echo -e "${RED}${1}${NOATT}" >&2
	exit 1
}

# Creates a sparse "${IMAGE}"  and attaches to ${LOOPBACK}
do_create () {

BOOTSIZE=${BOOTSIZE:-250}


	trace "Creating sparse "${IMAGE}", the apparent size of $SDCARD"
	dd if=/dev/zero of="${IMAGE}" bs=${BLOCKSIZE} count=0 seek=${SIZE}

	if [ -s "${IMAGE}" ]; then
		trace "Attaching "${IMAGE}" to ${LOOPBACK}"
		losetup ${LOOPBACK} "${IMAGE}"
	else
		error "${IMAGE} was not created or has zero size"
	fi

	trace "Creating partitions on ${LOOPBACK}"
	parted -s ${LOOPBACK} mktable msdos
	parted -s ${LOOPBACK} mkpart primary fat32 4MiB ${BOOTSIZE}MiB
	parted -s ${LOOPBACK} mkpart primary ext4 ${BOOTSIZE}MiB 100%
	trace "Formatting partitions"
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
			trace "Could not find PARTUUID of ${SDCARD}${SUFFIX}${p}"
			editmanual=true
		}
		#echo "srcpartuuid[${p}] ${srcpartuuid[${p}]}"
		dstpartuuid[${p}]=$(lsblk -n -o PARTUUID "${LOOPBACK}p${p}") || {
			trace "Colud not find PARTUUID of ${LOOPBACK}p${p}"
			editmanual=true
			} 
		#echo "dstpartuuid[${p}] ${dstpartuuid[${p}]}"
		
		grep -q "PARTUUID=${srcpartuuid[${p}]}" $fstab_tmp && {
			trace "Changeing PARTUUID from ${srcpartuuid[${p}]} to ${dstpartuuid[${p}]} in $fstab_tmp"
			sed -i "s/PARTUUID=${srcpartuuid[${p}]}/PARTUUID=${dstpartuuid[${p}]}/" $fstab_tmp||{
				trace "PARTUUID ${dstpartuuid[2]} has not been changed in  $fstab_tmp"
				editmanual=true
			}
				
		}||{
			trace "PARTUUID=${srcpartuuid[${p}]} not found in $fstab_tmp"
			editmanual=true
		}

	done
	
	if ${editmanual}
	then
		trace "fstab cannot be changed automatically."
		trace "correct fstab on destination manually."
	else
		cp $fstab_tmp ${MOUNTDIR}/etc/fstab
		success "Changeing PARTUUIDs in fstab succsessful"
	fi 
	
	#
	# Changeing /boot/cmdline.txt
	#
	editmanual=false
	cmdline_tmp=/tmp/cmdline.txt
	cp /boot/cmdline.txt $cmdline_tmp || {
		trace "could not copy ${LOOPBACK}p1/cmdline.txt to $cmdline_tmp"
		editmanual=true
		}
	grep -q "PARTUUID=${srcpartuuid[2]}" $cmdline_tmp && {
			trace "Changeing PARTUUID from ${srcpartuuid[2]} to ${dstpartuuid[2]} in $cmdline_tmp"
			sed -i "s/PARTUUID=${srcpartuuid[2]}/PARTUUID=${dstpartuuid[2]}/" $cmdline_tmp||{
				trace "PARTUUID ${dstpartuuid[2]} as not been changed in $cmdline_tmp"
				editmanual=true
			}
		}||{
				trace "PARTUUID ${srcpartuuid[2]} not found in  $cmdline_tmp"
				editmanual=true
		}
	
	if ${editmanual}
	then
		trace "cmdline.txt cannot be changed automatically."
		trace "correct cmdline.txt on destination manually."
	else
		cp $cmdline_tmp ${MOUNTDIR}/boot/cmdline.txt
		success "Changeing PARTUUID in cmdline.txt succsessful"
	fi 
}

do_cloneid () {
	# Check if do_create already attached the SD Image
	if [ $(losetup -f) = ${LOOPBACK} ]; then
		trace "Attaching ${IMAGE} to ${LOOPBACK}"
		losetup ${LOOPBACK} "${IMAGE}"
		partx --add ${LOOPBACK}
	fi
	clone
	partx --delete ${LOOPBACK}
	losetup -d ${LOOPBACK}
}

clone () {
	# cloning UUID and PARTUUID
	UUID=$(blkid -s UUID -o value ${SDCARD}p2)
	PTUUID=$(blkid -s PTUUID -o value ${SDCARD})
	e2fsck -f -y ${LOOPBACK}p2
	echo y|tune2fs ${LOOPBACK}p2 -U $UUID
	printf 'p\nx\ni\n%s\nr\np\nw\n' 0x${PTUUID}|fdisk "${LOOPBACK}"
	sync
	
}

# Mounts the ${IMAGE} to ${LOOPBACK} (if needed) and ${MOUNTDIR}
do_mount () {
	# Check if do_create already attached the SD Image
	if [ $(losetup -f) = ${LOOPBACK} ]; then
		trace "Attaching ${IMAGE} to ${LOOPBACK}"
		losetup ${LOOPBACK} "${IMAGE}"
		partx --add ${LOOPBACK}
	fi

	trace "Mounting ${LOOPBACK}p1 and ${LOOPBACK}p2 to ${MOUNTDIR}"
	if [ ! -n "${opt_mountdir}" ]; then
		mkdir ${MOUNTDIR}
	fi
	mount ${LOOPBACK}p2 ${MOUNTDIR}
	mkdir -p ${MOUNTDIR}/boot
	mount ${LOOPBACK}p1 ${MOUNTDIR}/boot
}

# Rsyncs content of ${SDCARD} to ${IMAGE} if properly mounted
do_backup () {

	local rsyncopt
	
	rsyncopt="-aEvx --del --stats"

	if mountpoint -q ${MOUNTDIR}; then
		trace "Starting rsync backup of / and /boot/ to ${MOUNTDIR}"

		if [ -n "${opt_log}" ]; then
			rsyncopt="$rsyncopt --log-file ${LOG}"
		fi

		trace "rsync /boot/ ${MOUNTDIR}/boot/"
		rsync ${rsyncopt}  /boot/ ${MOUNTDIR}/boot/
		trace ""
		trace "rsync / to ${MOUNTDIR}"
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
			--delete-excluded \
			 / ${MOUNTDIR}/

	else
		trace "Skipping rsync since ${MOUNTDIR} is not a mount point"
	fi
}

do_showdf () {

	echo -n "${NOATT}"
	df -m ${LOOPBACK}p1 ${LOOPBACK}p2
	echo ""
}

# Unmounts the ${IMAGE} from ${MOUNTDIR} and ${LOOPBACK}
do_umount () {
	trace "Flushing to disk"
	sync; sync

	trace "Unmounting ${LOOPBACK}p1 and ${LOOPBACK}p2 from ${MOUNTDIR}"
	umount ${MOUNTDIR}/boot
	umount ${MOUNTDIR}
	if [ ! -n "${opt_mountdir}" ]; then
		rmdir ${MOUNTDIR}
	fi

	trace "Detaching ${IMAGE} from ${LOOPBACK}"
	partx --delete ${LOOPBACK}
	losetup -d ${LOOPBACK}
}




#
# resize image
#
do_resize () {
	do_umount >/dev/null 2>&1
	truncate --size=+1G "${IMAGE}"
	losetup ${LOOPBACK} "${IMAGE}"
	parted -s ${LOOPBACK} resizepart 2 100%
	partx --add ${LOOPBACK}
	e2fsck -f ${LOOPBACK}p2
	resize2fs ${LOOPBACK}p2
	do_umount
}

# Compresses ${IMAGE} to ${IMAGE}.gz using a temp file during compression
do_compress () {
	trace "Compressing ${IMAGE} to ${IMAGE}.gz"
	pv -tpreb "${IMAGE}" | gzip > "${IMAGE}.gz.tmp"
	if [ -s "${IMAGE}.gz.tmp" ]; then
		mv -f "${IMAGE}.gz.tmp" "${IMAGE}.gz"
		if [ -n "${opt_delete}" ]; then
			rm -f "${IMAGE}"
		fi
	fi
}

# Tries to cleanup after Ctrl-C interrupt
ctrl_c () {
	trace "Ctrl-C detected."

	if [ -s "${IMAGE}.gz.tmp" ]; then
		rm "${IMAGE}.gz.tmp"
	else
		do_umount
	fi

	if [ -n "${opt_log}" ]; then
		trace "See rsync log in ${LOG}"
	fi

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
	        ${BOLD}umount${NOATT}     unmounts the 'sdimage' from 'mountdir'
	        ${BOLD}gzip${NOATT}       compresses the 'sdimage' to 'sdimage'.gz
	        ${BOLD}cloneid${NOATT}    clones the UUID/PTUUID from the current disk to the image
	        ${BOLD}chbootenv${NOATT}  changes PARTUUID entries in fstab and cmdline.txt in the image
	        ${BOLD}showdf${NOATT}     shows allocation of the image
	        ${BOLD}resize${NOATT}     add 1G to the image
	
	    Options:
	
	        ${BOLD}-c${NOATT}         creates the SD Image if it does not exist
	        ${BOLD}-l${NOATT}         writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
	        ${BOLD}-z${NOATT}         compresses the SD Image (after backup) to 'sdimage'.gz
	        ${BOLD}-d${NOATT}         deletes the SD Image after successful compression
	        ${BOLD}-f${NOATT}         forces overwrite of 'sdimage'.gz if it exists
	        ${BOLD}-L logfile${NOATT} writes rsync log to 'logfile'
	        ${BOLD}-i sdcard${NOATT}  specifies the SD Card location (default: $SDCARD)
	        ${BOLD}-s Mb${NOATT}      specifies the size of image in MB (default: Size of $SDCARD)
	
	Examples:
	
	    ${MYNAME} start -c /path/to/rpi_backup.img
	        starts backup to 'rpi_backup.img', creating it if it does not exist
	
	    ${MYNAME} start -c -s 8000 /path/to/rpi_backup.img
	        starts backup to 'rpi_backup.img', creating it 
	        with a size of 8000mb if it does not exist
	
	    ${MYNAME} start /path/to/\$(uname -n).img
	        uses the RPi's hostname as the SD Image filename
	
	    ${MYNAME} start -cz /path/to/\$(uname -n)-\$(date +%Y-%m-%d).img
	        uses the RPi's hostname and today's date as the SD Image filename,
	        creating it if it does not exist, and compressing it after backup
	
	    ${MYNAME} mount /path/to/\$(uname -n).img /mnt/rpi_image
	        mounts the RPi's SD Image in /mnt/rpi_image
	
	    ${MYNAME} umount /path/to/raspi-$(date +%Y-%m-%d).img
	        unmounts the SD Image from default mountdir (/mnt/raspi-$(date +%Y-%m-%d).img/)
EOF
}

setup

# Read the command from command line
case "${1}" in
	
	start|mount|umount|gzip|cloneid|chbootenv|showdf) opt_command=${1}
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

# Make sure we have root rights
if [ $(id -u) -ne 0 ]; then
	error "Please run as root. Try sudo."
fi

# Read the options from command line
while getopts ":czdflL:i:s:" opt; do
	case ${opt} in
		c)  opt_create=1;;
		z)  opt_compress=1;;
		d)  opt_delete=1;;
		f)  opt_force=1;;
		l)  opt_log=1;;
		L)  opt_log=1
			LOG=${OPTARG};;
		i)  SDCARD=${OPTARG};;
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
case "${SDCARD}" in
	"/dev/mmc"*) SUFFIX="p";;
	"/dev/sd"*)  SUFFIX="";;
	"/dev/disk/by-id/"*) SUFFIX="-part";;
	*) SUFFIX="p";;
esac

# Read the sdimage path from command line
IMAGE=${1}
if [ -z "${IMAGE}" ]; then
	error "No sdimage specified"
fi

# Check if sdimage exists
if [ ${opt_command} = umount ] || [ ${opt_command} = gzip ]; then
	if [ ! -f "${IMAGE}" ]; then
		error "${IMAGE} does not exist"
	fi
else
	if [ ! -f "${IMAGE}" ] && [ ! -n "${opt_create}" ]; then
		error "${IMAGE} does not exist\nUse -c to allow creation"
	fi
fi

# Check if we should compress and sdimage.gz exists
if [ -n "${opt_compress}" ] || [ ${opt_command} = gzip ]; then
	if [ -s "${IMAGE}".gz ] && [ ! -n "${opt_force}" ]; then
		error "${IMAGE}.gz already exists\nUse -f to force overwriting"
	fi
fi

# Define default rsync logfile if not defined
if [ -z ${LOG} ]; then
	LOG="${IMAGE}-$(date +%Y%m%d%H%M%S).log"
fi

# Identify which loopback device to use
LOOPBACK=$(losetup -j "${IMAGE}" | grep -o ^[^:]*)
if [ ${opt_command} = umount ]; then
	if [ -z ${LOOPBACK} ]; then
		error "No /dev/loop<X> attached to ${IMAGE}"
	fi
elif [ ! -z ${LOOPBACK} ]; then
	error "${IMAGE} already attached to ${LOOPBACK} mounted on $(grep ${LOOPBACK}p2 /etc/mtab | cut -d ' ' -f 2)/"
else
	LOOPBACK=$(losetup -f)
fi


# Read the optional mountdir from command line
MOUNTDIR=${2}
if [ -z ${MOUNTDIR} ]; then
	MOUNTDIR=/mnt/$(basename "${IMAGE}")/
else
	opt_mountdir=1
	if [ ! -d ${MOUNTDIR} ]; then
		error "Mount point ${MOUNTDIR} does not exist"
	fi
fi

# Check if default mount point exists
if [ ${opt_command} = umount ]; then
	if [ ! -d ${MOUNTDIR} ]; then
		error "Default mount point ${MOUNTDIR} does not exist"
	fi
else
	if [ ! -n "${opt_mountdir}" ] && [ -d ${MOUNTDIR} ]; then
		error "Default mount point ${MOUNTDIR} already exists"
	fi
fi

# Trap keyboard interrupt (ctrl-c)
trap ctrl_c SIGINT SIGTERM

# Check for dependencies
for c in dd losetup parted sfdisk partx mkfs.vfat mkfs.ext4 mountpoint rsync; do
	command -v ${c} >/dev/null 2>&1 || error "Required program ${c} is not installed"
done
if [ -n "${opt_compress}" ] || [ ${opt_command} = gzip ]; then
	for c in pv gzip; do
		command -v ${c} >/dev/null 2>&1 || error "Required program ${c} is not installed"
	done
fi

# Do the requested functionality
case ${opt_command} in
	start)
			trace "Starting SD Image backup process"
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
			success "SD Image backup process completed."
			if [ -n "${opt_log}" ]; then
				trace "See rsync log in ${LOG}"
			fi
			;;
	mount)
			if [ ! -f "${IMAGE}" ] && [ -n "${opt_create}" ]; then
				do_create
			fi
			do_mount
			success "SD Image has been mounted and can be accessed at:\n    ${MOUNTDIR}"
			;;
	umount)
			do_umount
			;;
	gzip)
			do_compress
			;;
	cloneid)
			cat<<EOF
	${YELLOW}
	While cloneid still works, you may consider to adapt /boot/cmdline.txt and /etc/fstab.
	${MYNAME} will assist you by using the ${BOLD}chbootenv${NOATT}${YELLOW} option.

EOF
			while true
			do
				read -p "Do you really wish to use cloneid? (y/n)" yn
				case $yn in
					[Yy]* ) do_cloneid; break;;
					[Nn]* ) exit;;
					* ) echo "Please answer yes or no.";;
				esac
			done
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
			do_resize;;
	*)
			error "Unknown command: ${opt_command}"
			;;
esac

exit 0
