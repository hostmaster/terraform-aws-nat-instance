#!/bin/bash -ex

REGION="$(/opt/aws/bin/ec2-metadata -z | sed 's/placement: \(.*\).$/\1/')"
INSTANCE_ID="$(/opt/aws/bin/ec2-metadata -i | cut -d' ' -f2)"

# attach the ENI (attach once, then wait for the link to appear)
if ! ip link show dev eth1 >/dev/null 2>&1; then
  aws ec2 attach-network-interface \
    --region "$REGION" \
    --instance-id "$INSTANCE_ID" \
    --device-index 1 \
    --network-interface-id "${eni_id}"
fi

end_time=$((SECONDS + 180))
while [ $SECONDS -lt $end_time ] && ! ip link show dev eth1 >/dev/null 2>&1; do
  sleep 2
done
ip link show dev eth1 >/dev/null 2>&1 || { echo "eth1 never appeared after attach" >&2; exit 1; }

# start SNAT
systemctl enable snat
systemctl start snat
