#! /usr/bin/env bash
#
# Copyright (c) 2015 BiDcore / Holger Berndt
# 
#
#########################################################################################
# uxbr: *UX BACKUP AND RECOVERY TOOL 
# Version 1.0       
#########################################################################################
# ACTION REQUIRED:
# CONFIGURE uxbr in the uxbr.properties file and APP_PATH
# in this file.
# Copy all files into root homedir.
# RUN ./uxbr.sh [backup|recovery|verify|collection|list] 
#########################################################################################
#
# Run backup daily at 5AM
# 0 5 * * * root /root/uxbr.sh backup 
#
#########################################################################################

# Load properties
UXBR_PATH=.

if [ -f ${UXBR_PATH}/uxbr.properties ]; then
	. ${UXBR_PATH}/uxbr.properties 
else
	echo uxbr.properties file not found, edit $0 and modify UXBR_PATH
	echo A template has been downloaded to $UXBR_PATH
	curl https://raw.githubusercontent.com/hberndt/uxbr/master/uxbr.properties -o $UXBR_PATH/uxbr.properties
	exit 1
fi

# Do not let this script run more than once
PROC=`ps axu | grep -v "grep" | grep --count "duplicity"`
if [ $PROC -gt 0 ]; then 
	echo "uxbr.sh or duplicity is already running."
	exit 1
fi

# Command usage menu
usage(){
echo "USAGE:
    `basename $0` <mode> [set] [date <dest>]

Modes:
    backup [set]		runs an incremental backup or a full if first time
    restore [set] [date] [dest]	runs the restore, wizard if no arguments
    verify [set]		verifies the backup
    collection [set]		shows all the backup sets in the archive
    list [set]			lists the files currently backed up in the archive

Sets:
    all		do all backup sets
    db		use data base backup set (group) for selected mode
    cs		use content store backup set (group) for selected mode
    files	use rest of files backup set (group) for selected mode
    system  	use rest of system backup set (group) for selected mode"
}

# Checks if encryption is required if not it adds appropiate flag
if [ $ENCRYPTION_ENABLED = "true" ]; then
	export PASSPHRASE
else
	NOENCFLAG="--no-encryption"
fi

# Checks backup type, target selected
case $BACKUPTYPE in
	"s3" ) 
	        export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
                export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
		DEST=${S3FILESYSLOCATION}
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${S3OPTIONS} ${NOENCFLAG}"
		;;
	"ftp" ) 
		if [ ${FTPS_ENABLE} == 'false' ]; then
   			DEST=ftp://${FTP_USER}:${FTP_PASSWORD}@${FTP_SERVER}:${FTP_PORT}/${FTP_FOLDER}
   			PARAMS="${GLOBAL_DUPLICITY_PARMS} ${NOENCFLAG}"
		else
   			DEST=ftps://${FTP_USER}:${FTP_PASSWORD}@${FTP_SERVER}:${FTP_PORT}/${FTP_FOLDER}
   			PARAMS="${GLOBAL_DUPLICITY_PARMS} ${NOENCFLAG}"
		fi
		;;	
	"scp" )
		DEST=scp://${SCP_USER}@${SCP_SERVER}/${SCP_FOLDER}
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${NOENCFLAG}"
		;;
	"local" )
		# command sintax is "file:///" but last / is coming from ${LOCAL_BACKUP_FOLDER} variable
		DEST=file://${LOCAL_BACKUP_FOLDER}
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${NOENCFLAG}"
		;;
	* ) echo "$LOG_DATE_LOG - [ERROR] Unknown BACKUP type <$BACKUPTYPE>, review your uxbr.properties" >> $UXBR_LOG_FILE;; 
esac
	
# Checks if logs directory exist 
if [ ! -d $UXBR_LOG_DIR ]; then
	echo Script logs directory not found, add a valid directory in 'UXBR_LOG_DIR'. Bye.
	exit 1
