#!/bin/sh

yum upgrade -y

yum install -y tomcat
yum install -y mysql-server
yum install -y mysql
yum install -y puppet
yum install -y monit
