#!/bin/bash
# This script is run after failover_command to recover the slave from the new primary.

set -o xtrace
exec > >(logger -i -p local1.info) 2>&1

# special values:  %d = node id
#                  %h = host name
#                  %p = port number
#                  %D = database cluster path
#                  %m = new master node id
#                  %M = old master node id
#                  %H = new master node host name
#                  %P = old primary node id
#                  %R = new master database cluster path
#                  %r = new master port number
#                  %% = '%' character
FAILED_NODE_ID="$1"
FAILED_NODE_HOST="$2"
FAILED_NODE_PORT="$3"
FAILED_NODE_PGDATA="$4"
NEW_MASTER_NODE_ID="$5"
OLD_MASTER_NODE_ID="$6"
NEW_MASTER_NODE_HOST="$7"
OLD_PRIMARY_NODE_ID="$8"
NEW_MASTER_NODE_PORT="$9"
NEW_MASTER_NODE_PGDATA="${10}"

PGHOME=/usr/lib/postgresql/11
ARCHIVEDIR=/DATA/pg_wal_archive
REPL_USER=replication
PCP_USER=postgres
PGPOOL_PATH=/usr/sbin
PCP_PORT=9898


# Recovery the slave from the new primary
logger -i -p local1.info follow_master.sh: start: pg_basebackup for $FAILED_NODE_ID

# Check the status of standby
ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    postgres@${FAILED_NODE_HOST} ${PGHOME}/bin/pg_ctl -w -D ${FAILED_NODE_PGDATA} status >/dev/null 2>&1

# If slave is running, recover the slave from the new primary.
if [[ $? -eq 0 ]]; then

    # Execute pg_basebackup at slave
    ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${FAILED_NODE_HOST} "
        ${PGHOME}/bin/pg_ctl -w -m f -D ${FAILED_NODE_PGDATA} stop

        rm -rf ${FAILED_NODE_PGDATA}
        ${PGHOME}/bin/pg_basebackup -h ${NEW_MASTER_NODE_HOST} -U ${REPL_USER} -p ${NEW_MASTER_NODE_PORT} -D ${FAILED_NODE_PGDATA} -X stream -R

        if [[ $? -ne 0 ]]; then
            logger -i -p local1.error follow_master.sh: end: pg_basebackup failed
            exit 1
        fi
        rm -rf ${ARCHIVEDIR}/*
cat >> ${FAILED_NODE_PGDATA}/recovery.conf << EOT
restore_command = 'rsync ${NEW_MASTER_NODE_HOST}:${ARCHIVEDIR}/%f %p'
EOT
        $PGHOME/bin/pg_ctl -l /dev/null -w -D ${FAILED_NODE_PGDATA} start
    "

    if [[ $? -eq 0 ]]; then

        # Run pcp_attact_node to attach this slave to Pgpool-II.
        ${PGPOOL_PATH}/pcp_attach_node -w -h localhost -U ${PCP_USER} -p ${PCP_PORT} -n ${FAILED_NODE_ID}

        if [[ $? -ne 0 ]]; then
            logger -i -p local1.error follow_master.sh: end: pcp_attach_node failed
            exit 1
        else
            logger -i -p local1.error follow_master.sh: end: follow master failed
            exit 1
        fi

else
    logger -i -p local1.info follow_master.sh: failed_nod_id=${FAILED_NODE_ID} is not running. skipping follow master command.
    exit 0
fi

logger -i -p local1.info follow_master.sh: end: follow master is finished
exit 0