fi


function dbBackup {
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up db to $BACKUPTYPE" >> $UXBR_LOG_FILE
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup - $DBTYPE db" >> $UXBR_LOG_FILE
	
	if [ ! -d $UXBR_LOG_DIR ]; then
		echo Script logs directory not found, add a valid directory in 'UXBR_LOG_DIR'. Bye.
		exit 1
	fi
	
	if [ ! -d $LOCAL_BACKUP_DB_DIR ]; then
		mkdir $LOCAL_BACKUP_DB_DIR
	fi
	
	case $DBTYPE in 
		"mysql" ) 
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up the DB to $BACKUPTYPE" >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup - $DBTYPE DB" >> $UXBR_LOG_FILE
			# Mysql dump
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $MYSQL_BINDIR/$MYSQLDUMP_BIN --single-transaction  -u $DBUSER -h $DBHOST -p$DBPASS $DBNAME | $GZIP -9 > $LOCAL_BACKUP_DB_DIR/$DBNAME.dump" >> $UXBR_LOG_FILE
			$MYSQL_BINDIR/$MYSQLDUMP_BIN --single-transaction -u $DBUSER -h $DBHOST -p$DBPASS $DBNAME | $GZIP -9 > $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/$DBTYPE" >> $UXBR_LOG_FILE
  			$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/$DBTYPE >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG cleaning DB backup" >> $UXBR_LOG_FILE
  			rm -fr $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG DB backup finished" >> $UXBR_LOG_FILE
			
		;; 
		"postgresql" ) 		
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up the DB to $BACKUPTYPE" >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup - $DBTYPE DB" >> $UXBR_LOG_FILE
			# PG dump in plain text format and compressed 
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $PGSQL_BINDIR/$PGSQLDUMP_BIN --host=$DBHOST --username=$DBUSER --format=p --compress=9 --file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump $DBNAME -w" >> $UXBR_LOG_FILE
			export PGPASSFILE=$PGPASSFILE
			export PGPASSWORD=$DBPASS
			if [ -z "$DBNAME" ]; then
				$DBNAME=`hostname`
				$PGSQL_BINDIR/$PGSQLDUMPALL_BIN --host=$DBHOST --username=$DBUSER --file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump -w
			else
				$PGSQL_BINDIR/$PGSQLDUMP_BIN --host=$DBHOST --username=$DBUSER --format=p --compress=9 --file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump $DBNAME -w
			fi
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/$DBTYPE" >> $UXBR_LOG_FILE
  			$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/$DBTYPE >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG cleaning DB backup" >> $UXBR_LOG_FILE
  			rm -fr $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG DB backup finished" >> $UXBR_LOG_FILE
		;; 
		
		"oracle" ) 
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up the DB to $BACKUPTYPE" >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup - $DBTYPE DB" >> $UXBR_LOG_FILE
			# Oracle export 
			# TODO: Change full options
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $ORACLE_BINDIR/$ORASQLDUMP_BIN $DBUSER/$DBPASS@$DBHOST/$DBNAME full=y file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump log=$UXBR_LOG_FILE" >> $UXBR_LOG_FILE
			$ORACLE_BINDIR/$ORASQLDUMP_BIN $DBUSER/$DBPASS@$DBHOST/$DBNAME full=y file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump log=$UXBR_LOG_FILE
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/$DBTYPE" >> $UXBR_LOG_FILE
  			$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/$DBTYPE >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG cleaning DB backup" >> $UXBR_LOG_FILE
  			rm -fr $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG DB backup finished" >> $UXBR_LOG_FILE
		;;
		
		* ) 
		echo "$LOG_DATE_LOG - [ERROR] Unknown DB type \"$DBTYPE\", review your uxbr.properties. Backup ABORTED!" >> $UXBR_LOG_FILE
		echo "$LOG_DATE_LOG - [ERROR] Unknown DB type \"$DBTYPE\", review your uxbr.properties. Backup ABORTED!"	
		exit 1
		;; 
	esac 
}

