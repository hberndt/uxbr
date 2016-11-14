# uxbr
Linux Backup Tool based on duplicity which can make backups to Amazon S3 or via FTP. It can backup files, databases and system configurations.
It provides a small interface for maintaining backups and restoring the database, single files or the whole dataset.

## Installation
``` 
> apt install duplicity lftp python-gi
> curl https://raw.githubusercontent.com/hberndt/uxbr/master/uxbr.sh -o uxbr.sh
> chmod u+x uxbr.sh
```
When you call `./uxbr.sh` you will get a fresh template of uxbr.properties which is a good starting point. Because of included passwords you should run `chmod 400 uxbr.properties`.
