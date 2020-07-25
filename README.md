Check Point Scripts
==================

Scripts for automating some aspect of management of Check Point firewalls or management servers.

Where a script might run on either Smartcenter (now called SMS) or Provider-1 (MDSM or something) it will detect the platform and act accordingly.

All scripts developed for and tested on SPLAT. They'll probably run on GAIA but I haven't tested them.

## backup-mds.sh

Script to back up an MDS (formerly Provider-1) and FTP or SCP it off to somewhere, optionally with email reporting.

## db_prune.sh

**This script has been mostly superseded by functionality that is now built in to the management servers.**

Run the script from the shell (in expert mode). It'll search the smartcenter or each CMA on a provider-1 for database versions that are older than a configured age (90 days as it stands). If it finds any it will prompt for a username and password in order to run the dbver tool to delete them. On a Provider-1 system it will remember the credentials for the run so you don't need to enter them again.

The script can't be automated in a cron job because of the password requirement. If you want to hard-code a username and password in then that's at your own risk.


## log-bundle.sh

Script to bundle up the logfile and associated logfile pointers that are generated each day and compress them using gzip on maximal compression.

When run in auto bundle mode it will find any checkpoint log older than $AGE and bundle that logfile and pointers. If $DELETE is greater than 0 the script will also delete bundles older than $DELETE.

Test mode adds "echo " to the front of each executed command so that it just tells you what it would do.

    Usage Guide:
     log-bunde.sh -a = auto bundle (bundle all logs older than $AGE days)
     log-bunde.sh -t = test mode (just echo commands used for auto bundle)
     log-bunde.sh <logname> = bundle <logname>

