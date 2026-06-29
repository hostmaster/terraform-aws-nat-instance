#!/bin/bash
set -euxo pipefail

# wait for eth1 link
end_time=$((SECONDS + 180))
while [ $SECONDS -lt $end_time ] && ! ip link show dev eth1 >/dev/null 2>&1; do
  sleep 1
done
ip link show dev eth1 >/dev/null 2>&1 || { echo "eth1 never appeared" >&2; exit 1; }

# wait for eth1 to actually get an IPv4 address (the real race vs. the old script)
end_time=$((SECONDS + 180))
while [ $SECONDS -lt $end_time ] && ! ip -4 -o addr show dev eth1 | grep -q 'inet '; do
  sleep 1
done

ETH1_CIDR=$(ip -4 -o addr show dev eth1 | awk '{print $4; exit}')
[ -n "${ETH1_CIDR:-}" ] || { echo "eth1 has no IPv4 address" >&2; exit 1; }

# AWS VPC router = first host of the subnet (network + 1). ipcalc ships on AL2.
NETWORK=$(ipcalc -n "$ETH1_CIDR" | cut -d= -f2)
GW=$(awk -F. '{print $1"."$2"."$3"."$4+1}' <<<"$NETWORK")
[ -n "$GW" ] || { echo "could not determine eth1 gateway" >&2; exit 1; }

# enable IP forwarding and NAT
sysctl -q -w net.ipv4.ip_forward=1
sysctl -q -w net.ipv4.conf.eth1.send_redirects=0
sysctl -q -w net.ipv4.conf.eth1.rp_filter=0
sysctl -q -w net.ipv4.conf.all.rp_filter=0

# idempotent iptables (-C check before -A so re-runs don't duplicate)
iptables -t mangle -C PREROUTING -i eth1 -j MARK --set-mark 1 2>/dev/null \
  || iptables -t mangle -A PREROUTING -i eth1 -j MARK --set-mark 1
iptables -t nat -C POSTROUTING -o eth1 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# policy-routing table for marked (forwarded) traffic
grep -q '^100[[:space:]]\+nat$' /etc/iproute2/rt_tables || echo "100 nat" >> /etc/iproute2/rt_tables
grep -q 'fwmark 1 lookup nat' /etc/sysconfig/network-scripts/rule-eth1 2>/dev/null \
  || echo "from all fwmark 1 lookup nat" >> /etc/sysconfig/network-scripts/rule-eth1

ip route replace default via "$GW" dev eth1 table nat        # replace = idempotent
ip rule list | grep -q "fwmark 0x1 lookup nat" || ip rule add fwmark 1 lookup nat
ip route flush cache
