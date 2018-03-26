#!/bin/bash 

function ver () {
echo -ne "\n Version - 0.0.6 \n" 
 exit 0
};

function hlp () {
echo -ne "\nUse $0 to backup site's files, nginx configs, mysql and/or mongo data, and send it to s3 storage\n\nOPTIONS:\n --skipmongo \t - do not backup MongoDB data\n --skipmysql \t - do not backup MySQL data \n --skipwww \t - do not backup folders (like /var/www or /etc/nginx) \n --nosend \t - do not send data to s3 storage \n -v \t\t - show version\n -h \t\t - show this help            \n\n" 
 exit 0
};


# set default parameters
CLIENT=''

S3CFG="/home/ubuntu/.s3cfg"
S3MCD_BIN="/usr/bin/s3cmd"

TMP_DIR="/backups"
DIR="s3://$CLIENT"

MYSQLDUMP_BIN="/usr/bin/mysqldump"
DBNAME=""
DBUSER=""
DBPW=""
DBHOST="127.0.0.1"
MYSQL_DMP_NAME="mysql_${NOW}.tar.gz"

MONGO_DATABASE=""
MONGO_HOST="127.0.0.1"
MONGO_PORT="27017"
MONGO_USER=""
MONGO_PASS=""
MONGODUMP_BIN="/usr/bin/mongodump"
MONGO_DMP_NAME="mongo_${NOW}.tar.gz"

DIRS_TO_BACKUP="/var/www/ /etc/nginx"
DIRS_DMP_NAME="www_${NOW}.tar.gz"


#KEEP number of backups
daily=7
weekly=5
monthly=12


NOW=$(date +"%Y%m%d")
TIMESTAMP=`date +%F-%H%M` 
day=`date -d $NOW +%d` 
weekday=`date -d $NOW +%w`
month=`date -d $NOW +%m`
ROTATION=( daily weekly monthly yearly)

#read configuration file to reset parameters 
source ./.backup.cfg


#get command line options.Must be here to easaly add option to everride ones from default list of from config file.
OPTSPEC=":hv-:"
while getopts "$OPTSPEC" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                skipmongo)
                    SKIPMONGO=1
                    ;;
                skipmysql) 
                    SKIPMYSQL=1
                    ;;
                skipwww)
                    SKIPDIRS=1
                    ;;
                nosend)
                    NOSEND=1
                    ;;    
            esac
            ;;
        v) ver ;;
        h) hlp ;;
        *) 
           if [ "$OPTERR" != 1 ] || [ "${OPTSPEC:0:1}" = ":" ] && [ $# -ne 0 ]; then
               hlp
           fi 
           ;;    
    esac
done

#if no client or db  given - nothing to do here
if [[ -z $CLIENT  ]] || [[ -z $DBNAME ]]  ; then 
    exit 0 
fi

if [[ ! -z ${S3CFG} ]] ; then 
    S3MCD="$S3MCD_BIN -c $S3CFG"
else 
    S3MCD="$S3MCD_BIN"
fi



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
          EXPIRE="7"
          ;;
         monthly)
          EXPIRE="30"
          ;; 
       esac
      local olderThan=`date -d"-$EXPIRE days" +%s`
        if [[ $createDate -lt $olderThan ]]; then 
          file=`echo $line|awk {'print $4'}`
          echo $file
            if [[ $file != "" ]]; then
#  $S3MCD ls $file
               $S3MCD mv $file ${DIR}/${ROTATION[$rotation]}/
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
          EXPIRE="$(($weekly*7)) days"
          ;;
         monthly)
          EXPIRE="$(($monthly*30)) days"
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


if [[ ! $SKIPMYSQL == 1 ]] ; then
#make mysql dump
for DB in $DBNAME; do 
    $MYSQLDUMP_BIN -u $DBUSER -p$DBPW -h$DBHOST -f  --skip-triggers  --skip-routines --extended-insert $DB > ${DB}.${NOW}.sql 
    $MYSQLDUMP_BIN -u $DBUSER -p$DBPW -h$DBHOST -f  --routines --no-data --no-create-db  --no-create-info  --skip-triggers --skip-opt $DB > ${DB}_SP.${NOW}.sql
    $MYSQLDUMP_BIN -u $DBUSER -p$DBPW -h$DBHOST -f  --triggers --no-data --no-create-db  --no-create-info  --skip-routines --skip-opt $DB > ${DB}_TR.${NOW}.sql

done
tar -zcf $MYSQL_DMP_NAME *.${NOW}.sql
fi


if [[ ! $SKIPMONGO == 1 ]] ; then
#make mongo dump
# mongo admin --eval "printjson(db.fsyncLock())"

#get list of collections
MONGO_COLLS=$(mongo -u panda -p HpLvvDjH0vBdoAmVFrL5 panda540 --quiet --eval "db.getCollectionNames().join('\n')")

for coll in $MONGO_COLLS;
  do 
    $MONGODUMP_BIN -u$MONGO_USER -p$MONGO_PASS -h $MONGO_HOST:$MONGO_PORT -d $MONGO_DATABASE -c $coll --archive=MONGO_${NOW}_${coll}.gz --gzip
  done  
# mongo admin --eval "printjson(db.fsyncUnlock())"

tar -czf ${MONGO_DMP_NAME} MONGO_*.gz
fi 


if [[ ! $SKIPDIRS == 1 ]] ; then
#make www dump
tar -zcf $DIRS_DMP_NAME ${DIRS_TO_BACKUP}

#make nagios config bak
#
#
fi

if [[ ! $NOSEND == 1 ]] ; then
#syncup all data
$S3MCD sync $MYSQL_DMP_NAME $DIR/daily/
$S3MCD sync $MONGO_DMP_NAME $DIR/daily/
$S3MCD sync $DIRS_DMP_NAME   $DIR/daily/



# Perform rotations
if [[ "$weekday" == "0" ]]; then
    rotate weekly
  if [[ "$day" -lt "07" ]]; then
    rotate monthly
  fi
fi
#if [[ "$month/$day" == "01/01" ]]; then
#    rotate yearly
#fi

#prune daily 
#prune weekly 
prune monthly 


#cleare TMP_DIR
cd $TMP_DIR
#check each file and by mask see if there is new backup, then delete old one.
rm -vf *${NOW}*
fi

exit
