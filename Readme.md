# RaspiBackup.sh
Script to backup a Raspberry Pi SDCARD to an imagefile
This image can be directly written to a SDCARD

## Author / Origin:

This script is a rewrite of a scipt written by user `jinx`.


## Usage

* RaspiBackup.sh _COMMAND_ _OPTION_ sdimage

E.g.:
* RaspiBackup.sh start [-cslzdf] [-L logfile] sdimage
* RaspiBackup.sh mount [-c] sdimage [mountdir]
* RaspiBackup.sh umount sdimage [mountdir]
* RaspiBackup.sh gzip [-df] sdimage

### Commands:

* *start* - starts complete backup of RPi's SD Card to 'sdimage'
* *mount* - mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
* *umount* - unmounts the 'sdimage' from 'mountdir'
* *gzip* - compresses the 'sdimage' to 'sdimage'.gz

### Options:

* -c creates the SD Image if it does not exist
* -l writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
* -z compresses the SD Image (after backup) to 'sdimage'.gz
* -d deletes the SD Image after successful compression
* -f forces overwrite of 'sdimage'.gz if it exists
* -L logfile writes rsync log to 'logfile'
* -s define the size of the image file

### Examples:

Start backup to `backup.img`, creating it if it does not exist:
```
RaspiBackup.sh start -c /path/to/backup.img
```

Start backup to `backup.img`, creating it if it does not exist, limiting 
 the size to 8000Mb.
 Remember you are responsible defineing the image size large enough to hold all files to backup! There is no size check. 
```
RaspiBackup.sh start -s 8000 -c /path/to/backup.img
```

Refresh (incremental backup) of `backup.img`. You can only refresh a noncompressed image. 
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


### Caveat:

This script takes a backup while the source partitions are mounted and in use. The resulting imagefile will be inconsistent!

To minimize inconsistencies, you should terminate as many services as possible before starting the backup. An example is provided as daily.sh.
