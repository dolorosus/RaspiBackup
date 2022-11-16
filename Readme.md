# RaspiBackup.sh
Script to backup a Raspberry Pi SDCARD to an imagefile. 
The resulting file can be installed to a sdcard. 
Refer to https://www.raspberrypi.org/documentation/installation/installing-images/README.md  

**Read this text to the end, before use!**

This script creates system backup to an image file. It creates backups of the device where the system was booted. It does not matter if the system was started from an SD card or a SSD drive. The size of the image will be calculated as the used size of the / partition plus 256m for /boot plus 500mb reserve.
This is not the size of the entire device, as 30 GB for a SSD drive where only 4 GB of root partition resides.
 
It is really helpful, if you run your system from a large partition residing on a SSD drive.

:stop_sign: You may want to use this script for migrating to an external SSD. In this case you may end up with an MBR partitiontable on a 8TB SSD...  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  You may consider to change the line:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  ```declare -r PARTSCHEME="MBR"``` to ```declare -r PARTSCHEME="GPT"```  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  But keep in mind: this is not thoroughly tested, but seems to work well (comments are welcome).

:bulb: if you wish to restore to an ssd which contains additional partitions :  
- restore to a SD card 
- boot from this SD card 
- mount your SSD boot partition and the SSD root partition  
- copy ```/``` to the SSD root partition  omitting ```/boot``` e.g. ```rsync -aEvx --del --exclude='/boot/**' / [mountdir of ssd root]```  
- copy the content of ```/boot``` to the SSD boot partition e.g. ```cp -a /boot/*  [mountdir of ssd boot]```  
- get the PARTUUID of [mountdir of ssd boot] and [mountdir of ssd root]   
    ```
    sudo bash
    BOOTDEV=$(findmnt  -c -n --uniq -o SOURCE [mountdir of ssd boot])
    ROOTDEV=$(findmnt  -c -n --uniq -o SOURCE [mountdir of ssd root])
    BootPARTUUID=$(lsblk -n -o PARTUUID "${BOOTDEV}")
    RootPARTUUID=$(lsblk -n -o PARTUUID "${ROOTDEV}")
    echo "Boot PARTUUID_:${BootPARTUUID}"
    echo "Root PARTUUID_:${RootPARTUUID}"
    ```
- check/change PARTUUID in ```[mountdir of ssd boot]/cmdline.txt``` to ```${RootPARTUUID}```
- check/change the PARTUUIDS of ```/``` and ```/boot``` in ```[mountdir of ssd root]/etc/fstab``` to ```${RootPARTUUID}``` and ```${BootPARTUUID}```

     
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
* -l writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
* -z compresses the SD Image (after backup) to 'sdimage'.gz (deprecated)
*    use pishrink instead.
* -d deletes the SD Image after successful compression
* -f forces overwrite of 'sdimage'.gz if it exists
* -L logfile writes rsync log to 'logfile'
* -s define the size of the image file in M

### Examples:

Start backup to `backup.img`, creating it if it does not exist. The size of the image corresponds to thje used size of the root partition, plus additional 256m for /boot and 500m reserve.
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


Mount the RPi's Image in `/mnt/backup.img`:
```
RaspiBackup.sh mount /path/to/backup.img /mnt/backup.img
```

Unmount the Image from default mountdir (`/mnt/backup.img/`):
```
RaspiBackup.sh umount /path/to/backup.img
```

show allocation of Image:
```
RaspiBackup.sh showdf /path/to/backup.img
```

increase the size of the Image by 1000M:
```
RaspiBackup.sh resize  /path/to/backup.img
```

increase the size of the Image by  a specific amount (here 2000M):
```
RaspiBackup.sh resize -s 2000  /path/to/backup.img
```

Note: Image compression is deprecated, a better alternative is to use filesystems that allow compressed folders (e.g. BTRFS)

### :zap: Caveat:

This script takes a backup while the source partitions are mounted and in use. The resulting imagefile will be inconsistent!

To reduce inconsistencies, you need to terminate as many services as possible before you start backing up.
You can put the system in rescue mode (be careful: new SSH connections are not possible in rescue mode), take the backup and put your system back in default mode).  
A sample is given as WeeklyBackup.sh. [WeeklyBackup.sh](https://github.com/dolorosus/RaspiBackup/blob/master/WeeklyBackup.sh).

### Recommendation:

Use a filesystem for the target that can handle snapshots (e.g. BTRFS). 
Creating a snapshot, before starting a backup,  results in a space efficient versioning backup.




