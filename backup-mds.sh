#!/bin/bash

### VARIABLES 

HOSTNAME=$(hostname)
DOMAIN=$(domainname)
RAND_ID=$RANDOM
ARCHIVE_DIR="/var/log/CPbackup/archives"
BACKUP_DIR="/var/log/CPbackup/backups"
LOG_DIR="/var/CPbackup/log"
LOG_FILE="$LOG_DIR/backup_$RAND_ID.txt"
TEMP_DIR="$BACKUP_DIR/$RAND_ID"
FREESPACE=20480000 # at least 20GB free space in backup_dir
DAYS_TO_KEEP=14 # How many days worth of backups should we keep?
START_TIME=$(date +"%F %X")
CHECKSUM="UNKNOWN"

# Define FTP_SERVER only if FTP transfer is desired
#FTP_SERVER="10.11.12.13"
FTP_USER="myuser"
FTP_PASSWD="mypass"
FTP_DIR="/provider1"
FTP_RESULTS="ok"

# Define SCP_SERVER only if SCP transfer is desired
#SCP_SERVER="10.11.12.13"
SCP_USER="myuser"
SCP_IDENT="/home/admin/.ssh/id_rsa" # location of private key
SCP_DIR="~/provider1"

# Define SMPT server for SMTP Reporting
#SMTP_SERVER="10.11.12.13"
SMTP_FROM="$HOSTNAME@$DOMAIN"
SMTP_TO="email@example.com"


### END OF VARIABLES 

### FUNCTIONS

gen_log(){
    echo $1 | tee -a $LOG_FILE
}

get_mimetype(){
  # warning: assumes that the passed file exists
  file -i "$1" | sed 's/.*: //'
}

send_email(){

    if [ -z $SMTP_SERVER ]; then
        return
    fi

    if [ $1 == "FAIL" ]; then
        subject="Backup of $HOSTNAME at $START_TIME. Result = FAIL"
        body="Backup failed. Please see attached log for details"
    else
        subject="Backup of $HOSTNAME at $START_TIME. Result = Success"
        body="Backup succeeded. Backup file MD5 sum = $CHECKSUM"
    fi

    boundary="ZZ_/afg6432dfgkl.94531q"

    declare -a attachments
    attachments=( ${LOG_FILE} )

    # Build headers
    {

    printf '%s\n' "From: $SMTP_FROM"
    printf '%s\n' "To: $SMTP_TO"
    printf '%s\n' "Subject: $subject"
    printf '%s\n' "Mime-Version: 1.0"
    printf '%s\n' "Content-Type: multipart/mixed; boundary=\"$boundary\""
    printf '%s\n' ""
    printf '%s\n' "--${boundary}"
    printf '%s\n' "Content-Type: text/plain; charset=\"US-ASCII\""
    printf '%s\n' "Content-Transfer-Encoding: 7bit"
    printf '%s\n' "Content-Disposition: inline"
    printf '%s\n' ""
    printf '%s\n' "$body"
    printf '%s\n' ""


    # now loop over the attachments, guess the type
    # and produce the corresponding part, encoded base64
    for file in "${attachments[@]}"; do

        if [ ! -f "$file" ]; then
            echo "Warning: attachment $file not found, skipping" >&2
            continue
        fi

        mimetype=$(get_mimetype "$file")
        simplefile=$(basename ${file})

        printf '%s\n' "--${boundary}"
        printf '%s\n' "Content-Type: $mimetype"
        printf '%s\n' "Content-Transfer-Encoding: base64"
        printf '%s\n' "Content-Disposition: attachment; filename=\"$simplefile\""
        printf '%s\n' ""
        base64 "$file"
        printf '%s\n' ""
    done

    # print last boundary with closing --
    printf '%s\n' "--${boundary}--"

    } | /sbin/sendmail -t -oi --host=${SMTP_SERVER} -f ${SMTP_FROM}
}

exit_on_error() {
     local exit_status=${1:-$?}
     gen_log "--- Error: Exiting $0 with $exit_status"
     send_email "FAIL"
     exit $exit_status
}

### END OF FUNCTIONS

# bring in the Check Point environment variables
if [ -r /etc/profile.d/CP.sh ]; then
           source /etc/profile.d/CP.sh
else
        gen_log "Could not source /etc/profile.d/CP.sh"
    send_email "FAIL"
        exit
fi
if [ -r $MDSDIR/scripts/MDSprofile.sh ]; then
           source $MDSDIR/scripts/MDSprofile.sh
else
        gen_log "Could not source $MDSDIR/scripts/MDSprofile.sh"
    send_email "FAIL"
        exit
fi

trap exit_on_error 1 2 3 6 9 14 15 ERR

#
# Check that needed directories exists
#
for CHECK_DIR in $BACKUP_DIR $ARCHIVE_DIR $LOG_DIR; do
    if [ ! -d $CHECK_DIR ]; then
        gen_log "--- Error: directory $CHECK_DIR does not exist! Creating it..."
        mkdir -p $CHECK_DIR
    fi
