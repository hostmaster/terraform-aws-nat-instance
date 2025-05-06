#!/bin/bash -x
set -e -o pipefail

# Check required environment variables
if [ -z "${eni_id:-}" ]; then
    echo "Error: eni_id environment variable is not set"
    exit 1
fi

# attach the ENI
end_time=$((SECONDS + 180))
while [ $SECONDS -lt $end_time ] && ! ip link show dev eth1; do
  aws ec2 attach-network-interface \
    --region "$(/opt/aws/bin/ec2-metadata -z  | sed 's/placement: \(.*\).$/\1/')" \
    --instance-id "$(/opt/aws/bin/ec2-metadata -i | cut -d' ' -f2)" \
    --device-index 1 \
    --network-interface-id "${eni_id}"
    sleep 1
done

# start SNAT
systemctl enable snat
systemctl start snat
