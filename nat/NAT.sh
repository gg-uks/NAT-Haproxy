#!/bin/bash
set -e
echo '출발지(NAT)  주소 : '
read src
echo '목적지(HAproxy)  주소 :'
read drc
echo '허용할 포트 번호 :'
read port
 
iptables -t nat -A PREROUTING -d $src -p tcp --dport $port -j DNAT --to-destination $drc:$port
iptables -I FORWARD 1 -p tcp -d $drc --dport $port -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -I FORWARD 1 -p tcp -s $drc -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o enp0s8 -d $drc -p tcp --dport $port -j MASQUERADE
iptables -t nat -L -n -v --line-numbers
iptables -L FORWARD -n -v --line-numbers
