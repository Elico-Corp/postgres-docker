#!/bin/sh
#
# Postgresql backup script
#
# Author
#  |
#  +-- speedboy (speedboy_420 at hotmail dot com)
#  +-- spiderr (spiderr at bitweaver dot org)
#  +-- Sebastien Maillard (sebastien dot maillard at elico-corp dot com)
#
# Last modified
#  |
#  +-- 16-10-2001
#  +-- 16-12-2007
#  +-- 02-02-2016
#
# Version
#  |
#  +-- 1.1.3
#
# Description
#  |
#  +-- A bourne shell script that automates the backup, vacuum and
#      analyze of databases running on a postgresql server.
#
# Tested on
#  |
#  +-- Postgresql
#  |    |
#  |    +-- 9.4
#  |    +-- 8.1.9
#  |    +-- 7.1.3
#  |    +-- 7.1.2
#  |    +-- 7.1
#  |    +-- 7.0
#  |
#  +-- Operating systems
#  |    |
#  |    +-- CentOS 5 (RHEL 5)
#  |    +-- Linux Redhat 6.2
#  |    +-- Linux Mandrake 7.2
#  |    +-- FreeBSD 4.3
#  |    +-- Cygwin (omit the column ":" because NT doesn't quite digest it)
#  |
#  +-- Shells:
#       |
#       +-- sh
#       +-- bash
#       +-- ksh
#
# Requirements
#  |
#  +-- grep, awk, sed, echo, bzip2, chmod, touch, mkdir, date, psql,
#      test, expr, dirname, find, tail, du, pg_dump, vacuum_db
#
# Installation
#  |
#  +-- Set the path and shell you wish to use for this script on the
#  |   first line of this file. Keep in mind this script has only been
#  |   tested on the shells above in the "Tested on" section.
#  |
#  +-- Set the configuration variables below in the configuration
#  |   section to appropriate values.
#  |
#  +-- Remove the line at the end of the configuration section so that
#  |   the script will run.
#  |
#  +-- Now save the script and perform the following command:
#  |
#  |   chmod +x ./pg_backup.sh
#  |
#  +-- Now run the configuration test:
#  |
#  |   ./pg_backup.sh configtest
#  |
#  |   This will test the configuration details.
#  |
#  +-- Once you have done that add similiar entries given as examples
#      below to the crontab (`crontab -e`) without the the _first_ #
#      characters.
#
#      # Run a backup of the remote database host 'foodb', likely on a private network
#      00 03 * * * export PGHOST=foodb; export PGBACKUPDIR=/bak/backups ; nice /server/postgres/pg_backup.sh b 2  >> /var/log/pgsql/pg_backup.log 2>&1
#      # Run a backup of the local database host 'foodb' to a custom backup directory
#      00 04 * * * export PGBACKUPDIR=/bak/backups ; nice /usr/bin/pg_backup b 2  >> /var/log/pgsql/pg_backup.log 2>&1
#
# Restoration
#  |
#  +-- Restoration can be performed by using psql or pg_restore.
#  |   Here are two examples:
#  |
#  |   a) If the backup is plain text:
#  |
#  |   Firstly bunzip2 your backup file (if it was bzip2ped).
#  |
#  |   nunzip2 backup_file.bz2
#  |   psql -U postgres database < backup_file
#  |
#  |   b) If the backup is not plain text:
#  |
#  |   Firstly bunzip2 your backup file (if it was bzip2ed).
#  |
#  |   bunzip2 backup_file
#  |   pg_restore -d database -F {c|t} backup_file
#  |
#  |   Note: {c|t} is the format the database was backed up as.
#  |
#  |   pg_restore -d database -F t backup_file_tar$PARAM_PGHOST
#  |
#  +-- Refer to the following url for more pg_restore help:
#
#      http://www.postgresql.org/idocs/index.php?app-pgrestore.html
#
# To Do List
#              1. db_connectivity() is BROKEN, if the script can not create a
#                 connection to postmaster it should die and write to the logfile
#                 that it could not connect.
#              2. make configtest check for every required binary
#
########################################################################
#                          Start configuration                         #
########################################################################
#
##################
# Authentication #
##################
#
# Postgresql username to perform backups under.
if [ -z $PGUSER ]; then
        PGUSER="$POSTGRES_USER"