function contentStoreBackup {
	
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up the ContentStore to $BACKUPTYPE" >> $UXBR_LOG_FILE
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup - ContentStore" >> $UXBR_LOG_FILE
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $DEST/cs" >> $UXBR_LOG_FILE
 
 	# Content Store backup itself 
  	$DUPLICITYBIN $PARAMS $CONTENTSTORE $DEST/cs >> $UXBR_LOG_FILE
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG ContentStore backup done!" >> $UXBR_LOG_FILE
}

function filesBackup {
    # Getting a variable to know all includes and excludes
	FILES_DIR_INCLUDES="$FILESDIR"
	
	if [ -d "$LOCAL_BACKUP_DB_DIR" ]; then
		OPT_LOCAL_BACKUP_DB_DIR=" --exclude $LOCAL_BACKUP_DB_DIR"
	fi
	
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up the files to $BACKUPTYPE" >> $UXBR_LOG_FILE
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup - files" >> $UXBR_LOG_FILE
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $FILES_DIR_INCLUDES $OPT_LOCAL_BACKUP_DB_DIR $DEST/files" >> $UXBR_LOG_FILE
 
 	# files backup itself 
  	$DUPLICITYBIN $PARAMS $FILES_DIR_INCLUDES  \
  	$OPT_LOCAL_BACKUP_DB_DIR $DEST/files >> $UXBR_LOG_FILE
  	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Files backup done!" >> $UXBR_LOG_FILE
}

function systemBackup () {
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Saving package configuration" >> $UXBR_LOG_FILE
	dpkg --get-selections > $LOCAL_BACKUP_SYS_DIR/Package.list
	cp -R /etc/apt/sources.list* $LOCAL_BACKUP_SYS_DIR/
	apt-key exportall > $LOCAL_BACKUP_SYS_DIR/Repo.keys
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Tar configuration directory" >> $UXBR_LOG_FILE
	tar czf /$LOCAL_BACKUP_SYS_DIR/etc_config.tar.gz /etc >> $UXBR_LOG_FILE
	if [ -n ${SYSTEM_MYSQL_DB_PWD} ]; then
		mysqldump -u root --password=${SYSTEM_MYSQL_DB_PWD} --all-databases > $LOCAL_BACKUP_SYS_DIR/sysdb.sql 
	fi
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Backing up system configuration files" >> $UXBR_LOG_FILE
	$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_SYS_DIR $DEST/system >> $UXBR_LOG_FILE
}

function restoreSystem () {
	echo " =========== Starting restore SYSTEM from $DEST/system to $RESTOREDIR/system ==========="
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/system $RESTOREDIR/system" >> $UXBR_LOG_FILE
	$DUPLICITYBIN restore --restore-time $RESTORE_TIME $DEST/system $RESTOREDIR/system
	echo " Restoring package configuration"
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Restoring package configuration" >> $UXBR_LOG_FILE
	apt-key add $RESTOREDIR/Repo.keys
	cp -R $RESTOREDIR/sources.list* /etc/apt/
	apt-get update
	apt-get install dselect
	dpkg --set-selections < $RESTOREDIR/Package.list
	apt-get dselect-upgrade -y
	if [ -n ${SYSTEM_MYSQL_DB_PWD} ]; then
		echo " Restoring system databases"
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Restoring system databases" >> $UXBR_LOG_FILE
		mysql -u root --password=${SYSTEM_MYSQL_DB_PWD} < $RESTOREDIR/sysdb.sql
	fi 
	echo " Restoring system configuration"
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Restoring system configuration" >> $UXBR_LOG_FILE
	cd /
	tar xvzf $RESTOREDIR/etc_config.tar.gz >> $UXBR_LOG_FILE
	echo ""
	echo "SYSTEM Recovery... DONE!"
	echo "System must be rebooted!"
}

