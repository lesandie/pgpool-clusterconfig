#!/bin/bash

# Store csv path
WORKING_DIR="/home/dnieto/Repos/geocaptor/csv"
# Paths for binary files
CURL="/usr/bin/curl"
LOGGER="/usr/bin/logger"
PSQL="/usr/bin/psql"
# The / at the end is for directory listing in the remote host
HOST="https://xxx.xxx.xxx.xxx/secret/geocap/"
USER_HTTP="xxxx"
PASS_HTTP="nxxxxx"
# PostgreSQL connection data
PGHOST="dbpostgres1.xxx.xxx.xxx"
PGPORT="9999"
PGUSER="xxxxx"
PGPASS="xxxxx"

# make sure backup directory exists
#[ ! -d $WORKING_DIR ] && mkdir -p ${WORKING_DIR}
# Get the csv list from the remote host
R_CSVs=$($CURL -u ${USER_HTTP}:${PASS_HTTP} https://xxxxxxxxxxxxxxxx/ | cut -d'"' -f2 | egrep csv)
#Remove this-day-last-week
#rm $(date +'%A')_$(date +'%F')_*
# Delete the contents of the unlogged table prior to load
$PSQL postgres://${PGUSER}:${PGPASS}@${PGHOST}:${PGPORT}/ddbb_geocap -c "DELETE FROM csv_load;"
# For each element in the list download the csv
for R_CSV in $R_CSVs; do
        $CURL -u ${USER_HTTP}:${PASS_HTTP} https://xxxxxxxxx/${R_CSV} -o ${WORKING_DIR}/${R_CSV} \
        && \
        $PSQL postgres://${PGUSER}:${PGPASS}@${PGHOST}:${PGPORT}/ddbb_geocap -c "\COPY csv_load FROM '${WORKING_DIR}/${R_CSV}' WITH DELIMITER AS ';' CSV HEADER;"
        # Log backup start time in /var/log/messages
        $LOGGER "$0: *** ${RCSV} file copied succesfully @ $(date) ***"
done

