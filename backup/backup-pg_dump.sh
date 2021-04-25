#!/bin/bash
# Store backup path
BACKUP="/mnt/backups/postgresql"

# list of databases
#BBDDs="db1 db2 db3"
BBDDs="simba baloo"

# Set PostgreSQL username and password
PGHOST="dbpostgres.xx.xx.xx"
PGUSER="postgres"
#variable PGPASSFILE
#export PGPASSFILE"/root/.pgpass"

# Paths for binary files
#TAR="/bin/tar"
PGDUMP="/usr/bin/pg_dump"
#MYSQL="/usr/bin/mysql"
GZIP="/bin/gzip"
LOGGER="/usr/bin/logger"

# make sure backup directory exists
[ ! -d $BACKUP ] && mkdir -p ${BACKUP}
cd $BACKUP
# Remove this-day-last-week backup
rm $(LC_ALL=en_US.utf8;date +'%A')_*

# Dump all databases. 
for BBDD in $BBDDs; do
        # Backup file name hostname.time.tar.gz
        MFILE="$(date +'%A')_$(date +'%F')_${BBDD}.sql"
        # Log backup start time in /var/log/messages
        $LOGGER "$0: *** ${BBDD} backup started @ $(date) File: ${BACKUP}/${MFILE}***"
        # Backup MySQL, compress the sql and remove it
        $PGDUMP -h ${PGHOST} -U ${PGUSER} -w ${BBDD} > ${BACKUP}/${MFILE}
        # Log backup end time in /var/log/messages
        MFILE="$(date +'%A')_$(date +'%F')_${BBDD}.dump"
        $PGDUMP -h ${PGHOST} -U ${PGUSER} -w -Fc ${BBDD} > ${BACKUP}/${MFILE}
        $LOGGER "$0: *** ${BBDD} backup ended @ $(date) ***"

done
