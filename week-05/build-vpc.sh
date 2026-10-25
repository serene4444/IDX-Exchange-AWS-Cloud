#!/bin/bash
# Week 05, Labs 5.1 + 5.2: the "VPC and more" wizard layout, built step by step
# with the AWS CLI, plus a bastion host and a private instance.
# Region is us-east-2: my org's SCP only allows Ohio.
# Every resource is tagged Project=week-05 so teardown-vpc.sh can find it.
set -euo pipefail
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2 MSYS_NO_PATHCONV=1
TAGS='{Key=Project,Value=week-05}'
tag() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},$TAGS]"; }

MY_IP=$(curl -s https://checkip.amazonaws.com)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)

# --- Lab 5.1: VPC ------------------------------------------------------------
VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "$(tag vpc training-vpc)" \
  --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --vpc-ids "$VPC"
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames
echo "VPC            $VPC"

subnet() { # name cidr az
  aws ec2 create-subnet --vpc-id "$VPC" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "$(tag subnet "$1")" --query Subnet.SubnetId --output text
}
PUB1=$(subnet training-subnet-public1-us-east-2a  10.0.0.0/20   us-east-2a)
PUB2=$(subnet training-subnet-public2-us-east-2b  10.0.16.0/20  us-east-2b)
PRIV1=$(subnet training-subnet-private1-us-east-2a 10.0.128.0/20 us-east-2a)
PRIV2=$(subnet training-subnet-private2-us-east-2b 10.0.144.0/20 us-east-2b)
for s in "$PUB1" "$PUB2"; do aws ec2 modify-subnet-attribute --subnet-id "$s" --map-public-ip-on-launch; done
echo "Subnets        public $PUB1 $PUB2 | private $PRIV1 $PRIV2"

# Internet Gateway + public route table (0.0.0.0/0 -> IGW)
IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(tag internet-gateway training-igw)" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
RT_PUB=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications "$(tag route-table training-rtb-public)" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RT_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
for s in "$PUB1" "$PUB2"; do aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$s" >/dev/null; done
echo "IGW            $IGW  (public route table $RT_PUB)"

# NAT Gateway "In 1 AZ": lives in a PUBLIC subnet, needs an Elastic IP
EIP=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(tag elastic-ip training-eip-nat)" \
  --query AllocationId --output text)
NAT=$(aws ec2 create-nat-gateway --subnet-id "$PUB1" --allocation-id "$EIP" \
  --tag-specifications "$(tag natgateway training-nat-public1-us-east-2a)" \
  --query NatGateway.NatGatewayId --output text)
echo "NAT Gateway    $NAT  (waiting until available...)"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT"

# One private route table per private subnet (0.0.0.0/0 -> NAT), explicitly associated
for pair in "$PRIV1:private1-us-east-2a" "$PRIV2:private2-us-east-2b"; do
  s=${pair%%:*}; n=${pair#*:}
  rt=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications "$(tag route-table "training-rtb-$n")" \
    --query RouteTable.RouteTableId --output text)
  aws ec2 create-route --route-table-id "$rt" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT" >/dev/null
  aws ec2 associate-route-table --route-table-id "$rt" --subnet-id "$s" >/dev/null
  echo "Private RT     $rt -> $s"
done

# --- Lab 5.2: bastion pattern ------------------------------------------------
SG_BASTION=$(aws ec2 create-security-group --vpc-id "$VPC" --group-name bastion-sg \
  --description "SSH from my IP only" --tag-specifications "$(tag security-group bastion-sg)" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_BASTION" --protocol tcp --port 22 --cidr "$MY_IP/32" >/dev/null

SG_PRIVATE=$(aws ec2 create-security-group --vpc-id "$VPC" --group-name private-sg \
  --description "SSH only from the bastion SG" --tag-specifications "$(tag security-group private-sg)" \
  --query GroupId --output text)
# Source is the bastion's SECURITY GROUP, not an IP
aws ec2 authorize-security-group-ingress --group-id "$SG_PRIVATE" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$SG_BASTION}]" >/dev/null
echo "SGs            bastion $SG_BASTION (22 from $MY_IP/32) | private $SG_PRIVATE (22 from $SG_BASTION)"

launch() { # name subnet sg
  aws ec2 run-instances --image-id "$AMI" --instance-type t3.micro --key-name training-key \
    --subnet-id "$2" --security-group-ids "$3" \
    --metadata-options HttpTokens=required \
    --tag-specifications "$(tag instance "$1")" --query "Instances[0].InstanceId" --output text
}
BASTION=$(launch training-bastion "$PUB1" "$SG_BASTION")
PRIVATE=$(launch training-private "$PRIV1" "$SG_PRIVATE")
aws ec2 wait instance-running --instance-ids "$BASTION" "$PRIVATE"

BASTION_IP=$(aws ec2 describe-instances --instance-ids "$BASTION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
PRIVATE_IP=$(aws ec2 describe-instances --instance-ids "$PRIVATE" --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
NAT_IP=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT" --query "NatGateways[0].NatGatewayAddresses[0].PublicIp" --output text)

echo
echo "Bastion        $BASTION  public $BASTION_IP"
echo "Private        $PRIVATE  private $PRIVATE_IP (no public IP)"
echo "NAT public IP  $NAT_IP"
