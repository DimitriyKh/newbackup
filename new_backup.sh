#!/bin/bash 

CLIENT='...'

S3CFG="/home/ubuntu/.s3cfg"
S3MCD_BIN="/usr/bin/s3cmd"
if [[ ! -z ${S3CFG} ]] ; then 
    S3MCD="$S3MCD_BIN -c $S3CFG"
else 
    S3MCD="$S3MCD_BIN"
fi

TMP_DIR="/backups"
DIR="s3://crm-backups/$CLIENT"
NOW=$(date +"%Y%m%d")
TIMESTAMP=`date +%F-%H%M` 
day=`date -d $NOW +%d` 
weekday=`date -d $NOW +%w`
month=`date -d $NOW +%m`

MYSQLDUMP_BIN="/usr/bin/mysqldump"
DBNAME="..."
DBUSER="..."
DBPW="..."
DMPNAME="$CLIENT-dump-tables-$NOW.sql"
DMPNAME_TR="$CLIENT-dump-triggers-$NOW.sql"
DMPNAME_SP="$CLIENT-dump-SP-$NOW.sql"
MYSQL_DMP_NAME="mysql_${NOW}.tar.gz"

MONGO_DATABASE="..."
MONGO_HOST="127.0.0.1"
MONGO_PORT="27017"
MONGODUMP_BIN="/usr/bin/mongodump"
MONGO_DMP_NAME="mongo_${NOW}.gz"

DIRS_TO_BACKUP="/var/www /etc/nginx"
WWW_DMP_NAME="www_${NOW}.tar.gz"


ROTATION=( daily weekly monthly yearly)
#KEEP number of backups
daily=7
weekly=5
monthly=12

function rotate {
    # get the postion for current run from array named "ROTATION"
    local rotation=$(search ROTATION $1)

    $S3MCD ls ${DIR}/${ROTATION[$(($rotation-1))]}/ | while read -r line ;
    do
      local createDate=`echo $line|awk {'print $1,$2'}`
      local createDate=`date -d"${createDate}" +%s`
        # need to calculdate expire date...
       case $1 in
#       daily)
#         EXPIRE="$daily days"
#         ;;
        weekly)
          EXPIRE="7 days"
          ;;
         monthly)
          EXPIRE="30 days"
          ;; 
       esac
      local olderThan=`date -d"-$EXPIRE" +%s`
        if [[ $createDate -lt $olderThan ]]; then 
          file=`echo $line|awk {'print $4'}`
          echo $file
            if [[ $file != "" ]]; then
#  $S3MCD ls $file
               $S3MCD mv $file ${!DIR}/${ROTATION[$rotation]}/
            fi
        fi
    done
}

function prune {  
    # get the postion for current run from array named "ROTATION"
    local rotation=$(search ROTATION $1)

    $S3MCD ls ${DIR}/${ROTATION[$(($rotation-1))]}/ | while read -r line ;
    do
      local createDate=`echo $line|awk {'print $1,$2'}`
      local createDate=`date -d"${createDate}" +%s`
        # need to calculdate expire date...
       case $1 in
#       daily)
#         EXPIRE="$daily days"
#         ;;
        weekly)
          EXPIRE="7 days"
          ;;
         monthly)
          EXPIRE="30 days"
          ;;
       esac
      local olderThan=`date -d"-$EXPIRE" +%s`
        if [[ $createDate -lt $olderThan ]]; then
          file=`echo $line|awk {'print $4'}`
          echo $file
            if [[ $file != "" ]]; then
#  $S3MCD ls $file
      $S3MCD del -r $file
            fi
        fi
    done
}


function abort {
    echo "aborting..."
    exit 1
}

function search { 
#returns position of element $2 in array $1
    local array="$1[@]";
    local i=0;
    for str in ${!array};
    do
        if [ "$str" = "$2" ]; then
            echo $i;
    return;
        else
            ((i++));
        fi;
    done;
    echo "-1"
}

#start backup from here
mkdir -p $TMP_DIR
cd $TMP_DIR
#make mysql dump
$MYSQLDUMP_BIN -u $DBUSER -p$DBPW  -f  --skip-triggers  --skip-routines --extended-insert $DBNAME > $DMPNAME
$MYSQLDUMP_BIN -u $DBUSER -p$DBPW  -f  --routines --no-data --no-create-db  --no-create-info  --skip-triggers --skip-opt $DBNAME > $DMPNAME_SP
$MYSQLDUMP_BIN -u $DBUSER -p$DBPW  -f  --triggers --no-data --no-create-db  --no-create-info  --skip-routines --skip-opt $DBNAME > $DMPNAME_TR


tar -zcf $MYSQL_DMP_NAME $DMPNAME $DMPNAME_SP $DMPNAME_TR

#make mongo dump
# mongo admin --eval "printjson(db.fsyncLock())"
# $MONGODUMP_BIN -h $MONGO_HOST:$MONGO_PORT -d $MONGO_DATABASE
$MONGODUMP_BIN -d $MONGO_DATABASE --archive=$MONGO_DMP_NAME --gzip
# mongo admin --eval "printjson(db.fsyncUnlock())"



#make www dump
tar -zcf $WWW_DMP_NAME ${DIRS_TO_BACKUP}

#make nagios config bak
#
#

#syncup all data
$S3MCD sync $MYSQL_DMP_NAME $DIR/daily/
$S3MCD sync $MONGO_DMP_NAME $DIR/daily/
$S3MCD sync $WWW_DMP_NAME   $DIR/daily/



# Perform rotations
if [[ "$weekday" == "0" ]]; then
    rotate weekly
fi
if [[ "$day" == "01" ]]; then
    rotate monthly
fi
#if [[ "$month/$day" == "01/01" ]]; then
#    rotate yearly
#fi

#prune daily 
prune weekly 
prune monthly 

#cleare TMP_DIR
cd $TMP_DIR
#check each file and by mask see if there is new backup, then delete old one.
rm -f *${NOW}*.gz
rm -f *${NOW}*.sql

exit
