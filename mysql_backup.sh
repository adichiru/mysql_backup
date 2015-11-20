#!/bin/bash

#  Script name: backup_mysql.sh
#  Author: Adi Chiru (adichiru@gmail.com)
#  Versions:
#      v1.0 16.09.2010
#      v1.1 12.10.2010
#      v2.0 13.08.2015


# Description:
# MySQL Databases backup script; this was intended to be:
# - used on SLAVE servers
# - used together with the pre- and post-backup scripts
# - run by a scheduler (cron, Jenkins etc.)

# Features:
# - preliminary checks to make sure it can/should start the backup dump
# - calls the pre-backup script to obtain a list of tables that should be excluded from backup
# - stops the replication thread before dump
# - dumps specified or all databases in a single file or each table/file (depending on the database)
# - calculates SHA1SUM hashes for each .sql file
# - compresses each .sql file with bzip2 or gzip - configurable
# - encrypts the compressed files with GPG (a GPG private key must be accessible)
# - compression and encryption are executed on-the-fly; no clear data is written to disk!

# Notes:
# - databases and tables names MUST NOT contain spaces
# - encryption can NOT be turned off

PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/mysql/bin

DATE_Ymd_HM=$(date +%Y%m%d_%H%M)     # Datestamp e.g. 20070510_1512
DATE_Ymd=$(date +%Y%m%d)             # Datestamp e.g. 20070510
DayOfWeek=$(date +%A)                # Day of the week e.g. Monday

# -------------------------------
# DATABASE CONNECTION PARAMETERS
# -------------------------------

# Username to access the MySQL server e.g. dbuser (mandatory)
DBUSERNAME="backupuser"

# Password to access the MySQL server e.g. password (mandatory)
# de gasit o metoda sa nu mai tin parola in clar in acest fisier
DBPASSWORD="KGH123432kbk(^io^ert889sahy78ebhhsdlkhjwlhhtry45KJGH"

# Sometimes the Unix socket file must be specified (relevant for connections to locahost) (optional)
DBSOCKET="/var/run/mysqld41/mysqld.sock"

# TCP Port on witch MySQL server binds to, if necessary (optional)
DBPORT="3306"

# Host name (or IP address) of MySQL server e.g. localhost (mandatory)
DBHOST="localhost"

# List of databases to be included in the Backup e.g. "DB1 DB2 DB3" (mandatory)
DBNAMES="all"
#DBNAMES="catalog"

# The tables excluded from dump (when dump_by_tables function defined below is used)
# are listed in this file; this file is created automatically by the pre backup script
EXCLUDED_TABLES_LIST_FILENAME="/DBbackup/mysql_srv1/backup_mysql_exclude_tables_$DATE_Ymd.txt"

# ---------------------
# MYSQLDUMP PARAMETERS
# ---------------------

# Include CREATE DATABASE in backup? (yes, no)
CREATE_DATABASE="no"

# OPT string for use with mysqldump (see man mysqldump)
OPT="--quote-names --extended-insert --opt"
#OPT1="--quote-names --extended-insert --opt"

# -----------------------------
# OTHER PARAMETERS / VARIABLES
# -----------------------------

# Backup directory location e.g. /backups (no ending slash required)
BACKUPDIR="/DBbackup/mysql_srv1"

# The minimum free space, in kilobytes, that MUST be available before starting the backup operation
#  1GB =  1048576 kilobytes; to use multipliers change the constant in the let command (no floating point!)
MINIMUM_SPACE="1048576"
# to make the minimum space variable 4GB:
let "MINIMUM_SPACE *= 4"

# Activity report
# During each run, the script gathers detailed information about its operation.
# What would you like to do with this info? (choose one only!)
# - log : will append the info to a log file in the location specified below
# - mail : will send the info over email to destinations specified below
# - screen : will send the info to the screen
OUTPUT_INFO="mail"

# The files containing log information
LOGFILE=$BACKUPDIR/$DATE_Ymd-$HOSTNAME.log
LOGERR=$BACKUPDIR/$DATE_Ymd-$HOSTNAME\_error.log

