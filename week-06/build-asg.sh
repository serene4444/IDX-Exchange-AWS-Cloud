#!/bin/bash
# Week 06, Lab 6.1: PropertyLite on an Auto Scaling Group behind an Application Load Balancer.
# Rebuilds the Week 5 network (2 public + 2 private subnets, 1 NAT), then:
#   ALB (public subnets, HTTP:80) -> target group (port 8080, /health) -> ASG (private subnets, 2/1/4)
# Region is us-east-2: my org's SCP only allows Ohio.
# Every resource is tagged Project=week-06 so teardown-asg.sh can find it.
set -euo pipefail
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2 MSYS_NO_PATHCONV=1 AWS_PAGER=""
HERE="$(cd "$(dirname "$0")" && pwd)"
LT_FILE="$(cd "$HERE" && pwd -W 2>/dev/null || pwd)/.lt.json"   # Windows-style path for the AWS CLI on Git Bash
TAGS='{Key=Project,Value=week-06}'
tag() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},$TAGS]"; }

AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)

# --- Network (same layout as Week 5) ------------------------------------------
VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "$(tag vpc training-vpc)" \
  --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --vpc-ids "$VPC"
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames
subnet() { aws ec2 create-subnet --vpc-id "$VPC" --cidr-block "$2" --availability-zone "$3" \
  --tag-specifications "$(tag subnet "$1")" --query Subnet.SubnetId --output text; }
PUB1=$(subnet training-subnet-public1-us-east-2a  10.0.0.0/20   us-east-2a)
PUB2=$(subnet training-subnet-public2-us-east-2b  10.0.16.0/20  us-east-2b)
PRIV1=$(subnet training-subnet-private1-us-east-2a 10.0.128.0/20 us-east-2a)
PRIV2=$(subnet training-subnet-private2-us-east-2b 10.0.144.0/20 us-east-2b)
IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(tag internet-gateway training-igw)" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
RT_PUB=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications "$(tag route-table training-rtb-public)" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RT_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
for s in "$PUB1" "$PUB2"; do aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$s" >/dev/null; done
EIP=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(tag elastic-ip training-eip-nat)" \
  --query AllocationId --output text)
NAT=$(aws ec2 create-nat-gateway --subnet-id "$PUB1" --allocation-id "$EIP" \
  --tag-specifications "$(tag natgateway training-nat)" --query NatGateway.NatGatewayId --output text)
echo "VPC $VPC | public $PUB1 $PUB2 | private $PRIV1 $PRIV2 | NAT $NAT (waiting...)"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT"
for pair in "$PRIV1:private1" "$PRIV2:private2"; do
  s=${pair%%:*}; n=${pair#*:}
  rt=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications "$(tag route-table "training-rtb-$n")" \
    --query RouteTable.RouteTableId --output text)
  aws ec2 create-route --route-table-id "$rt" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT" >/dev/null
  aws ec2 associate-route-table --route-table-id "$rt" --subnet-id "$s" >/dev/null
done

# --- Security groups -----------------------------------------------------------
SG_ALB=$(aws ec2 create-security-group --vpc-id "$VPC" --group-name alb-sg \
  --description "HTTP 80 from the internet" --tag-specifications "$(tag security-group alb-sg)" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ALB" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
SG_APP=$(aws ec2 create-security-group --vpc-id "$VPC" --group-name property-api-sg \
  --description "8080 only from the ALB SG" --tag-specifications "$(tag security-group property-api-sg)" \
  --query GroupId --output text)
# Debug Lab 6.3: without this rule (source = the ALB's SG), every target fails health checks.
aws ec2 authorize-security-group-ingress --group-id "$SG_APP" \
  --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,UserIdGroupPairs=[{GroupId=$SG_ALB}]" >/dev/null
echo "SGs alb $SG_ALB (80 from 0.0.0.0/0) | app $SG_APP (8080 from $SG_ALB)"

# --- Instance role: SSM only, so I can run the stress test without SSH or a bastion ---
if ! aws iam get-role --role-name property-api-ec2-role >/dev/null 2>&1; then
  aws iam create-role --role-name property-api-ec2-role --tags Key=Project,Value=week-06 \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name property-api-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name property-api-ec2-profile >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name property-api-ec2-profile --role-name property-api-ec2-role
  sleep 15   # instance profiles take a few seconds to become usable by EC2
fi

# --- Launch template (same AMI + user data as Week 3) ---------------------------
USERDATA=$(base64 -w0 < "$HERE/../week-03/user-data.sh")
cat > "$LT_FILE" <<EOF
{
  "ImageId": "$AMI",
  "InstanceType": "t3.micro",
  "SecurityGroupIds": ["$SG_APP"],
  "IamInstanceProfile": {"Name": "property-api-ec2-profile"},
  "UserData": "$USERDATA",
  "Monitoring": {"Enabled": true},
  "MetadataOptions": {"HttpTokens": "required"},
  "TagSpecifications": [{"ResourceType": "instance", "Tags": [{"Key": "Name", "Value": "property-api-asg"}, {"Key": "Project", "Value": "week-06"}]}]
}
EOF
LT=$(aws ec2 create-launch-template --launch-template-name property-api-template \
  --launch-template-data "file://$LT_FILE" \
  --tag-specifications "$(tag launch-template property-api-template)" \
  --query LaunchTemplate.LaunchTemplateId --output text)
rm -f "$LT_FILE"
echo "Launch template $LT"

# --- Target group, ALB, listener -----------------------------------------------
TG=$(aws elbv2 create-target-group --name property-api-tg --protocol HTTP --port 8080 --vpc-id "$VPC" \
  --target-type instance --health-check-path /health --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 --tags Key=Project,Value=week-06 \
  --query "TargetGroups[0].TargetGroupArn" --output text)
ALB=$(aws elbv2 create-load-balancer --name property-api-alb --type application --scheme internet-facing \
  --subnets "$PUB1" "$PUB2" --security-groups "$SG_ALB" --tags Key=Project,Value=week-06 \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)
aws elbv2 create-listener --load-balancer-arn "$ALB" --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TG" >/dev/null
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB" --query "LoadBalancers[0].DNSName" --output text)

# --- Auto Scaling Group + target tracking policy --------------------------------
aws autoscaling create-auto-scaling-group --auto-scaling-group-name property-api-asg \
  --launch-template "LaunchTemplateId=$LT,Version=\$Latest" \
  --min-size 1 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "$PRIV1,$PRIV2" --target-group-arns "$TG" \
  --health-check-type ELB --health-check-grace-period 120 --default-instance-warmup 60 \
  --tags "Key=Project,Value=week-06,PropagateAtLaunch=false"
aws autoscaling enable-metrics-collection --auto-scaling-group-name property-api-asg --granularity 1Minute
aws autoscaling put-scaling-policy --auto-scaling-group-name property-api-asg --policy-name cpu50 \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":50}' >/dev/null

echo
echo "ALB  http://$ALB_DNS"
echo "Waiting for 2 healthy targets..."
until [ "$(aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)" = "2" ]; do sleep 15; done
aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output text
