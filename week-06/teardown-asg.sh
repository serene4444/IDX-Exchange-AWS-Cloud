#!/bin/bash
# Week 06 cleanup, in the handbook's order: ASG (terminates its instances) -> ALB -> target group
# -> launch template, then the Week-5-style network tagged Project=week-06, then the IAM role.
set -uo pipefail
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2 AWS_PAGER=""
F="Name=tag:Project,Values=week-06"
q() { aws "$@" --output text; }

if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names property-api-asg \
     --query "AutoScalingGroups[0].AutoScalingGroupName" --output text | grep -q property-api-asg; then
  echo "Deleting ASG property-api-asg (and its instances)..."
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name property-api-asg --force-delete
  while aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names property-api-asg \
          --query "AutoScalingGroups[0].AutoScalingGroupName" --output text | grep -q property-api-asg; do sleep 15; done
fi

ALB=$(q elbv2 describe-load-balancers --names property-api-alb --query "LoadBalancers[0].LoadBalancerArn" 2>/dev/null)
if [ -n "$ALB" ] && [ "$ALB" != "None" ]; then
  echo "Deleting ALB..."; aws elbv2 delete-load-balancer --load-balancer-arn "$ALB"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB"
fi
TG=$(q elbv2 describe-target-groups --names property-api-tg --query "TargetGroups[0].TargetGroupArn" 2>/dev/null)
if [ -n "$TG" ] && [ "$TG" != "None" ]; then echo "Deleting target group..."; aws elbv2 delete-target-group --target-group-arn "$TG"; fi
aws ec2 delete-launch-template --launch-template-name property-api-template >/dev/null 2>&1 && echo "Deleted launch template"

# Any stray instances (ASG delete already terminates them)
INST=$(q ec2 describe-instances --filters "Name=tag:Name,Values=property-api-asg" Name=instance-state-name,Values=pending,running,stopping,stopped --query "Reservations[].Instances[].InstanceId")
if [ -n "$INST" ]; then aws ec2 terminate-instances --instance-ids $INST >/dev/null; aws ec2 wait instance-terminated --instance-ids $INST; fi

NAT=$(q ec2 describe-nat-gateways --filter "$F" Name=state,Values=pending,available --query "NatGateways[].NatGatewayId")
if [ -n "$NAT" ]; then
  echo "Deleting NAT Gateway: $NAT"; aws ec2 delete-nat-gateway --nat-gateway-id $NAT >/dev/null
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT
fi
for a in $(q ec2 describe-addresses --filters "$F" --query "Addresses[].AllocationId"); do
  echo "Releasing Elastic IP: $a"; aws ec2 release-address --allocation-id "$a"
done

for VPC in $(q ec2 describe-vpcs --filters "$F" --query "Vpcs[].VpcId"); do
  # ALB network interfaces can linger for a minute after the ALB is deleted
  while [ -n "$(q ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC --query 'NetworkInterfaces[].NetworkInterfaceId')" ]; do
    echo "Waiting for network interfaces to release..."; sleep 15; done
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

if aws iam get-role --role-name property-api-ec2-role >/dev/null 2>&1; then
  echo "Deleting IAM role property-api-ec2-role"
  aws iam remove-role-from-instance-profile --instance-profile-name property-api-ec2-profile --role-name property-api-ec2-role
  aws iam delete-instance-profile --instance-profile-name property-api-ec2-profile
  aws iam detach-role-policy --role-name property-api-ec2-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam delete-role --role-name property-api-ec2-role
fi

echo
echo "Leftover check (all should be empty):"
echo "  ASG:       $(q autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?AutoScalingGroupName=='property-api-asg'].AutoScalingGroupName")"
echo "  ALB:       $(q elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName=='property-api-alb'].LoadBalancerName")"
echo "  instances: $(q ec2 describe-instances --filters "Name=tag:Name,Values=property-api-asg" Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId')"
echo "  NAT:       $(q ec2 describe-nat-gateways --filter "$F" Name=state,Values=pending,available,deleting --query 'NatGateways[].NatGatewayId')"
echo "  EIPs:      $(q ec2 describe-addresses --filters "$F" --query 'Addresses[].PublicIp')"
echo "  VPCs:      $(q ec2 describe-vpcs --filters "$F" --query 'Vpcs[].VpcId')"
