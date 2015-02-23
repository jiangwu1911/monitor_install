#!/bin/bash

# 机房监控安装程序

RELEASE_SERVER="http://10.1.1.90/sinoPEM"
RELEASE_VERSION="2.0.1"
OLD_MYSQL_ROOT_PASSWORD=""
NEW_MYSQL_ROOT_PASSWORD="password"
DATABASE_NAME="sinopem"
DATABASE_USER="sinopem"
DATABASE_PASSWORD="sinopem"

dt=`date '+%Y%m%d-%H%M%S'`
logfile="install_$dt.log"


# 配置mysql root口令, 创建sinopem库, 创建sinopem用户
function config_mysql() {
    echo -ne "\n配置MySQL数据库......      "

    mysql_secure_installation >> $logfile 2>&1 <<EOF
$OLD_MYSQL_ROOT_PASSWORD
Y
$NEW_MYSQL_ROOT_PASSWORD
$NEW_MYSQL_ROOT_PASSWORD
Y
Y
Y
EOF

    mysql -u root -p$NEW_MYSQL_ROOT_PASSWORD >> $logfile 2>&1 <<EOF
CREATE DATABASE $DATABASE_NAME;  
GRANT ALL ON $DATABASE_USER.* TO '$DATABASE_NAME'@'%' IDENTIFIED BY '$DATABASE_PASSWORD';  
commit;  
EOF

    systemctl restart mysql
    mysql -u $DATABASE_NAME -p$DATABASE_PASSWORD -D$DATABASE_NAME -e quit >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "错误，请检查提供的数据库密码是否正确。"
        exit -1
    else 
        echo -e "成功。"
    fi
}


# 下载文件
function download_file() {
    url="$1/$2"
    curl -O $url -s
    grep '404 Not Found1' $2
    if [ $? -eq 0 ]; then
        echo -e "错误，无法下载$url"
        exit -1
    fi
}


# 下载并安装应用程序
function install_package() {
    echo -ne "\n下载并安装机房监控程序......      "

    download_file "${RELEASE_SERVER}/${RELEASE_VERSION}" sinopem.sql
    sed -i "/^CREATE DATABASE/d" sinopem.sql
    mysql -u $DATABASE_USER -p$DATABASE_PASSWORD -D$DATABASE_NAME < sinopem.sql >> $logfile 2>&1

    download_file "${RELEASE_SERVER}/${RELEASE_VERSION}" sinoPEM.war
    cp sinoPEM.war /usr/share/tomcat/webapps
    systemctl restart tomcat
    sleep 10		# 等待tomcat解压

    (cd /usr/share/tomcat/webapps/sinoPEM/WEB-INF/classes
     sed -i "s#^jdbc.url=.*#jdbc.url=jdbc\\\:mysql\\\://127.0.0.1/$DATABASE_NAME\?useUnicode\\\=true\&characterEncoding\\\=utf8\&useOldAliasMetadataBehavior\\\=true#" jdbc.properties
     sed -i "s#^jdbc.username=.*#jdbc.username=$DATABASE_USER#" jdbc.properties
     sed -i "s#^jdbc.password=.*#jdbc.password=$DATABASE_PASSWORD#" jdbc.properties
    )
    echo -e "成功。"
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
    echo -ne "\n配置自监控服务......      "

    monit_mysql
    monit_tomcat
    sed -i -s 's#^set daemon.*#set daemon 20#' /etc/monitrc
    systemctl restart monit
    echo -e "成功。"

    localip=`ifconfig | grep -v 127.0.0.1 | grep inet | grep -v inet6 | awk '{print $2}' | sed 's/addr://'`
    echo -e "\n安装完成，请在浏览器中打开http://$localip:8080/sinoPEM, 访问机房监控程序。"
}


# 主程序
config_mysql
install_package
monit_all

localip=`ifconfig | grep -v 127.0.0.1 | grep inet | grep -v inet6 | awk '{print $2}' | sed 's/addr://'`
echo -e "\n安装完成，请在浏览器中打开http://$localip:8080/sinoPEM, 访问机房监控程序。\n"