function restoreOptions (){
	if [ "$WIZARD" = "1" ]; then
		RESTORE_TIME=$RESTOREDATE
		RESTOREDIR=$RESTOREDIR
	else
		RESTORE_TIME=$3
			if [ -z $4 ]; then
				usage
				exit 0
			else
				RESTOREDIR=$4
			fi
	fi
}

function restoreDb (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
		echo " =========== Starting restore DB from $DEST/$DBTYPE to $RESTOREDIR/$DBTYPE==========="
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/$DBTYPE $RESTOREDIR/$DBTYPE" >> $UXBR_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME $DEST/$DBTYPE $RESTOREDIR/$DBTYPE
		if [ ${DBTYPE} == 'mysql' ]; then
			mv $RESTOREDIR/$DBTYPE/$DBNAME.dump $RESTOREDIR/$DBTYPE/$DBNAME.dump.gz
			echo ""
			echo "DB from $DEST/$DBTYPE... DONE!"
			echo ""
			echo "To restore this MySQL database use next command (the existing db must be empty)"
			echo "gunzip < $RESTOREDIR/$DBTYPE/$DBNAME.dump.gz | $MYSQL_BINDIR/mysql -u $DBUSER -p$DBPASS $DBNAME"
		fi
		if [ ${DBTYPE} == 'postgresql' ]; then
			mv $RESTOREDIR/$DBTYPE/$DBNAME.dump $RESTOREDIR/$DBTYPE/$DBNAME.dump.gz
			echo ""
			echo "DB from $DEST/$DBTYPE... DONE!"
			echo ""
			echo "To restore this PostgreSQL database use next command (the existing db must be empty)"
			echo "$PGSQL_BINDIR/psql --host=$DBHOST -U $DBUSER -d $DBNAME -f $DBNAME.dump.gz"
		fi
	else
		echo "No backup DB configured to backup. Nothing to restore."
	fi
}
	
function restoreContentStore (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
		echo " =========== Starting restore CONTENT STORE from $DEST/cs to $RESTOREDIR/cs ==========="
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/cs $RESTOREDIR/cs" >> $UXBR_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME $DEST/cs $RESTOREDIR/cs
		echo ""
		echo "CONTENT STORE from $DEST/cs... DONE!"
		echo ""
	else
		echo "No backup CONTENTSTORE configured to backup. Nothing to restore."
	fi
}
	
function restoreFiles (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
		echo " =========== Starting restore FILES from $DEST/files to $RESTOREDIR/files ==========="
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/files $RESTOREDIR/files" >> $UXBR_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME $DEST/files $RESTOREDIR/files
		echo ""
		echo "FILES from $DEST/files... DONE!"
		echo ""
	else
		echo "No backup FILES configured to backup. Nothing to restore."
	fi
}

