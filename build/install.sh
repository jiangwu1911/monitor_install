#!/bin/bash

# 机房监控安装程序

RELEASE_SERVER="http://10.1.1.90/sinoPEM"
RELEASE_VERSION="2.0.1"
OLD_MYSQL_ROOT_PASSWORD=""
NEW_MYSQL_ROOT_PASSWORD="password"
DATABASE_NAME="sinopem"
DATABASE_USER="sinopem"
DATABASE_PASSWORD="sinopem"


# 配置mysql root口令, 创建sinopem库, 创建sinopem用户
function config_mysql() {
    mysql_secure_installation <<EOF
$OLD_MYSQL_ROOT_PASSWORD
Y
$NEW_MYSQL_ROOT_PASSWORD
$NEW_MYSQL_ROOT_PASSWORD
Y
Y
Y
EOF
    mysql -u root -p$NEW_MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE $DATABASE_NAME;  
GRANT ALL ON $DATABASE_USER.* TO '$DATABASE_NAME'@'%' IDENTIFIED BY '$DATABASE_PASSWORD';  
commit;  
EOF
    systemctl restart mysql
}


# 下载并安装应用程序
function install_package() {
    curl -O "${RELEASE_SERVER}/${RELEASE_VERSION}/sinotj.sql" -s
    sed -i "/^CREATE DATABASE/d" sinotj.sql
    mysql -u $DATABASE_USER -p$DATABASE_PASSWORD -D$DATABASE_NAME < sinotj.sql

    curl -O "${RELEASE_SERVER}/${RELEASE_VERSION}/sinoPEM.war" -s
    cp sinoPEM.war /usr/share/tomcat/webapps
    sleep 10		# 等待tomcat解压

    (cd /usr/share/tomcat/webapps/sinoPEM/WEB-INF/classes
     sed -i "s#^jdbc.url=.*#jdbc.url=jdbc\\\:mysql\\\://127.0.0.1/$DATABASE_NAME\?useUnicode\\\=true\&characterEncoding\\\=utf8\&useOldAliasMetadataBehavior\\\=true#" jdbc.properties
     sed -i "s#^jdbc.username=.*#jdbc.username=$DATABASE_USER#" jdbc.properties
     sed -i "s#^jdbc.password=.*#jdbc.password=$DATABASE_PASSWORD#" jdbc.properties
    )
}


# 用monit监控mysql
function monit_mysql() {
    systemctl stop mysql
    cat > /etc/monit.d/mysql <<EOF
check process mysql with pidfile /run/mysqld/mysqld.pid
    start = "/usr/bin/systemctl start mysqld" with timeout 10 seconds
    stop = "/usr/bin/systemctl stop mysqld"
    if failed port 3306 protocol mysql with timeout 30 seconds
        then restart
    group monitor
EOF
}


# 用monit监控tomcat 
function monit_tomcat() {
    systemctl stop tomcat
    cat > /etc/monit.d/tomcat <<EOF
check process tomcat with pidfile /run/tomcat.pid
    start = "/usr/bin/systemctl start tomcat" with timeout 30 seconds
    stop = "/usr/bin/systemctl stop tomcat"
    if failed url http://localhost:8080/sinoPEM with timeout 30 seconds
        then restart
    group monitor
EOF
}


function monit_all() {
    monit_mysql
    monit_tomcat
    sed -i -s 's#^set daemon.*#set daemon 20#' /etc/monitrc
    systemctl restart monit
}


# 主程序
config_mysql
install_package
monit_all
