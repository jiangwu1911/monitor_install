#!/bin/s

SOURCE_DIR=`dirname $0`
DATABASE_USER="root"
DATABASE_PASSWORD="password"
MASTER_IP="192.168.206.151"
SLAVE_IP="192.168.206.152"

DATABASE_REP_USER="rep"
DATABASE_REP_PASSWORD="abc123"


function copy_sshkey_to_slave() {
    if [ ! -e /root/.ssh/id_rsa.pub ]; then
        ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""
    fi
    ssh-copy-id -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no root@$SLAVE_IP
}


function remote_exec() {
    remote_host=$1
    shift
    cmd=$@
    ssh -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no $remote_host $cmd
}


function config_mysql_master() {
    crudini --set /etc/my.cnf mysqld server-id 1
    crudini --set /etc/my.cnf mysqld log-bin /var/lib/mysql/mysql-bin
    crudini --set /etc/my.cnf mysqld binlog-ignore "mysql 
binlog-ignore = information_schema
binlog-ignore = performance_schema"
    crudini --set /etc/my.cnf mysqld binlog-do-db sinopem
    systemctl restart mysqld

    echo "grant replication slave on *.* to '$DATABASE_REP_USER'@'$SLAVE_IP' identified by '$DATABASE_REP_PASSWORD'" \
        | mysql -u $DATABASE_USER -p$DATABASE_PASSWORD
}


function config_mysql_slave() {
    remote_exec $SLAVE_IP "crudini --set /etc/my.cnf mysqld server-id 2"
    remote_exec $SLAVE_IP "systemctl restart mysqld"
}


function sync_db() {
    mysqldump -u $DATABASE_USER -p$DATABASE_PASSWORD sinopem > sinopem.sql
    dbinfo=`echo "show master status" | mysql -u $DATABASE_USER -p$DATABASE_PASSWORD 2>/dev/null | tail -1`
    file=`echo $dbinfo | awk '{print $1}'`
    pos=`echo $dbinfo | awk '{print $2}'`
    
    scp sinopem.sql root@$SLAVE_IP:
    cat > start_slave.sql <<EOF
DROP DATABASE sinopem;
CREATE DATABASE sinopem;
USE sinopem;
source ~/sinopem.sql;
stop slave;
change master to master_host='$MASTER_IP', master_user='rep', master_password='abc123', master_log_file='$file', master_log_pos=$pos;
start slave;
EOF
    scp start_slave.sql root@$SLAVE_IP:
    remote_exec $SLAVE_IP "cat ~/start_slave.sql | mysql -u $DATABASE_USER -p$DATABASE_PASSWORD"

    remote_exec $SLAVE_IP "rm -f sinopem.sql"
    remote_exec $SLAVE_IP "rm -f start_slave.sql"
}    
    
    
#copy_sshkey_to_slave
#config_mysql_master
#config_mysql_slave
sync_db