done

#
# Check enough free space on device
#
ACTUALFREESPACE=$(df -k $BACKUP_DIR | grep -vi filesystem | awk '{ print $4 }')
if [ $ACTUALFREESPACE -lt $FREESPACE ]; then
     gen_log "--- Error: Not enough free space in directory $BACKUP_DIR"
     send_email "FAIL"
     exit 2
fi

gen_log "---//  Check Point automatic MDS BACKUP script  \\---"
gen_log "---// BEGIN logfile of last $0 script run \\---"
gen_log "---// Started at $START_TIME \\---"
gen_log ""


# Move to temporary directory
mkdir $TEMP_DIR
gen_log "$(date +%H:%M) --- Temporary dir $TEMP_DIR created ---"
cd $TEMP_DIR

# Do the backup!
gen_log "$(date +%H:%M) --- MDS service is going offline ---"
$MDSDIR/scripts/mdsstop
gen_log "$(date +%H:%M) --- MDS backup in progress ---"
# stdout to devnull because there's a crapload of it!
$MDSDIR/scripts/mds_backup -b -l >/dev/null 2>> $LOG_FILE
gen_log "$(date +%H:%M) --- MDS backup is done, starting MDS services ---"
$MDSDIR/scripts/mdsstart
gen_log "$(date +%H:%M) --- MDS services started ---"

# identify BACKUP_FILE
gen_log "$(date +%H:%M) --- Searching for backup file... ---"
GEND_BACKUP_FILE=`ls $TEMP_DIR | grep mdsbk`
if [ -z $GEND_BACKUP_FILE ]; then
    gen_log "$(date +%H:%M) --- Unable to identify backup file ---"
    send_email "FAIL"
    exit 2
fi
gen_log "$(date +%H:%M) --- Found $GEND_BACKUP_FILE ---"
BACKUP_FILE="$HOSTNAME-$GEND_BACKUP_FILE"
gen_log "$(date +%H:%M) --- Renaming to $BACKUP_FILE and continuing ---"
mv $GEND_BACKUP_FILE $BACKUP_FILE

# Get our MD5 sum
gen_log "$(date +%H:%M) --- Computing checksum ---"
MD5_SUM=$(md5sum $BACKUP_FILE)
CHECKSUM=$(echo $MD5_SUM | awk '{ print $1; }')

# Record the MD5 sum
BACKUP_MD5_FILE="$BACKUP_FILE.md5sum.txt"
echo "$MD5_SUM" > $BACKUP_MD5_FILE
gen_log "$(date +%H:%M) --- Checksum: $CHECKSUM ---"

# Transfer to network storage
if [ ! -z $FTP_SERVER ]; then  # FTP if server is defined
gen_log "$(date +%H:%M) --- FTPing backup to $FTP_SERVER ---"
FTP_RESULT=$(ftp -n $FTP_SERVER <<EOC
quote user $FTP_USER
quote pass $FTP_PASSWD
debug
binary
cd $FTP_DIR
put $BACKUP_FILE
put $BACKUP_MD5_FILE
bye
EOC
)
gen_log $FTP_RESULT
fi

if [[ $FTP_RESULT == *"failed"* ]] || [[ $FTP_RESULT == *"incorrect"* ]]; then
    gen_log "--- Error: Failure in FTP transfer ---"
    send_email "FAIL"
    exit 2
fi

if [ ! -z $SCP_SERVER ]; then # SCP is server is defined
    gen_log "$(date +%H:%M) --- SCPing backup to $SCP_SERVER ---"
    scp -i $SCP_IDENT $BACKUP_FILE $SCP_USER@$SCP_SERVER:$SCP_DIR/
    scp -i $SCP_IDENT $BACKUP_MD5_FILE $SCP_USER@$SCP_SERVER:$SCP_DIR/
fi

# Change backup file permissions
gen_log "$(date +%H:%M) --- Changing backup file permissions ---"
chmod 640 $BACKUP_FILE $BACKUP_MD5_FILE

# Move backup to local archive and tidy up the temp directory
gen_log "$(date +%H:%M) --- Moving $BACKUP_FILE file into $ARCHIVE_DIR directory for backup ---"
mv $BACKUP_FILE $BACKUP_MD5_FILE $ARCHIVE_DIR
gen_log "$(date +%H:%M) --- Deleting $TEMP_DIR directory and contents ---"
for fl in *; do
    gen_log "    Deleting $fl"
    rm "$fl"
done

cd
rmdir $TEMP_DIR

# Delete old archives
gen_log "$(date +%H:%M) --- Deleting backups older than $DAYS_TO_KEEP days ---"
find $ARCHIVE_DIR -type f -mtime +$DAYS_TO_KEEP -delete

# Complete
gen_log "$(date +%H:%M) Script complete at $(date +'%F %X')"
gen_log "$(date +%H:%M) -- \o/ ALL DONE  \o/ --"

send_email "SUCCESS"
