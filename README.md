#INSTALLATION NOTES:

##0. copy the script on a server. make sure it's executable
```bash
chmod 750 backup.sh
```

##1. make sure s3cmd installed and configured
```bash
apt install s3cmd
s3cmd --configure
```

##2. open .backup.cfg and set variables:
```bash
CLIENT='CLIENT_NAME'
S3CFG="/home/ubuntu/.s3cfg" #path to s3cmd config file

#MySQL credentials
DBNAME="DATABASE"
DBUSER="USER"
DBPW="PASSWORD"

#Mongo credentilas
MONGO_DATABASE="DATABASE"
MONGO_HOST="127.0.0.1"
MONGO_PORT="27017"
MONGO_USER="USER"
MONGO_PASS="PASSWORD"

# OPTIONAL: number of backups to keep within rotation period

daily=7                     #backups to keep that made everyday
weekly=5                    #backups to keep that being copied from daily (oldest) ones every sunday
monthly=12                  #backups to keep that being copied from weekly (oldest) ones on the beginning of every month 
```

##3.  create TMP_DIR="/backups"
```bash
mkdir /backups
```

##4. add the script to  cron (_/etc/crontab_):
```bash
01 00   * * *    root    /home/ubuntu/s3backup/backup.sh &> /home/ubuntu/s3backup/new_backup.log
```