function restoreWizard(){
	WIZARD=1
    clear
    echo "################## Welcome to UXBR Recovery wizard ############################"
    echo ""
    echo " This backup and recovery tool does not overrides nor modify your existing	"
    echo " data, then you must have a destination folder ready to do the entire 	"
    echo " or partial restore process.											        "
    echo ""
    echo "##############################################################################"
    echo ""
    echo " Choose a restore option:"
    echo "	1) Full restore"
    echo " 	2) Set restore"
    echo "	3) Restore a single file of your repository"
    echo "	4) Restore other configuration file or directory"
    echo ""
    echo -n " Enter an option [1|2|3|4|5] or CTRL+c to exit: " 
    builtin read ASK1
    case $ASK1 in
    	1 ) 
    		RESTORECHOOSED=full
    		echo ""
    		echo " This wizard will help you to restore your Indexes, Data Base, Content Store and rest of files to a given directory."
    		echo ""
    		echo -n " Type a destination path with enough space available: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		echo ""
    		echo -n " Do you want to see what backups collections are available to restore? [yes|no]: "
			read SHOWCOLANSWER
			shopt -s nocasematch
			case "$SHOWCOLANSWER" in
  				y|yes) 
  					collectionCommands collection all
					;;
  				n|no) 
    				;;
  				* ) echo "Incorrect value provided. Please enter yes or no." 
  				;; 
			esac
    		echo ""
    		echo " Specify a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo " You want to restore a $RESTORECHOOSED backup from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
    		#duplicity restore --restore-time 
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			restoreDb
			restoreContentStore
			restoreFiles
			echo ""
			echo " Restore finished! Now you have to copy and replace your existing content with the content left in $RESTOREDIR, if you need a guideline about how to recovery your Alfresco installation from a backup please read the Alfresco Backup and Desaster Recovery White Paper file."
			echo ""
			exit 1
		;; 		
    	
  		2 ) 
  			RESTORECHOOSED=partial
    		echo ""
    		echo " This wizard will help you to restore one of your backup components: Indexes, Data Base, Content Store or rest of files to a given directory."
    		echo ""
    		echo -n " Type a component to restore [index|db|cs|files]: "
    		builtin read BACKUPGROUP
    		echo -n " Type a destination path with enough space available: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		echo ""
    		echo -n " Do you want to see what backups collections are available for $BACKUPGROUP to restore? [yes|no]: "
			read SHOWCOLANSWER
			shopt -s nocasematch
			case "$SHOWCOLANSWER" in
  				y|yes) 
  					collectionCommands collection $BACKUPGROUP
					;;
  				n|no) 
    				;;
  				* ) echo "Incorrect value provided. Please enter yes or no." 
  				;; 
			esac
    		echo ""
    		echo " Specify a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo " You want to restore a $RESTORECHOOSED backup of $BACKUPGROUP from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
    		#duplicity restore --restore-time 
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			case $BACKUPGROUP in
			"db" )
				restoreDb
			;;
			"cs" )
				restoreContentStore
			;;
			"files" )
				restoreFiles
    		;;
			* )
				echo "ERROR: Invalid parameter, there is no backup group with this name!"
		
			esac
			echo ""
			echo " Restore finished! Now you have to copy and replace your existing content with the content left in $RESTOREDIR, if you need a guideline about how to recovery your Alfresco installation from a backup please read the Alfresco Backup and Desaster Recovery White Paper."
			echo ""
			exit 1
		;;
		3 )
			echo ""
			echo " This option will restore a single content file from your backup."
    		echo " Type a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days: " 
    		builtin read RESTOREDATE 
    		echo " Type file name or any information about the file name you are looking for. I.e.: report."
    		echo -n " Document name: "
    		builtin read CONTENTCLUE
#    		echo " You want to restore a file like $CONTENTCLUE from $RESTOREDATE"
#    		echo -n " Is that correct? [yes|no]: "
#    		read CONFIRMRESTORE
#			read -p " To start restoring your selected file press ENTER or CTRL+C to exit"
			echo ""
			
			if [ ${DBTYPE} == 'mysql' ]; then
				restoreMysqlAtPointInTime
				searchNodeUrlInMysql
				restoreSelectedNode
				else
				echo "ONLY MYSQL IS SUPPORTED FOR SINGLE FILE RECOVERY YET. WAIT FOR NEXT VERSION"
				#	searchNodeUrlPosgres
				#	searchNodeUrlOracle
			fi	
		;;

		4 )
			echo ""
    		echo " This option will restore any other file or directory from your installation or customization (files). "
    		echo ""
    		
    		echo ""
    		echo -n " Type the file or directory name you want to restore: "
			builtin read FILE_TO_SEARCH_IN_FILES
			echo ""
			echo " Looking for this file in the backup..."
			echo ""
			./`basename $0` list files|grep $FILE_TO_SEARCH_IN_FILES
			echo ""
			echo -n " Type the file or directory full path: "	
			builtin read FILE_TO_RESTORE_PATH
    		echo ""
    		echo " Type a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo -n " Type a destination path: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		FILE_TO_RESTORE=`basename $FILE_TO_RESTORE_PATH` 
    		echo " You want to restore a $RESTORECHOOSED backup of $FILE_TO_RESTORE from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			$DUPLICITYBIN restore --restore-time $RESTOREDATE --file-to-restore $FILE_TO_RESTORE_PATH $DEST/files $RESTOREDIR/$FILE_TO_RESTORE
		;;
  		q ) 
  			exit 0
  		;;
  		* ) 
  			restoreWizard
  		;;
		esac
}			
	
