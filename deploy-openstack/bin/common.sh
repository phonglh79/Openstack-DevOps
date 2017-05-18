#!/bin/bash 

#----------------disable selinux-------------------------
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config #disable selinux in conf file 
setenforce 0  &&
echo $GREEN Disable the selinux by config file. The current selinux Status:$NO_COLOR $YELLOW $(getenforce) $NO_COLOR

function ntp(){
yum install ntp -y  1>/dev/null
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
ntpdate $NTP_SERVER_IP 1>/dev/null
hwclock --systohc
sed -i "/server 0.centos.pool.ntp.org iburst/d" /etc/ntp.conf
sed -i "/server 1.centos.pool.ntp.org iburst/d" /etc/ntp.conf
sed -i "/server 2.centos.pool.ntp.org iburst/d" /etc/ntp.conf
sed -i "/server 3.centos.pool.ntp.org iburst/d" /etc/ntp.conf
sed -i "21 i server $NTP_SERVER_IP iburst " /etc/ntp.conf
systemctl enable ntpd.service 1>/dev/null && 
systemctl start ntpd.service
}

function mysql_configuration(){
echo $BLUE Beginning configuration mysql for controller node on $YELLOW $(hostname) $NO_COLOR
# set the bind-address key to the management IP address of the controller node to enable access by other nodes via the management network
# refer https://docs.openstack.org/newton/install-guide-rdo/environment-sql-database.html
yum install mariadb mariadb-server python2-PyMySQL -y 1>/dev/null 
debug "$1" "$RED Install mariadb mariadb-server python2-PyMySQL failed $NO_COLOR"   
    echo > /etc/my.cnf.d/openstack.cnf
    cat > /etc/my.cnf.d/openstack.cnf <<EOF
[mysqld]
bind-address = $MGMT_IP
default-storage-engine = innodb
innodb_file_per_table
max_connections=4096
collation-server = utf8_general_ci
character-set-server = utf8
init-connect = 'SET NAMES utf8'
EOF
systemctl enable mariadb.service 1>/dev/null 2>&1 && 
systemctl start mariadb.service
#sed -i '/Group=mysql/a\LimitNOFILE=65535' /usr/lib/systemd/system/mariadb.service
#systemctl daemon-reload
systemctl restart mariadb.service

mysql_secure_installation <<EOF

y
$MARIADB_PASSWORD
$MARIADB_PASSWORD
y
y
y
y
EOF
debug "$?" "$RED Mysql configuration failed $NO_COLOR"
echo $GREEN Finished the Mariadb install and configuration on $YELLOW $(hostname) $NO_COLOR 
}

function database_create(){
#create database and user in mariadb for openstack component
#$1 is the database name (comonent name and usename) 
#$2 is password of database

mysql -uroot -p$MARIADB_PASSWORD -e "create database $1 character set utf8;grant all privileges on $1.* to $1@localhost \
identified by '$2';GRANT ALL PRIVILEGES ON $1.* TO 'keystone'@'%'  IDENTIFIED BY '$2';flush privileges;"  
debug "$?" "Create database $1 Failed "
}

function rabbitmq_configuration(){
#RABBIT_P 
#Except Horizone and keystone ,each component need connect to Rabbitmq 
yum install rabbitmq-server  -y 1>/dev/null
debug "$1" "$RED Install rabbitmq-server failed $NO_COLOR"
systemctl enable rabbitmq-server.service 1>/dev/null && 
systemctl start rabbitmq-server.service
debug "$?" "systemctl start rabbitmq-server.service Faild, Did you edit the /etc/hosts ? "
rabbitmqctl add_user openstack $RABBIT_PASS  1>/dev/null
#Permit configuration, write, and read access for the openstack user:
rabbitmqctl set_permissions openstack ".*" ".*" ".*"  1>/dev/null
#rabbitmq-plugins list
#enable rabbitmq_management boot after the os boot 
#Use rabbitmq-web 
rabbitmq-plugins enable rabbitmq_management
systemctl restart rabbitmq-server.service
}

function memcache(){
#install and configuration memecache 
#Need variable MGMT_IP
#The Identity service authentication mechanism for services uses Memcached to cache tokens. 
#The memcached service typically runs on the controller node. 
#For production deployments, we recommend enabling a combination of firewalling, authentication, and encryption to secure it.
yum install memcached python-memcached -y 1>/dev/null
sed -i "s/127.0.0.1/$MGMT_IP/g" /etc/sysconfig/memcached
systemctl enable memcached.service && 1>/dev/null
systemctl start memcached.service
}