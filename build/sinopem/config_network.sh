#!/bin/bash

function get_input() {
    read -p "$1 (default: $3): " VAR
    if [ -z $VAR ]; then
        VAR=$3
    fi
    eval $2=$VAR
}

function answer_yes_or_no() {
    while :
    do
        read -p "$1 (yes/no): " VAR
        if [ "$VAR" = "yes" -o "$VAR" = "no" ]; then
            break
        fi
    done
    eval $2=$VAR
}

function splash_screen() {
    clear
    echo -e "\n            Config network\n"
}

function config_network() {
    while :
    do
        splash_screen

        default_interface=$(ip link show  | grep -v '^\s' | cut -d':' -f2 | sed 's/ //g' | grep -v lo | head -1)
        address=$(ip addr show label $default_interface scope global | awk '$1 == "inet" { print $2,$4}')
        ip=$(echo $address | awk '{print $1 }')
        ip=${ip%%/*}
        broadcast=$(echo $address | awk '{print $2 }')
        netmask=$(route -n |grep 'U[ \t]' | grep -v '^169' | head -n 1 | awk '{print $3}')
        gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
        hostname=`hostname`

        get_input 'Input hostname' HOSTNAME $hostname
        get_input 'Select network card' INTERFACE $default_interface
        get_input 'Input IP address' IPADDR $ip
	    get_input 'Input netmask' NETMASK $netmask
        get_input 'Input gateway' GATEWAY $gateway

        echo -e "\nInput parameters:"
        echo "    Hostname: $HOSTNAME"
        echo "    IP address: $IPADDR"
        echo "    Netmask: $NETMASK"
        echo "    Gateway: $GATEWAY"
        echo ""

        answer_yes_or_no "Is this correct:" ANSWER
        if [ "$ANSWER" = "yes" ]; then
            break
        fi
    done

    sed -i "/^BOOTPROTO=.*/d" /etc/sysconfig/network-scripts/ifcfg-$default_interface
    cat > /etc/sysconfig/network-scripts/ifcfg-$default_interface <<EOF
BOOTPROTO=static
IPADDR=$IPADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
DEVICE="$default_interface" 
ONBOOT=yes
EOF
    cat >> /etc/sysconfig/network <<EOF
DNS1=$GATEWAY
EOF

    echo $HOSTNAME > /etc/hostname
    hostname $HOSTNAME

    systemctl restart network
}

yum install -y net-tools
systemctl disable NetworkManager
systemctl stop NetworkManager
config_network