function restoreMysqlAtPointInTime (){
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Command: $DUPLICITYBIN restore --restore-time $RESTOREDATE --file-to-restore $DBNAME.dump $DEST/$DBTYPE /tmp/$DBNAME.dump.gz" >> $UXBR_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTOREDATE --file-to-restore $DBNAME.dump $DEST/$DBTYPE /tmp/$DBNAME.dump.gz
		$GZIP -d /tmp/$DBNAME.dump.gz
		## TODO: Clean DB if its already populated
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Command: $REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS $REC_MYDBNAME < /tmp/$DBNAME.dump" >> $UXBR_LOG_FILE
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS $REC_MYDBNAME < /tmp/$DBNAME.dump >> $UXBR_LOG_FILE
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Recovery DB populated" >> $UXBR_LOG_FILE
}

# Function to search a node URL based on a string in the node name, it shows a result and the user has to type the chosen node_id
function searchNodeUrlInMysql (){
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select node_id,string_value from alf_node_properties where STRING_VALUE like '%$CONTENTCLUE%'"
		echo " Type the node_id of the file you want to restore to /tmp."
    	echo -n " Document node_id: "
    	builtin read NODE_ID
		
		NODE_URL=`$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select n.id, u.content_url from alf_node n, alf_node_properties p, alf_namespace ns, alf_qname q, alf_content_data d, alf_content_url u where n.id = p.node_id and q.local_name = 'content' and ns.uri = 'http://www.alfresco.org/model/content/1.0' and ns.id = q.ns_id and p.qname_id = q.id and p.long_value = d.id and d.content_url_id = u.id and n.id=$NODE_ID;"|grep store|awk -F 'store:/' '{ print "contentstore" $2 }'`
		NODE_NAME=`$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select node_id,string_value from alf_node_properties where STRING_VALUE like '%$CONTENTCLUE%';"|grep $NODE_ID|awk -F'$NODE_ID' '{ print $2 }'`
		NODE_FORMAT=`file $DIRROOT/$NODE_URL`
		NODE_FILE_NAME=`$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select string_value from alf_node_properties where node_id='$NODE_ID';"|grep -v \||grep -v string_value|head -1|sed -e 's/ /_/g'`
		
		echo "Trying to restore $NODE_URL as $NODE_NAME " 
		echo ""
		echo "Node file format: $NODE_FORMAT"
		echo ""
		rm -fr /tmp/$DBNAME.dump
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Cleaning recovery DB..." >> $UXBR_LOG_FILE
		echo ""
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "drop database $REC_MYDBNAME;"
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -e "create database $REC_MYDBNAME;"
}

function restoreSelectedNode (){
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG - Command: $DUPLICITYBIN restore --restore-time $RESTOREDATE --file-to-restore $NODE_URL $DEST/$DBTYPE /tmp/$NODE_FILE_NAME" >> $UXBR_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTOREDATE --file-to-restore $NODE_URL $DEST/cs /tmp/$NODE_FILE_NAME
		echo ""
		echo "Whooooohooooo!!"
		echo ""
		echo "Your restored file has been placed in /tmp/$NODE_FILE_NAME rename with its name and format before opening if necessary."
}	

