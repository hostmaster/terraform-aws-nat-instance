#!/bin/bash
set -x

# wait for eth1
end_time=$((SECONDS + 180))
while [ $SECONDS -lt $end_time ] && ! ip link show dev eth1; do
  sleep 1
done

if ! ip link show dev eth1; then
  exit 1
fi

# enable IP forwarding and NAT
sysctl -q -w net.ipv4.ip_forward=1
sysctl -q -w net.ipv4.conf.eth1.send_redirects=0
sysctl -q -w net.ipv4.conf.eth1.rp_filter=0
sysctl -q -w net.ipv4.conf.all.rp_filter=0

iptables -A PREROUTING -t mangle -i eth1 -j MARK --set-mark 1
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

echo "from all fwmark 1 lookup nat" >> /etc/sysconfig/network-scripts/rule-eth1

echo "100 nat" >>/etc/iproute2/rt_tables
GW=$(ip route show 0.0.0.0/0 dev eth1 | cut -d\  -f3)
ip route add default via $GW dev eth1 table nat
ip rule add fwmark 1 lookup nat
ip route flush cache
# switch the default route to eth1
#ip route del default dev eth0
#ip route

# wait for network connection
#curl --retry 10 --retry-delay 5 --connect-timeout 10 --max-time 60 http://www.example.com
#if [ $? -ne 0 ]; then
#  echo "curl exited with an error"
#fi

# reestablish connections
# systemctl restart amazon-ssm-agent.service
