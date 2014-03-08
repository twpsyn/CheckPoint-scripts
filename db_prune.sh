#!/bin/bash

# db_prune.sh (universal edition) Matt Hill
# Will delete old database versions based on AGE set below. Maintains a minimum
# number of versions based on MINREV.
# Detects if this is a smartcenter or provider-1 and acts accordingly, iterating
# over all CMAs on a P-1 or just once for a Smartcenter

# Changelog
#  2012-08-21 - Added in checking that there are a minimum number of revisions
#					before and during deletion.
#					 Also added checking for Provider-1 or Smartcenter.
#	2013-01-07 - Modified find parameters to only match version directories

AGE=90							#how long to keep revisions for
MINREV=10						#keep at least this many revisions

CPUSER=""						#start with blank username
CPPASS=""						# and password


function do_delete {
	DBVER="$FWDIR/bin/dbver"
	cd $FWDIR/conf/db_versions/repository
	VER_DIRS=`find . -mtime +$AGE -prune -type d -regex "\.\/[0-9]*" | sed 's/[^0-9]//g' | sort -g`

	# As before, use arrays here so that we can compute the size of them later.
	VDARR=( `ls` )
	DELARR=( $VER_DIRS )

	# check that we have versions to delete before proceeding
	if [ "$VER_DIRS" != "" ]; then

		echo "We have ${#DELARR[@]} versions to delete out of ${#VDARR[@]} total"

		echo ""

		# Check for username and password, we only want to have to enter this 
		#  once and it'll be reused if necessary.
		if [ "$CPUSER" == "" ]; then
			echo "I need a username and password please"
			read -p "Username: " CPUSER
			read -s -p "Password: " CPPASS
		else
			echo "Reusing username and password"
		fi

		echo ""

		for DIR in $VER_DIRS; do

			# Before deleting, we'll first check that we have more than the 
			#  minimum revisions
			LSCOUNT=`ls | wc -l | sed 's/\ //g'`  #(removing leading space)
			if [ "$LSCOUNT" -lt "$MINREV" ]; then
				echo "Fewer than $MINREV revisions. Abandoning!"
				break
			fi

			VER=`echo $DIR | sed 's/[^0-9]//g'` #strip all but numbers (remove ./)
			echo ""
			echo -n "Deleting version $VER ... "
			$DBVER -u $CPUSER -w $CPPASS -m delete $VER
		done

		echo ""
		echo "Finished"
		echo ""
	else
		echo "Nothing to delete today (${#VDARR[@]} revisions)"
		echo ""
	fi
}


# set the Check Point environment
if [ -r /etc/profile.d/CP.sh ]; then
	. /etc/profile.d/CP.sh
fi

if [ -z "$MDS_CPDIR" ]; then
	echo "Smartcenter detected"
	echo ""

	do_delete

else
	echo "Provider-1 detected"
	echo ""

	CMAS=`ls $FWDIR/customers`	#get a list of customers

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

		do_delete

		echo "Completed $CMA"
	done

	# reset mdsenv
	mdsenv
fi
