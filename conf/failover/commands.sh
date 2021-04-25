# promote a node
sudo -u postgres /usr/lib/postgresql/11/bin/pg_ctl promote -D /var/lib/postgresql/11/main
# Init a node
sudo -u postgres /usr/lib/postgresql/11/bin/postgres -D /var/lib/postgresql/11/main -c config_file=/etc/postgresql/11/main/postgresql.conf
# Stop a node
 sudo -u postgres /usr/lib/postgresql/11/bin/pg_ctl stop -D /var/lib/postgresql/11/main
