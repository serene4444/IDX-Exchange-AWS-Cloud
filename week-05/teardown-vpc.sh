#!/bin/bash
# Week 05 cleanup: deletes everything tagged Project=week-05, in dependency order.
# The NAT Gateway (~$0.045/hr) and its Elastic IP are the resources that cost money.
set -uo pipefail
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2
F="Name=tag:Project,Values=week-05"
q() { aws "$@" --output text; }

INST=$(q ec2 describe-instances --filters "$F" Name=instance-state-name,Values=pending,running,stopping,stopped --query "Reservations[].Instances[].InstanceId")
if [ -n "$INST" ]; then
  echo "Terminating instances: $INST"
  aws ec2 terminate-instances --instance-ids $INST >/dev/null
  aws ec2 wait instance-terminated --instance-ids $INST
fi

NAT=$(q ec2 describe-nat-gateways --filter "$F" Name=state,Values=pending,available --query "NatGateways[].NatGatewayId")
if [ -n "$NAT" ]; then
  echo "Deleting NAT Gateway: $NAT"
  aws ec2 delete-nat-gateway --nat-gateway-id $NAT >/dev/null
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT
fi

for a in $(q ec2 describe-addresses --filters "$F" --query "Addresses[].AllocationId"); do
  echo "Releasing Elastic IP: $a"; aws ec2 release-address --allocation-id "$a"
done

for VPC in $(q ec2 describe-vpcs --filters "$F" --query "Vpcs[].VpcId"); do
  for sg in $(q ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC --query "SecurityGroups[?GroupName!='default'].GroupId"); do
    aws ec2 revoke-security-group-ingress --group-id "$sg" \
      --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)" >/dev/null 2>&1
  done
  for sg in $(q ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC --query "SecurityGroups[?GroupName!='default'].GroupId"); do
    echo "Deleting SG: $sg"; aws ec2 delete-security-group --group-id "$sg" >/dev/null
  done
  for s in $(q ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query "Subnets[].SubnetId"); do
    echo "Deleting subnet: $s"; aws ec2 delete-subnet --subnet-id "$s"
  done
  for rt in $(q ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC --query "RouteTables[?!(Associations[?Main])].RouteTableId"); do
    echo "Deleting route table: $rt"; aws ec2 delete-route-table --route-table-id "$rt"
  done
  for igw in $(q ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC --query "InternetGateways[].InternetGatewayId"); do
    echo "Deleting IGW: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC"
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
  done
  echo "Deleting VPC: $VPC"; aws ec2 delete-vpc --vpc-id "$VPC"
done

echo
echo "Leftover check (all should be empty):"
echo "  instances: $(q ec2 describe-instances --filters "$F" Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId')"
echo "  NAT:       $(q ec2 describe-nat-gateways --filter "$F" Name=state,Values=pending,available,deleting --query 'NatGateways[].NatGatewayId')"
echo "  EIPs:      $(q ec2 describe-addresses --filters "$F" --query 'Addresses[].PublicIp')"
echo "  VPCs:      $(q ec2 describe-vpcs --filters "$F" --query 'Vpcs[].VpcId')"