fi
 
##################
# Locations      #
##################
#
# Location to place backups.
if [ -z $PGBACKUPDIR ]; then
        PGBACKUPDIR="/mnt/pg_backup"
fi
 
# Location of the psql binaries.
if [ -z $PGBINDIR ]; then
        PGBINDIR="/usr/bin"
fi
 
##################
# Permissions    #
##################
#
# Permissions for the backup location.
permissions_backup_dir="0755"
 
# Permissions for the backup files.
permissions_backup_file="0644"
 
##################
# Other options  #
##################
#
# Databases to exclude from the backup process (separated by a space)
exclusions="postgres $PGUSER"

# Backup format
#  |
#  +-- p = plain text : psql database < backup_file
#  +-- t = tar        : pg_restore -F t -d database backup_file
#  +-- c = custom     : pg_restore -F c -d database backup_file
#
backup_format="p"

# Backup large objects
backup_large_objects="no"

# bzip2 the backups
backup_bzip2="yes"

# Date format for the backup
#  |
#  +-- %d-%m-%Y       = DD-MM-YYYY
#  +-- %Y-%m-%d       = YYYY-MM-DD
#  +-- %A-%b-%Y       = Tuesday-Sep-2001
#  +-- %A-%Y-%d-%m-%Y = Tuesday-2001-18-09-2001
#  |
#  +-- For more date formats type:
#
#      date --help
#
backup_date_format="%Y-%m-%d"

# You must comment out the line below before using this script
#echo "You must set all values in the configuration section in this file then run ./pg_backup.sh configtest before using this script" && exit 1
########################################################################
#                          End configuration                           #
########################################################################
#
#################
# Variables     #
#################
#
version="1.1.3"
current_time=`date +%H%M`
date_info=`date +$backup_date_format`

# Export the variables
export PGUSER

#################
# Checking      #
#################
#
# Check the backup format
if [ "$backup_format" = "p" ]; then
        backup_type="Plain text SQL"
        backup_args="-F $backup_format"

elif [ "$backup_format" = "t" ]; then
        backup_type="Tar"
        if [ "$backup_large_objects" = "yes" ]; then
                backup_args="-b -F $backup_format"
        else
                backup_args="-F $backup_format"
        fi
elif [ "$backup_format" = "c" ]; then
        backup_type="Custom"
        if [ "$backup_large_objects" = "yes" ]; then
                backup_args="-b -F $backup_format"
        else
                backup_args="-F $backup_format"
        fi
else
        backup_format="c"
        backup_args="-F $backup_format"
        backup_type="Custom"
fi

#################
# Functions     #
#################
#
# Obtain a list of available databases with reference to the user
# defined exclusions
db_connectivity() {
        tmp=`echo "($exclusions)" | sed 's/\ /\|/g'`
        if [ "$exclusions" = "" ]; then
                databases=`$PGBINDIR/psql -U $PGUSER --tuples-only -P format=unaligned -c "SELECT datname FROM pg_database WHERE NOT datistemplate"`
        else
                # databases=`$PGBINDIR/psql -U $PGUSER -q -c "\l" template1 | sed -n 4,/\eof/p | grep -v rows\) | grep -Ev $tmp | awk {'print $1'} || echo "Database connection could not be established at $timeinfo"`
                databases=`$PGBINDIR/psql -U $PGUSER --tuples-only -P format=unaligned -c "SELECT datname FROM pg_database WHERE NOT datistemplate" | grep -Ev $tmp`
        fi
}
 
# Setup the permissions according to the Permissions section
set_permissions() {
        # Make the backup directories and secure them.
        mkdir -m $permissions_backup_dir -p "$PGBACKUPDIR"
 
        # Make the backup tree
        chmod -f $permissions_backup_dir "$PGBACKUPDIR"
}
 