# Email details
RETURN_PATH="achiru@company.com"
FROM="$HOSTNAME"
REPLY_TO="achiru@company.com"
TO="achiru@company.com"
CC="achiru@company.com"
BCC="achiru@company.com"
SUBJECT="MySQL Backup log for $DATE_Ymd_HM"

# Choose compression type. Possible values: gzip, bzip2 (mandatory)
COMPRESSION="gzip"

# Choose to encrypt or not the compressed files. Possible values: yes, no (mandatory)
# UNUSED for the moment - ENCRYPTION will always be performed!
#ENCRYPTION="yes"

# The ID of the key to use for GPG encryption (mandatory)
ENCRYPTION_KEY_ID="test_key"

# Files to store SHA1SUM hashes (we compute a SHA1SUM hash for each .sql file and for the .gpg file)
SQL_SHA1SUM_FILENAME="$BACKUPDIR/$DATE_Ymd/sql_sha1sum.txt"
GPG_SHA1SUM_FILENAME="$BACKUPDIR/$DATE_Ymd/gpg_sha1sum.txt"

# Hostname of this machine
HOSTNAME=$(hostname)

# Command to run before starting the backup operation
PREBACKUP="/opt/etc/periodic/mysql_backup/backup_mysql_pre.sh"

# Command to run after finishing backup operation
POSTBACKUP="/opt/etc/periodic/mysql_backup/backup_mysql_post.sh"

# ----------
# MAIN BODY
# ----------

# Create required directories
if [ ! -e "$BACKUPDIR/$DATE_Ymd" ]; then
    mkdir -p "$BACKUPDIR/$DATE_Ymd"
fi

# IO redirection for logging.
touch $LOGFILE
exec 6>&1           # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > $LOGFILE     # stdout replaced with file $LOGFILE.
touch $LOGERR
exec 7>&2           # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> $LOGERR     # stderr replaced with file $LOGERR.

function compression () {
if [ "$COMPRESSION" == "gzip" ]; then
    COMP="gzip -f -9"
    echo $COMP
elif [ "$COMPRESSION" == "bzip2" ]; then
    COMP="bzip2 -f -9"
    echo $COMP
fi
}

function encryption () {
if [ "$ENCRYPTION" == "yes" ]; then
    ENC="gpg --quiet --compress-level 0 -r "$ENCRYPTION_KEY" --encrypt"
else
    echo "WARNING - Files will not be encrypted!"
    ENC="no"
    echo $ENC
fi
}

# set connection parameters:
PARAM="--user=${USERNAME} --password=${PASSWORD} --socket=${SOCKET}"

# determine if "CREATE DATABASE" option will be inlcuded in the dumped files:
if [ "$CREATE_DATABASE" == "no" ]; then
    OPT="$OPT --no-create-db"
else
    OPT="$OPT --databases"
fi

# Database dump function - dumps the entire database in a single file
# Accepted parameters: database_name, backup_location, date_time, day_of_week
function dbdump () {
    mysqldump ${PARAM} ${OPT} ${1} | tee >(sha1sum >> ${SQL_SHA1SUM_FILENAME}) | $(compression) | gpg --encrypt --quiet --compress-level 0 -r "$ENCRYPTION_KEY_ID" | tee >(sha1sum >> ${GPG_SHA1SUM_FILENAME}) > ${2}/${1}-${HOSTNAME}_${3}_${4}.sql.gz.gpg
    sed -i "s/ -/ ${1}-${HOSTNAME}_${3}_${4}.sql/" ${SQL_SHA1SUM_FILENAME}
    sed -i "s/ -/ ${1}-${HOSTNAME}_${3}_${4}.sql.gz.gpg/" ${GPG_SHA1SUM_FILENAME}
}

