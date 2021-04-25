
# PostgreSQL 11 multimaster and PgPool-II cluster config

# Indice

1. [Node installation](#nodeinstall)
2. [Node configuration](#nodeconfig)
3. [Pgpool-II installation](#pgpoolinstall)
4. [Pgpool-II config](#pgpoolconfig)
5. [PostgreSQL tips](#tipspostgres)
6. [PostreSQL extensions](#extensions)
7. [Info and resources](#bib)

## Node installation

**PostgreSQL node installation in Ubuntu 18.04:**

Repo configuration:

```bash
$sudo apt-get install curl ca-certificates
$curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
$sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
```

Install postgres:

```bash
$sudo apt-get update
$sudo apt-get install postgresql-11
```

**PostgreSQL node installation in CentOS 7:**

Repo configuration:

```bash
$sudo yum install https://download.postgresql.org/pub/repos/yum/11/redhat/rhel-7-x86_64/pgdg-centos11-11-2.noarch.rpm
```

Install postgres:

```bash
$sudo yum update
$sudo yum install postgresql11
$sudo yum install postgresql11-server
```

## Node configuration

There are 2 types of configs, one for each type of node (master/slave) but first of all, we should create a role/user with the replication privilege:

```sql
postgres=# CREATE ROLE replicacion WITH REPLICATION LOGIN;
postgres=# \password replicacion
Enter new password:
Enter it again:
```

Then we must create a directory to archive the wal log files to allow point-in-time recovery

```bash
$sudo mkdir /mnt/pg_wal_archive
$sudo chown postgres:postgres /mnt/pg_wal_archive
```

### Streaming Replication in a master node

Changes in the postgresql.conf file:

```bash
wal_level = replica
wal_buffers = 16MB
archive_mode = always
archive_command = 'rsync -a %p /mnt/pg_wal_archive/%f'
max_wal_senders = 5
wal_keep_segments = 32
max_replication_slots = 5
```

Changes in the pg_hba.conf:

```bash
# Allow replication connections from localhost, by a user with the replication privilege.
#local   replication     all                                peer
host    replication     all             127.0.0.1/32        trust
host    replication     all             ::1/128             trust
host    replication     all             10.17.0.11/32      md5
host    replication     all             10.17.0.16/32      md5
```

### Streaming Replication in a slave/worker node

The only difference with the master config is the parameter *hot_standby*.
Changes in the postgresql.conf file:

```bash
# In every slave
hot_standby = on
################
wal_level = replica
archive_mode = always
archive_command = 'rsync -a %p /mnt/pg_wal_archive/%f'
max_wal_senders = 5
wal_keep_segments = 32
max_replication_slots = 5
```

Changes in the pg_hba.conf:

```bash
# Allow replication connections from localhost, by a user with the replication privilege
#local   replication     all                                peer
host    replication     all         127.0.0.1/32            trust
host    replication     all         ::1/128                 trust
host    replication     all         10.17.0.11/32          md5
host    replication     all         10.17.0.16/32          md5
```

In order to initializate the node the data directory */var/lib/postgresql/11/main* should be empty
Then we must stream the basebackup from the master node:

```bash
# su - postgres
$pg_basebackup -h 10.17.0.3 -D /var/lib/postgresql/11/main/ -P -U replication --wal-method=stream
Password:
23908/23908 kB (100%), 1/1 tablespace
```

Then we must create a recovery file *recovery.conf* in the data directory:

```bash
standby_mode = 'on'
primary_conninfo = 'host=10.17.0.3 port=5432 user=replicacion password=xxxxxxx'
trigger_file = '/tmp/MasterNow'
restore_command = 'rsync -a /mnt/pg_wal_archive/%f "%p"'
```

After we finish with each config, for each slave/worker we have to start postgresql and we should see that replication is working on master.

```bash
mgmt-cesga@dbpostgres1:~$ps ax | grep postgres
 2758 pts/0    S+     0:00 grep --color=auto postgres
28919 ?        S      0:03 /usr/lib/postgresql/11/bin/postgres -D /var/lib/postgresql/11/main -c config_file=/etc/postgresql/11/main/postgresql.conf
28920 ?        Ss     0:00 postgres: 11/main: logger
28922 ?        Ss     0:00 postgres: 11/main: checkpointer
28923 ?        Ss     0:00 postgres: 11/main: background writer
28924 ?        Ss     0:01 postgres: 11/main: walwriter
28925 ?        Ss     0:01 postgres: 11/main: autovacuum launcher
28926 ?        Ss     0:00 postgres: 11/main: archiver
28927 ?        Ss     0:01 postgres: 11/main: stats collector
28928 ?        Ss     0:00 postgres: 11/main: logical replication launcher
28982 ?        Ss     0:00 postgres: 11/main: walsender replication 10.172.0.11(53702) streaming 0/250001E8
28983 ?        Ss     0:00 postgres: 11/main: walsender replication 10.172.0.16(44022) streaming 0/250001E8
```

and slaves:

```bash
mgmt-cesga@dbpostgres2:~$ps ax | grep postgres
28061 ?        S      0:00 /usr/lib/postgresql/11/bin/postgres -D /var/lib/postgresql/11/main -c config_file=/etc/postgresql/11/main/postgresql.conf
28062 ?        Ss     0:00 postgres: 11/main: logger
28063 ?        Ss     0:00 postgres: 11/main: startup   recovering 000000010000000000000025
28068 ?        Ss     0:00 postgres: 11/main: checkpointer
28069 ?        Ss     0:00 postgres: 11/main: background writer
28070 ?        Ss     0:00 postgres: 11/main: archiver
28071 ?        Ss     0:00 postgres: 11/main: stats collector
28072 ?        Ss     0:34 postgres: 11/main: walreceiver   streaming 0/250001E8
```

## Pgpool-II instalation

Pgpool-II installation from apt, simply:

```bash
$sudo apt-get install pgpool2
$sudo apt-get install postgresql-11-pgpool2
```

Pgpool-II instalation from yum:

```bash
$sudo yum install pgpool2
$sudo yum install postgresql-11-pgpool2
```

Pgpool-II don't need a local instance of PostgreSQL.

## Pgpool-II configuration

The main configuration reference is at:

<http://www.pgpool.net/docs/latest/en/html/index.html>

It is recommended to follow the source chapter by chapter to configure Pgpool-II.

The most important parameters for a master-slave streaming replication with load balancing and high availability are:

* *master_slave_mode* = *on*
* *master_slave_sub_mode* = '*stream*'
* *load_balance_mode* = *on*
* *connection_cache* = *on*

### PCP configuration
To encrypt the password, use command pg_md5:

```bash
pg_md5 -p
password:
```

Change the pcp.conf file, in /etc/pgpool2/:

```bash
# USERID:MD5PASSWD
postgres:5c117df0b12d256520aa9bf2e8f9f7fd
```

### PCP without password configuration

Create the .pcpass file in the user's directory. The file will have the following structure, localhost: port: user: password (password in plain text).

```bash
localhost:9898:postgres:xxpassxx
```

Set file permissions 600:

```bash
chmod 600 .pcppass
```

Set variable PCPPASSFILE:

```bash
export PCPPASSFILE=/home/baloo/.pcppass
```

### Failover configuration

#### Slave to master configuration

If the master is down, the first thing to do is change the postgresql.conf file in the slave that will be promoted to master.  
Before:

```bash
hot_stanby = on
```

After:

```bash
#hot_stanby = on
```

Delete the file recovery.conf :

```bash
rm recovery.conf
```

Restart the service:

```bash
systemctl restart postgresql-11
```

#### Configure the slave to connect to the new master

The recovery.conf file is configured on the slave, only the ip is modified.
Before:

```bash
standby_mode          = 'on'
primary_conninfo      = 'host=10.17.3.38 port=5432 user=replication password=xxxxxxx'
trigger_file = '/tmp/MasterNow'
restore_command = 'rsync -a /home/pg_wal_archive/%f "%p"'
```

After:

```bash
standby_mode          = 'on'
primary_conninfo      = 'host=10.17.3.46 port=5432 user=replication password=xxxxxxxx'
trigger_file = '/tmp/MasterNow'
restore_command = 'rsync -a /home/pg_wal_archive/%f "%p"'
```

Restart the service:

```bash
systemctl restart postgresql-11
```

#### Pgpool cluster reconfiguration

To promote the slave to master is done with the following command:

```bash
pcp_promote_node -h localhost -p 9898 -U postgres -w 1
pcp_promote_node -- Command Successful
```

to check the result:

```bash
 psql -p 9999 -h localhost -U postgres -c "show pool_nodes" postgres
 node_id |  hostname  | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication_delay | last_status_change  
---------+------------+------+--------+-----------+---------+------------+-------------------+-------------------+---------------------
 0       | 10.38.3.38 | 5432 | down   | 0.333333  | standby | 76         | false             | 0                 | 2019-05-03 13:38:19
 1       | 10.38.3.46 | 5432 | up     | 0.333333  | primary | 0          | true              | 0                 | 2019-05-03 13:38:12
 2       | 10.38.3.47 | 5432 | up     | 0.333333  | standby | 1          | false             | 0                 | 2019-05-03 11:57:14
(3 filas)
```

## PostgreSQL tips

### Continuous archiving in standby

When continuous WAL archiving is used in a standby, there are two different scenarios: the WAL archive can be shared between the primary and the standby, or the standby can have its own WAL archive. When the standby has its own WAL archive, set *archive_mode* to *always*, and the standby will call the archive command for every WAL segment it receives, whether it's by restoring from the archive or by streaming replication. The shared archive can be handled similarly, but the *archive_command* must test if the file being archived exists already, and if the existing file has identical contents. This requires more care in the *archive_command*, as it must be careful to not overwrite an existing file with different contents, but return success if the exactly same file is archived twice. And all that must be done free of race conditions, if two servers attempt to archive the same file at the same time.

If *archive_mode* is set to *on*, the archiver is not enabled during recovery or standby mode. If the standby server is promoted, it will start archiving after the promotion, but will not archive any WAL it did not generate itself. To get a complete series of WAL files in the archive, you must ensure that all WAL is archived, before it reaches the standby. This is inherently true with file-based log shipping, as the standby can only restore files that are found in the archive, but not if streaming replication is enabled. When a server is not in recovery mode, there is no difference between on and always modes.

### Tablespaces

Tablespaces are needed for two reasons mostly:

* Keep the database running when the disk space is running out on the current partition and there’s no easy way to extend it (no LVM for example)
* Optimize performance and enable more parallel IO, by for example having indexes on fast SSD disks to benfit OLTP workloads

If we're using replication it is not recommended setting up tablespaces though as it has some implications for **replication scenarios**.

### pgpool and load-balancing

First of all, pgpool-II' load balancing is "session base", not "statement base". That means, DB node selection for load balancing is decided at the beginning of session. So all SQL statements are sent to the same DB node until the session ends.

Another point is, whether statement is in an explicit transaction or not. If the statement is in a transaction, it will not be load balanced in the replication mode. In pgpool-II 3.0 or later, SELECT will be load balanced even in a transaction if operated in the master/slave mode.

Note the method to choose DB node is not LRU or some such. Pgpool-II chooses DB node randomly considering the "weight" parameter in pgpool.conf. This means that the chosen DB node is not uniformly distributed among DB nodes in short term. You might want to inspect the effect of load balancing after ~100 queries have been sent.

Also cursor statements are not load balanced in replication mode. i.e.:DECLARE..FETCH are sent to all DB nodes in replication mode. This is because the SELECT might come with FOR UPDATE/FOR SHARE. Note that some applications including psql could use CURSOR for SELECT. For example, from PostgreSQL 8.2, if "\set FETCH_COUNT n" is executed, psql unconditionaly uses a cursor name.

More info at <https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html>

### Logging to a file in pgpool

To check that the load balancing is activated turn *on* these parameters in the '''pgpool.conf''':

* log_statement
* log_per_node_statement
* log_hostname
* log_connections

More info at <http://saule1508.github.io/pgpool-logging/>


## PostgreSQL Extensions

### Monitoring with pg_stat_statements

First to get a good picture of the health state of an instance check the cache hit rate, bloat and indexes. See the health check playbook[9].

In order to activate the pg_stat_statements view to check the query performance of the instance, we have to load a shared library in the **postgresql.conf** file.

```conf
shared_preload_libraries = pg_stat_statements
#default is 5000
pg_stat_statements.max = 10000
#track all statements included the ones called from functions
pg_stat_statements.track = all
```

After restarting the instance we should create the extensión in the database we want to do the monitoring.

```sql
CREATE EXTENSION pg_stat_statements;
```

### Postgis

```bash
sudo apt-get install postgis
```

### TimescaleDB

<https://docs.timescale.com/v1.2/getting-started/installation/ubuntu/installation-apt-ubuntu>

## Info and resources

* [PostgreSQL][1]: PostgreSQL APT repo
* [Replication][2]: Streaming replication with PostgreSQL 10
* [WAL archiving][3]: Continuous archiving in standby progress
* [Hash index][4]: Hash indexes performance
* [Parallel queries][5]: Parallel queries
* [Pgpool2 cache][6]: PGpool-II In Memory Query Cache
* [Pgool2 pool][7]: PGpool-II conection pooling
* [Tablespaces][8]: Tablespaces in PostgreSQL
* [PostgreSQL Health][9]: A Health Check Playbook for Your Postgres Database
* [PostgreSQL statements 1][10]: Info pg_stat_statements
* [PostgreSQL statements 2][11]: Enabling pg_stat_statements

[1]: https://wiki.postgresql.org/wiki/Apt
[2]: https://blog.raveland.org/post/postgresql_sr/
[3]: https://www.postgresql.org/docs/11/warm-standby.html#CONTINUOUS-ARCHIVING-IN-STANDBY
[4]: https://medium.com/@jorsol/postgresql-10-features-hash-indexes-484f319db281
[5]: https://medium.com/@jorsol/postgresql-10-features-parallel-queries-10a92c012d53
[6]: http://www.pgpool.net/docs/latest/en/html/runtime-in-memory-query-cache.html
[7]: http://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html
[8]: https://www.cybertec-postgresql.com/en/postgresql-tablespaces-its-not-so-scary/
[9]: https://dzone.com/articles/a-health-check-playbook-for-your-postgres-database
[10]: https://www.postgresql.org/docs/10/pgstatstatements.html
[11]: https://pganalyze.com/docs/install/01_enabling_pg_stat_statements