function verifyCommands (){
#    	if [ -z $2 ]; then	
#			echo "Please specify a valid backup group name to verify [index|db|cs|files|all]" 
#		else
		case $2 in
			"db" )
				echo "=========================== BACKUP VERIFICATION FOR DB $DBTYPE ==========================="    
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/$DBTYPE $LOCAL_BACKUP_DB_DIR
				echo "DONE!"
			;;
			"cs" )
				echo "=========================== BACKUP VERIFICATION FOR CONTENTSTORE ==========================="
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/cs $CONTENTSTORE 
				echo "DONE!"
			;;
			"files" )
				echo "=========================== BACKUP VERIFICATION FOR FILES ==========================="
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/files $FILESDIR 
    			echo "DONE!"
			;;
			"system" )
				echo "=========================== BACKUP VERIFICATION FOR SYSTEM ==========================="
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/system $INSTALLATION_DIR 
    			echo "DONE!"
			;;
			* )
				
				echo "=========================== BACKUP VERIFICATION FOR DB $DBTYPE ==========================="; \
	   			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/$DBTYPE $LOCAL_BACKUP_DB_DIR; \
	   			echo "=========================== BACKUP VERIFICATION FOR CONTENTSTORE ==========================="; \
				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/cs $CONTENTSTORE; \
				echo "=========================== BACKUP VERIFICATION FOR FILES ==========================="; \
				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/files $FILESDIR; \ 
				echo "=========================== BACKUP VERIFICATION FOR SYSTEM ==========================="; \
				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/system $LOCAL_BACKUP_SYS_DIR 
			;;
		esac 
#		fi
}

function listCommands(){
		case $2 in
			"db" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/$DBTYPE
			;;
			"cs" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/cs
			;;
			"files" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/files 
			;;
			"system" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/system 
			;;
			* )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/$DBTYPE; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/cs; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/files; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/system
			;;
		esac 
#		fi
}

function collectionCommands () {
#		if [ -z $2 ]; then	
#			echo " Please specify a valid backup group name to access its collection [db|cs|files|system|all]" 
#		else
		case $2 in
			"db" )
				echo "=========================== BACKUP COLLECTION FOR DB $DBTYPE =========================="
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/$DBTYPE
			;;
			"cs" )
				echo "========================== BACKUP COLLECTION FOR CONTENTSTORE ========================="
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/cs
			;;
			"files" )
				echo "============================== BACKUP COLLECTION FOR FILES ============================"
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/files			
			;;
			"system" )
				echo "============================== BACKUP COLLECTION FOR SYSTEM ============================"
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/system			
			;;
			* )
				echo "=========================== BACKUP COLLECTION FOR DB $DBTYPE =========================="; \
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/$DBTYPE; \
				echo "========================== BACKUP COLLECTION FOR CONTENTSTORE ========================="; \
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/cs; \
				echo "============================== BACKUP COLLECTION FOR FILES ============================"; \
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/files; \
				echo "============================== BACKUP COLLECTION FOR SYSTEM ============================"; \
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${UXBR_LOG_FILE} $DEST/system; \	
				
			;;
		esac 
#		fi
}
    