# Run backup
run_b() {
        for i in $databases; do
                start_time=`date '+%s'`
                timeinfo=`date '+%T %x'`

		OF="$PGBACKUPDIR/$date_info-pg_db-$i.backup"

                "$PGBINDIR/pg_dump" $backup_args $i > "$OF"

                if [ "$backup_bzip2" = "yes" ]; then
			bzip2 "$OF"
                        chmod $permissions_backup_file "$OF.bz2"
                else
                        chmod $permissions_backup_file "$OF"
                fi

                finish_time=`date '+%s'`
                duration=`expr $finish_time - $start_time`
                echo "Backup complete (duration $duration seconds) at $timeinfo for schedule $current_time on database: $i, format: $backup_type"
                echo "Backup File Name: $OF"
        done
        exit 1
}
 
# Run backup and vacuum
run_bv() {
        for i in $databases; do
                start_time=`date '+%s'`
                timeinfo=`date '+%T %x'`

                OF="$PGBACKUPDIR/$date_info-pg_db-$i.backup"
 
                "$PGBINDIR/vacuumdb" -U $PGUSER $i >/dev/null 2>&1
                "$PGBINDIR/pg_dump" $backup_args $i > "$OF"

                if [ "$backup_bzip2" = "yes" ]; then
			bzip2 "$OF"
                        chmod $permissions_backup_file "$OF.bz2"
                else
                        chmod $permissions_backup_file "$OF"
                fi

                finish_time=`date '+%s'`
                duration=`expr $finish_time - $start_time`
                echo "Backup and Vacuum complete (duration $duration seconds) at $timeinfo for schedule $current_time on database: $i, format: $backup_type"
                echo "Backup File Name: $OF"
        done
        exit 1	
}
 
# Run backup, vacuum and analyze
run_bva() {
        for i in $databases; do
                start_time=`date '+%s'`
                timeinfo=`date '+%T %x'`

                OF="$PGBACKUPDIR/$date_info-pg_db-$i.backup"
 
                "$PGBINDIR/vacuumdb" -z -U $PGUSER $i >/dev/null 2>&1
                "$PGBINDIR/pg_dump" $backup_args $i > "$OF"

                if [ "$backup_bzip2" = "yes" ]; then
			bzip2 "$OF"
                        chmod $permissions_backup_file "$OF.bz2"
                else
                        chmod $permissions_backup_file "$OF"
                fi

                finish_time=`date '+%s'`
                duration=`expr $finish_time - $start_time`
                echo "Backup, Vacuum and Analyze complete (duration $duration seconds) at $timeinfo for schedule $current_time on database: $i, format: $backup_type"
                echo "Backup File Name: $OF"
        done
        exit 1
}
 
# Run vacuum
run_v() {
        for i in $databases; do
                start_time=`date '+%s'`
                timeinfo=`date '+%T %x'`
 
                "$PGBINDIR/vacuumdb" -U $PGUSER $i >/dev/null 2>&1

                finish_time=`date '+%s'`
                duration=`expr $finish_time - $start_time`
                echo "Vacuum complete (duration $duration seconds) at $timeinfo for schedule $current_time on database: $i "
        done
        exit 1
}
 
# Run vacuum and analyze
run_va() {
        for i in $databases; do
                start_time=`date '+%s'`
                timeinfo=`date '+%T %x'`
 
                "$PGBINDIR/vacuumdb" -z -U $PGUSER $i >/dev/null 2>&1

                finish_time=`date '+%s'`
                duration=`expr $finish_time - $start_time`
                echo "Vacuum and Analyze complete (duration $duration seconds) at $timeinfo for schedule $current_time on database: $i "
        done
        exit 1
}
 
# Print information regarding available backups
print_info() {
        echo "Postgresql backup script version $version"
        echo ""
        echo "Available backups:"
        echo ""
        if [ ! -d $PGBACKUPDIR ] ; then
                echo "There are currently no available backups"
                echo ""
                exit 0
        else
                echo "$i `du -h \"$i\" | tail -n 1 | awk {'print $1'}`"
                echo ""
        fi
        exit 1
}
 
