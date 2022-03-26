# RaspiBackup.sh
Script to backup a Raspberry Pi SDCARD to a file. 
The resulting file can be installed to a sdcard. 
Refer to https://www.raspberrypi.org/documentation/installation/installing-images/README.md  


## Author / Origin:

This script is inpired by user `jinx`.


## Usage

* RaspiBackup.sh _COMMAND_ _OPTION_ sdimage

E.g.:
* RaspiBackup.sh start [-cslzdf] [-L logfile] sdimage
* RaspiBackup.sh mount [-c] sdimage [mountdir]
* RaspiBackup.sh umount sdimage [mountdir]
* RaspiBackup.sh gzip [-df] sdimage (deprecated)
* RaspiBackup.sh showdf sdimage
* RaspiBackup.sh resize [-s] size sdimage
### Commands:

* *start* - starts complete backup of RPi's SD Card to 'sdimage'
* *mount* - mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
* *umount* - unmounts the 'sdimage' from 'mountdir'
* *gzip* - compresses the 'sdimage' to 'sdimage'.gz (deprecated)
* *showdf* - Shows allocation of image
* *resize* - resize the image
### Options:

* -c creates the SD Image if it does not exist
* -i defines a different source device path instead of the default /dev/mmcblk0
* -l writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
* -z compresses the SD Image (after backup) to 'sdimage'.gz (deprecated)
*    use pishrink instead.
* -d deletes the SD Image after successful compression
* -f forces overwrite of 'sdimage'.gz if it exists
* -L logfile writes rsync log to 'logfile'
* -s define the size of the image file in M

### Examples:

Start backup to `backup.img`, creating it if it does not exist. The size of the image corresponds to size of the source partition.
```
RaspiBackup.sh start -c /path/to/backup.img
```

Start backup to `backup.img`, creating it if it does not exist, limiting 
 the size to 8000M.
 Keep in mind: you are responsible defineing a size large enough to hold all files to backup! There's no such thing as a size check.  
```
RaspiBackup.sh start -s 8000 -c /path/to/backup.img
```

Refresh of `backup.img`. (only noncompressed images can be refreshed) 
```
RaspiBackup.sh start /path/to/backup.img
```


Mount the RPi's SD Image in `/mnt/backup.img`:
```
RaspiBackup.sh mount /path/to/backup.img /mnt/backup.img
```

Unmount the SD Image from default mountdir (`/mnt/backup.img/`):
```
RaspiBackup.sh umount /path/to/backup.img
```

show allocation of SD Image:
```
RaspiBackup.sh showdf /path/to/backup.img
```

increase the size of the SD Image by 1000M:
```
RaspiBackup.sh resize  /path/to/backup.img
```

increase the size of the SD Image by  a specific amount (here 2000M):
```
RaspiBackup.sh resize -s 2000  /path/to/backup.img
```

Note: Image compression is deprecated, a better alternative is to use filesystems that allow compressed folders (e.g. BTRFS)

### Caveat:

This script takes a backup while the source partitions are mounted and in use. The resulting imagefile will be inconsistent!

To minimize inconsistencies, you should terminate as many services as possible before starting the backup. An example is provided as weekly.sh.

### Recommendation:

Use a file system for the target that can handle snapshots (e.g. BTRFS). 
Creating a snapshot, before starting a backup,  results in a space efficient versioning backup.