function maintenanceCommands () {
	# Function to apply backup policies
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running maintenance commands" >> $UXBR_LOG_FILE
	
	if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
	case $DBTYPE in 
		"mysql" ) 
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/$DBTYPE" >> $UXBR_LOG_FILE
			$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/$DBTYPE >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/$DBTYPE" >> $UXBR_LOG_FILE 2>&1
  			$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/$DBTYPE >> $UXBR_LOG_FILE
		;; 
		"postgresql" )
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/$DBTYPE" >> $UXBR_LOG_FILE
			$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/$DBTYPE >> $UXBR_LOG_FILE
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/$DBTYPE" >> $UXBR_LOG_FILE 2>&1
			$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/$DBTYPE >> $UXBR_LOG_FILE		
		;; 		
		"oracle" )
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/$DBTYPE" >> $UXBR_LOG_FILE
  			$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/$DBTYPE >> $UXBR_LOG_FILE
  			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/$DBTYPE" >> $UXBR_LOG_FILE 2>&1
  			$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/$DBTYPE >> $UXBR_LOG_FILE
		;;	
	esac
	fi

	if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/cs" >> $UXBR_LOG_FILE
  		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/cs >> $UXBR_LOG_FILE 2>&1
  		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/cs" >> $UXBR_LOG_FILE 2>&1
  		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/cs >> $UXBR_LOG_FILE 2>&1
	fi
	if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/files" >> $UXBR_LOG_FILE
  		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/files >> $UXBR_LOG_FILE 2>&1
  		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/files" >> $UXBR_LOG_FILE 2>&1
  		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/files >> $UXBR_LOG_FILE 2>&1
	fi 
	if [ ${BACKUP_SYSTEM_ENABLED} == 'true' ]; then
		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/system" >> $UXBR_LOG_FILE
  		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force --extra-clean $DEST/system >> $UXBR_LOG_FILE 2>&1
  		echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/system" >> $UXBR_LOG_FILE 2>&1
  		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${UXBR_LOG_FILE} --force $DEST/system >> $UXBR_LOG_FILE 2>&1
	fi 
	echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Maintenance commands DONE!" >> $UXBR_LOG_FILE
}

# Main options
case $1 in
	"backup" ) 
		case $2 in
			"db" )
			# Run backup of db if enabled
			if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
				dbBackup
			fi
			;;
			"cs" )
			# Run backup of contentStore if enabled
			if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
				contentStoreBackup
			fi
			;;
			"files" )
			# Run backup of files if enabled
			if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
				filesBackup
			fi
			;;
			"system" )
			# Run backup of system
			if [ ${BACKUP_SYSTEM_ENABLED} == 'true' ]; then
				systemBackup
			fi
			;;
			* )
				case $3 in 
					"force" )
						PARAMS="$PARAMS --allow-source-mismatch"
					;;
				esac
			
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Starting backup" >> $UXBR_LOG_FILE
			echo "$LOG_DATE_LOG - $UXBR_LOG_TAG Set script varibles done" >> $UXBR_LOG_FILE
			# Run backup of db if enabled
			if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
				dbBackup
			fi
			# Run backup of contentStore if enabled
			if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
				contentStoreBackup
			fi
			# Run backup of files if enabled
			if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
				filesBackup
			fi 
			# System installation backup
			if [ ${BACKUP_SYSTEM_ENABLED} == 'true' ]; then
				systemBackup
			fi
			# Maintenance commands (cleanups and apply retention policies)
			if [ ${BACKUP_POLICIES_ENABLED} == 'true' ]; then
				maintenanceCommands
			fi
		esac

	;;
	
	"restore" )	
		case $2 in
			"db" )
				restoreDb $1 $2 $3 $4
			;;
			"cs" )
				restoreContentStore $1 $2 $3 $4
			;;
			"files" )
				restoreFiles $1 $2 $3 $4
			;;
			"all" )
				restoreIndexes $1 $2 $3 $4
				restoreDb $1 $2 $3 $4
				restoreContentStore $1 $2 $3 $4
				restoreFiles $1 $2 $3 $4
				restoreSystem $1 $2 $3 $4
			;;
			* )
			restoreWizard
		esac
   	
    ;;
    
	"verify" ) 
		verifyCommands $1 $2
	;;
    
	"list" ) 
    	listCommands $1 $2
    ;;
    
	"collection" )
		collectionCommands $1 $2
    ;;

	* ) 	
		usage
	;;
esac

# Unload al security variables
unset PASSPHRASE
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset DBPASS
unset FTP_PASSWORD
unset REC_MYPASS
unset REC_PGPASS
unset REC_ORAPASS
unset PGPASSWORD