# Print configuration test
print_configtest() {
        echo "Postgresql backup script version $version"
        echo ""
        echo "Configuration test..."
        echo ""
 
        # Check database connectivity information
        echo -n "Database username                    : "
        echo "$PGUSER"
        echo -n "Database connectivity                : "
        $PGBINDIR/psql -U $PGUSER -q -c "select now()" $PGUSER > /dev/null 2>&1 && echo "Yes" || echo "Connection could not be established..."
 
        # Backup information
        echo ""
        echo "Backup information:"
        echo ""
        echo -n "Backup format                        : "
        if [ "$backup_format" = "p" ]; then
                echo "Plain text SQL"
        elif [ "$backup_format" = "t" ]; then
                echo "Tar"
        else
                echo "Custom"
        fi
 
        echo -n "Backup large objects                 : "
        if [ "$backup_large_objects" = "yes" ]; then
                echo "Yes"
        else
                echo "No"
        fi
        echo -n "bzip2 backups                        : "
        if [ "$backup_bzip2" = "yes" ]; then
                echo "Yes"
        else
                echo "No"
        fi
        echo -n "Backup date format                   : $date_info"
        echo ""
 
        # File locations
        echo -n "Backup directory                     : "
        echo "$PGBACKUPDIR"
        echo -n "Postgresql binaries                  : "
        echo "$PGBINDIR"
 
        # Backup file permissions
 
        echo -n "Backup directory permissions         : "
        echo "$permissions_backup_dir"
        echo -n "Backup file permissions              : "
        echo "$permissions_backup_file"
 
        # Databases that will be backed up
        echo -n "Databases that will be backed up     : "
        echo ""
        if [ "$databases" = "" ]; then
                echo "                                       none"
        else
                for i in $databases; do
                        echo "                                       $i"
                done
                echo ""
        fi
 
        # Databases that will not be backed up
        echo -n "Databases that will not be backed up :"
        echo ""
        if [ "$exclusions" = "" ]; then
                echo "                                       none"
        else
                for i in $exclusions; do
                        echo "                                       $i"
                done
                echo ""
        fi
 
        # Check if the backups location is writable
        echo "Checking permissions:"
        echo ""
        echo -n "Write access                         : $PGBACKUPDIR: "
        # Needed to create/write to the dump location"
        test -w "$PGBACKUPDIR" && echo "Yes" || echo "No"
 
        # Check if the binaries are executable
        echo -n "Execute access                       : $PGBINDIR/psql: "
        test -x $PGBINDIR/psql && echo "Yes" || echo "No"
 
        echo -n "Execute access                       : $PGBINDIR/pg_dump: "
        test -x $PGBINDIR/pg_dump && echo "Yes" || echo "No"
 
        echo -n "Execute access                       : $PGBINDIR/vacuumdb: "
        test -x $PGBINDIR/vacuumdb && echo "Yes" || echo "No"
 
        echo ""
        exit 1
}
 
# Print help
print_help() {
        echo "Postgresql backup script version $version"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  b,          Backup ALL databases"
        echo "  bv,         Backup and Vacuum ALL databases"
        echo "  bva,        Backup, Vacuum and Analyze ALL databases"
        echo "  v,          Vacuum ALL databases"
        echo "  va,         Vacuum and Analyze ALL databases"
        echo "  info,       Information regarding all available backups"
        echo "  configtest, Configuration test"
        echo "  help,       This message"
        echo ""
        exit 1
}

case "$1" in
        # Run backup
        b)
                db_connectivity
                set_permissions
                run_b
                exit 1
                ;;
        # Run backup and vacuum
        bv)
                db_connectivity
                set_permissions
                run_bv
                exit 1
                ;;
 
        # Run backup, vacuum and analyze
        bva)
                db_connectivity
                set_permissions
                run_bva
                exit 1
                ;;
 
        # Run vacuum
        v)
                db_connectivity
                set_permissions
                run_v
                exit 1
                ;;
 
        # Run vacuum and analyze
        va)
                db_connectivity
                set_permissions
                run_va
                exit 1
                ;;
 
        # Print info
        info)
                set_permissions
                print_info
                exit 1
                ;;
 
        # Print configtest
        configtest)
                db_connectivity
                set_permissions
                print_configtest
                exit 1
                ;;
 
        # Default
        *)
                print_help
                exit 1
                ;;
esac
