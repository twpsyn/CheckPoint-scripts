#!/bin/bash

#####
# Log bundler (Matt Hill)
#
# Script to bundle up the logfile and associated logfile pointers that are
#  generated each day and compress them using gzip on maximal compression.
# When run on a smartcenter in auto bundle mode it will find any checkpoint
#  log older than $AGE (set below) and bundle that logfile and pointers.
# When run on an MDS it will do that for each CMA.
##
# 2012-08-30 MH - initial version
# 2012-09-01 MH - modified to require command line options and to add test
#                 and manual modes. Added help text. Now updates timestamp
#						of archive to be that of logfile.
# 2013-07-26 MH - added deletion of old logs, controlled by DELETE variable
##

# set this to the number of days that you wish to keep logs unbundled for
AGE=365

# this one is the number of days to delete bundles after (set to 0 to disable)
DELETE=550 # (slightly over 18 months)

## FUNCTIONS ###

# Bundles log and pointers for logfile passed in as sole parameter
function do_bundle {
	INLOG=$1
	LOGDATE=$(echo $INLOG | sed 's/\.\///' | sed 's/_[0-9]*\.[a-z]*//');\
	if [ -e $LOGDATE.tar.gz ]; then
		echo "$LOGDATE.tar.gz already exists, skipping"
		continue
	fi
	$DEMO tar cvf $LOGDATE.tar --remove-files $LOGDATE* ;\
	$DEMO gzip -9v $LOGDATE.tar ;\

	#fix timestamp
	MAKEDATE=$(echo $LOGDATE | sed 's/\-//g')
	$DEMO touch -t $MAKEDATE"2359" $LOGDATE.tar.gz
}

# For autobundle (and test) finds all logfiles of interest and calls do_bundle
#  on them.
function bundle_loop {
	cd $FWDIR/log
   LOGLIST=`find . -mtime +$AGE -name "*.log"`

   if [ "$LOGLIST" != "" ]; then
		for LOG in $LOGLIST; do
			do_bundle $LOG
		done
	else
		echo "No logs to archive"
	fi

	if [ $DELETE -gt 0 ]; then
		DELETELIST=`find . -mtime +$DELETE -name "*.tar.gz"`
		for BUNDLE in $DELETELIST; do
			$DEMO /bin/rm -v $BUNDLE
		done
	fi
}

# Detects if on Smartcenter or Provider-1 and runs bundle_loop for each
#  CMA or just once for Smartcenter
function autobundle {
	if [ -r /etc/profile.d/CP.sh ]; then
	   . /etc/profile.d/CP.sh
	else
		echo "Could not source /etc/profile.d/CP.sh"
		exit
	fi

	if [ -z "$MDS_CPDIR" ]; then
	   echo "Smartcenter detected"
	   echo ""

	   bundle_loop

	else
	   echo "Provider-1 detected"
	   echo ""

	   CMAS=`ls $FWDIR/customers` #get a list of customers

	   # Throw the list of CMAs into an array so that we can get the size of it
	   #  later on. That is the only place the array is used.
	   CMAARR=( $CMAS )

	   echo "Found the following ${#CMAARR[@]} customers: "
	   for CUST in $CMAS; do
	      echo "  $CUST"
	   done

	   for CMA in $CMAS; do
	      echo ""
	      echo "processing $CMA..."
	      mdsenv $CMA

	      bundle_loop

	      echo "Completed $CMA"
	   done

   	# reset mdsenv
   	mdsenv
	fi
}

## END OF FUNCTION DECLARATIONS ##

DEMO=""

if [[ -z $1 || -n $2 || $1 = "-h" || $1 = "--help" ]]; then
	SN=${0##*/}
	echo ""
	echo "tar and gzips Checkpoint log files and related log pointer files."
	echo "Can either operate automatically for all logs older than $AGE days"
	echo "or can operate on a specific log file."
	echo "For automatic operation, will detect if on an MDS and will iterate"
	echo "over all CMAs."
	echo ""
	echo "Usage Guide:"
	echo " $SN -a = auto bundle (bundle all logs older than $AGE days)"
	echo " $SN -t = test mode (just echo commands used for auto bundle)"
	echo " $SN <logname> = bundle <logname>"
	echo ""
	exit
fi

case $1 in
-t)
	DEMO="echo"
	autobundle
	;;
-a)
	DEMO=""
	autobundle
	;;
*)
	do_bundle $1
	;;
esac

echo ""
