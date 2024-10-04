# RaspiBackup.sh


Script to backup a Raspberry Pi SDCARD to an imagefile. 
The resulting file can be installed to a sdcard. 
Refer to https://www.raspberrypi.org/documentation/installation/installing-images/README.md  

**Read this text to the end, before use!**

This script creates system backup to an image file. It creates backups of the device where the system was booted. It does not matter if the system was started from an SD card or a SSD drive. The size of the image will be calculated as the used size of the / partition plus 550m for /boot plus 1000mb reserve.
This is not the size of the entire device, as 30 GB for a SSD drive where only 4 GB of root partition resides.
 
It is really helpful, if you run your system from a large partition residing on a SSD drive.

 :stop_sign: Using an imager all existing data on the target will be removed.
 
:bulb: If your destination contains other partitions you want to keep, do the following:

- restore to a SD card 
- boot from this SD card 
- mount your SSD boot partition and the SSD root partition
- copy `/` to the SSD root partition  omitting `/boot` or `/boot/firmware` (depending on your Raspian version)
   e.g. `rsync -aEvx --del --exclude='/boot/**' / [mountdir of ssd root]`
- copy the content of  `/boot` or `/boot/firmware` to the SSD boot partition e.g. `cp -a /boot/*  [mountdir of ssd boot]` 
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
    or look them up with
   ```blkid```
  
- check/change PARTUUID in `[mountdir of ssd boot]/cmdline.txt` to `${RootPARTUUID}`
- check/change the PARTUUIDS of `/` and  `/boot` or `/boot/firmware` (depending on your Raspian version) in `[mountdir of ssd root]/etc/fstab` to `${RootPARTUUID}` and `${BootPARTUUID}`
- check if all symbolic links in `/`, `/boot`, `/boot/firmware` are present and points to the correct destination
- use `raspi-config` for addopting the boot order
- reboot
- 
     
## Usage

* RaspiBackup.sh _COMMAND_ _OPTION_ sdimage

E.g.:
* RaspiBackup.sh start [-csl] [-L logfile] sdimage
* RaspiBackup.sh mount [-c] sdimage [mountdir]
* RaspiBackup.sh umount sdimage [mountdir]
* RaspiBackup.sh showdf sdimage
* RaspiBackup.sh resize [-s] size sdimage
### Commands:

* *start*  - starts complete backup of RPi's SD Card to 'sdimage'
* *mount*  - mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
* *umount* - unmounts the 'sdimage' from 'mountdir'
* *showdf* - Shows allocation of image
* *resize* - resize the image
### Options:

* -c creates the SD Image if it does not exist
* -l writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
* -L logfile writes rsync log to 'logfile'
* -s define the size of the image file in Mb

### Examples:

Start backup to `backup.img`, creating it if it does not exist. The size of the image corresponds to the used size of the root partition, plus additional 500Mb for /boot and 1000Mb reserve.
```
RaspiBackup.sh start -c /path/to/backup.img
```

Start backup to `backup.img`, creating it if it does not exist, limiting 
 the size to 8000M.
 Keep in mind: you are responsible defineing a size large enough to hold all files to backup! **There's no such thing as a size check**.  
```
RaspiBackup.sh start -s 8000 -c /path/to/backup.img
```

Refresh of `backup.img`.
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

### :zap: Caveat:

This script takes a backup while the source partitions are mounted and in use. The resulting imagefile will be inconsistent!

To reduce inconsistencies, you need to terminate as many services as possible before you start backing up.
You can put the system in rescue mode (be careful: new SSH connections are not possible in rescue mode), take the backup and put your system back in default mode.  
A sample is given as WeeklyBackup.sh. [WeeklyBackup.sh](https://github.com/dolorosus/RaspiBackup/blob/master/WeeklyBackup.sh).

### Recommendation:

Use a filesystem for the target that can handle snapshots (e.g. BTRFS). 
Creating a snapshot, before starting a backup,  results in a space efficient versioning backup.




