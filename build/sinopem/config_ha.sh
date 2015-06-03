#!/bin/sh

SOURCE_DIR=`dirname $0`

DATABASE_USER="root"
DATABASE_PASSWORD="password"
DATABASE_REP_USER="rep"
DATABASE_REP_PASSWORD="abc123"

MASTER_IP="192.168.206.151"
SLAVE_IP="192.168.206.152"
VIP="192.168.206.150"

EMAIL="2762942925@qq.com"
MAIL_SERVER="mx3.qq.com"


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


function remote_exec_script() {
    remote_host=$1
    script=$2
    chmod u+x $script
    scp $script root@$remote_host:
    remote_exec $remote_host ~/$script
    remote_exec $remote_host "rm -f $script" 
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


function config_haproxy() {
    cat >> config_haproxy.sh <<EOF
    yum install -y haproxy
    cat >>/etc/haproxy/haproxy.cfg <<HAPROXY_CFG_END
listen sinopem
    bind :80
    mode tcp
    server mon01 $MASTER_IP:8080
    server mon02 $MASTER_IP:8080

HAPROXY_CFG_END
    systemctl restart haproxy
EOF
    sh config_haproxy.sh
    remote_exec_script $SLAVE_IP config_haproxy.sh
    rm -f config_haproxy.sh
}


function pre_config() {
    systemctl stop tomcat
    copy_sshkey_to_slave
}


function post_config() {
    systemctl start tomcat
}


function config_mysql_ha() {
    config_mysql_master
    config_mysql_slave
    sync_db
}


function config_keepalived() {
    interface=$(ip link show  | grep -v '^\s' | cut -d':' -f2 | sed 's/ //g' | grep -v lo | head -1)
   
    # 配置主节点上的keepalived
    cat > config_keepalived.sh <<EOF
    yum install -y keepalived mailx

    cat > /etc/keepalived/keepalived.conf <<KEEYALIVED_CONF_END
global_defs {
    notification_email {
        $EMAIL
    }
    notification_email_from $EMAIL
    smtp_server $MAIL_SERVER
    smtp_connect_timeout 30
    router_id LVS_Master
}        

vrrp_script chk_http_port {
    script  "/etc/keepalived/check_haproxy.sh"
    interval        5   
    weight         -5  
}

vrrp_instance VI_A {
    state MASTER
    interface $interface
    virtual_router_id 50
    priority 100
    advert_int 1
    authentication {  
        auth_type PASS
        auth_pass 1111 
    }  
    track_script {
        chk_http_port
    }
    virtual_ipaddress {
        $VIP
    }
}
KEEYALIVED_CONF_END

    cat > /etc/keepalived/check_haproxy.sh <<CHECK_HAPROXY_END
A=\\\`ps -C haproxy --no-header |wc -l\\\`
if [ \\\$A -eq 0 ]; then
    systemctl start haproxy 
    echo "Start haproxy"& > /dev/null
    sleep 3

    if [ \\\`ps -C haproxy --no-header | wc -l\\\` -eq 0 ]; then
        systemctl stop haproxy
        echo "Stop keepalived"& > /dev/null
    fi
fi
CHECK_HAPROXY_END

    chmod u+x /etc/keepalived/check_haproxy.sh
    systemctl restart keepalived
EOF

    chmod u+x config_keepalived.sh
    ./config_keepalived.sh

    # 配置从节点上的keepalived
    sed -i 's/state MASTER/state BACKUP/' config_keepalived.sh
    sed -i 's/priority 100/priority 50/' config_keepalived.sh
    remote_exec_script $SLAVE_IP config_haproxy.sh
    rm -f config_keepalived.sh    
}

    
#pre_config
#config_mysql_ha
#config_haproxy
config_keepalived
#post_config