# Database dump function - dumps each table in a separate file
# Accepted parameters: database_name, backup_location, date_time, day_of_week
function dbdump_by_tables () {
    FULL_TABLES_LIST=$(mysql ${PARAM} ${1} --batch --skip-column-names -e "show tables")
    for TABLE in ${FULL_TABLES_LIST}; do
        # If it's Monday, a full backup will be performed (including all tables)
        if [ "${DayOfWeek}" == "Monday" ]; then
            mysqldump ${PARAM} ${OPT} ${1} ${TABLE} | tee >(sha1sum >> ${SQL_SHA1SUM}) | $(compression) | gpg --encrypt --quiet --compress-level 0 -r "$ENCRYPTION_KEY" | tee >(sha1sum >> ${GPG_SHA1SUM}) > ${2}/${1}-${TABLE}-${HOSTNAME}_${3}_${4}.sql.gz.gpg
                sed -i "s/ -/ ${1}-${TABLE}-${HOSTNAME}_${3}_${4}.sql/" ${SQL_SHA1SUM}
                sed -i "s/ -/ ${1}-${TABLE}-${HOSTNAME}_${3}_${4}.sql.gz.gpg/" ${GPG_SHA1SUM}	
        else
            # If it's NOT Monday, tables in EXCL_TABLES_LIST will be ignored
            EXCLUDED=$(grep -c -e "^${TABLE}$" ${EXCLUDED_TABLES_LIST})
                if [ ${EXCLUDED} -eq 0 ]; then
                mysqldump ${PARAM} ${OPT} ${1} ${TABLE} | tee >(sha1sum >> ${SQL_SHA1SUM}) | $(compression) | gpg --encrypt --quiet --compress-level 0 -r "$ENCRYPTION_KEY" | tee >(sha1sum >> ${GPG_SHA1SUM}) > ${2}/${1}-${TABLE}-${HOSTNAME}_${3}_${4}.sql.gz.gpg
                sed -i "s/ -/ ${1}-${TABLE}-${HOSTNAME}_${3}_${4}.sql/" ${SQL_SHA1SUM}
                sed -i "s/ -/ ${1}-${TABLE}-${HOSTNAME}_${3}_${4}.sql.gz.gpg/" ${GPG_SHA1SUM}
                fi
        fi
    done
}

#chown getbackup -R ${BACKUPDIR}/${DATE_Ymd} - bagam in post backup
#chmod 640 -R ${BACKUPDIR}/${DATE_Ymd}/* - bagam in post backup

# View free space on backup partition function
# Accepted parameters: none
function get_free_space () {
    INITIAL=$(df -h | grep "/DBbackup")
    LIBER=$(echo $INITIAL | awk '{print $3}')
    LA_SUTA=$(echo $INITIAL | awk '{print $4}' | sed -e s/\%//)
    LA_SUTA=$(expr 100 - $LA_SUTA)
    echo "${LIBER}B (${LA_SUTA}%)"
}

# Determine if there is enough free space to store the backup files
# Accepted parameters: none
function check_sufficient_space () {
    FREE=$(df | grep "/DBbackup" | awk '{print $3}' | sed 's/[A-Za-z]$//')
    if [ $FREE -ge $MINIMUM_SPACE ]; then
        echo "1"
    else
        echo "0"
    fi
}

# Run command before we begin
if [ "$PREBACKUP" ]; then
    echo "Prebackup command: ${PREBACKUP}"
    echo "Prebackup command output:"
        $PREBACKUP
    if [ "$?" -eq "0" ]; then
        echo "Success - Pre-backup script sucessfuly completed."
    else
        echo "Error - Pre-backup script exited with error!"
        # we do not want to miss a backup execution if pre backup script exists with error
        #exit 1
    fi
fi

echo
echo "-----------------------------------------"
echo "Starting backup operation ($(date))"
echo "-----------------------------------------"

# If backing up all DBs on the server
if [ "$DBNAMES" = "all" ]; then
    DBNAMES=$(mysql ${PARAM} --batch --skip-column-names -e "show databases")
fi

if [ "$(check_sufficient_space)" == "1" ]; then
    # stop replication thread
    mysql ${PARAM} -e "STOP SLAVE SQL_THREAD"
    sleep 5
    for DB in $DBNAMES; do
        echo "- Backup operation started for \"$DB\" database. ($(date))"
        DATE_Ymd_HM=$(date +%Y%m%d_%H%M)
        if [ "$DB" == "epayment" ] || [ "$DB" == "epay_logs" ]; then
            dbdump_by_tables "$DB" "$BACKUPDIR/$DATE_Ymd" "${DATE_Ymd_HM}" "${DayOfWeek}"
        else
            dbdump "$DB" "$BACKUPDIR/$DATE_Ymd" "${DATE_Ymd_HM}" "${DayOfWeek}"
        fi
    done
else
    echo "Error - Not enough space available - Backup operation NOT started!"
    exit 1
fi

# restarting replication thread (relevant only on SLAVE servers)
mysql ${PARAM} -e "START SLAVE SQL_THREAD"
# aici trebuie sa informez watcher-ul ca am pornit slave-ul !?

echo "-----------------------------------------"
echo "Backup operation completed ($(date))"
echo "-----------------------------------------"
echo
echo -n "Free space on backup file system AFTER today backup:"
get_free_space
echo "-----------------------------------------"
echo

# Run post-backup script
if [ "$POSTBACKUP" ]; then
    echo "Post-backup command: ${POSTBACKUP}"
    echo "Post-backup command output:"
    $POSTBACKUP
    if [ "$?" == "0" ]; then
        echo "Success - Post-backup script successfuly completed."
    else
        echo "Error - Post-backup script exited with errors!"
        exit 1
    fi
    echo "-----------------------------------------"
    echo "End of report."
else
    echo "-----------------------------------------"
    echo "End of report."
fi

#Clean up IO redirection
exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
exec 1>&7 7>&-      # Restore stdout and close file descriptor #7.

if [ "$OUTPUT_INFO" = "mail" ]; then
    if [ -s "$LOGERR" ]; then
        BODY_ERR=$(cat "$LOGERR")
    else
        BODY_ERR="No errors detected."
    fi

    # Generating a random file in /tmp to store details that will be sent by email
    RND64=$( ( uuidgen; uuidgen ) | tr "\n-" "xX" | head -c 64 );
    SCRIPT_NAME=$(basename $0);
    RANDOM_FILE="/tmp/${SCRIPT_NAME}_${RND64}";

    # Creating email file
    echo "Return-Path: $RETURN_PATH" > $RANDOM_FILE
    echo "From: $FROM" >> $RANDOM_FILE
    echo "Reply-To: $REPLY_TO" >> $RANDOM_FILE
    echo "To: $TO" >> $RANDOM_FILE
    # add CC and BCC fields; uncomment to use
    # echo "Cc: $CC" >> $RANDOM_FILE
    # echo "Bcc: $BCC" >> $RANDOM_FILE
    echo "Subject: $SUBJECT" >> $RANDOM_FILE
    echo "" >> $RANDOM_FILE
    cat "$LOGFILE" >> $RANDOM_FILE
    echo "" >> $RANDOM_FILE
    cat "$BODY_ERR" >> $RANDOM_FILE

    # using sendmail should be fail-proof no matter what MTA is available
    cat "$RANDOM_FILE" | /usr/sbin/sendmail -bm -oi -t

    # removing log files
    eval rm -f "$LOGFILE"
    eval rm -f "$LOGERR"
elif [ "$OUTPUT_INFO" = "screen" ]; then
    if [ -s "$LOGERR" ]; then
        cat "$LOGFILE"
        echo
        echo "###### WARNING ######"
        echo "Errors reported during Automatic MySQL Databases Backup execution !!!"
        echo "Error log below:"
        cat "$LOGERR"
    else
        cat "$LOGFILE"
    fi
    if [ -s "$LOGERR" ]; then
        STATUS=0
    else
        STATUS=1
    fi
    # removing log files
    eval rm -f "$LOGFILE"
    eval rm -f "$LOGERR"
fi

# if there is any info in the $LOGERR variable exit status will be 1
exit $STATUS

# end of script

