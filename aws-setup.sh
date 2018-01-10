#!/bin/sh
#
# Create a VPC, Subnet, and Security Group required by jmeter-ecs

# Create an IPv4 VPC and Subnets Using the AWS CLI
# http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/vpc-subnets-commands-example.html

if [ "$CIDR_BLOCK" == '' ]; then
  # create a CIDR block at 10.74, the 74 being ASCII 'J'
  CIDR_BLOCK=10.74.0.0/16
fi
if [ "$SUBNET_CIDR_BLOCK1" == '' ]; then
  # this CIDR limits us to 251 JMeter Minions - protection from a typo trying to create 1000 instances
  SUBNET_CIDR_BLOCK1=10.74.1.0/24
fi
if [ "$SUBNET_CIDR_BLOCK2" == '' ]; then
  # this CIDR limits us to 251 JMeter Minions - protection from a typo trying to create 1000 instances
  SUBNET_CIDR_BLOCK2=10.74.2.0/24
fi
if [ "$OWNER" == '' ]; then
  OWNER=jmeter-ecs
fi

# keep the tags consistant so we can easily detect if a JMeter VPC already exists
VPC_TAGS="Key=Name,Value=JMeter-VPC Key=Owner,Value=$OWNER Key=Stack,Value=JMeter"

VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Stack,Values=JMeter --query 'Vpcs[*].[VpcId]' --output text | tr -d '\n')
if [ "$VPC_ID" == '' ]; then
  echo "JMeter-VPC does not exist - lets create it"
else
  echo "JMeter-VPC exists: $VPC_ID"
  exit 1
fi

# Step 1: Create a VPC and Subnets
VPC_ID=$(aws ec2 create-vpc --cidr-block $CIDR_BLOCK --query 'Vpc.[VpcId]' --output text | tr -d '\n')
if [ "$VPC_ID" == '' ]; then
  echo "Creating VPC failed - exiting"
  exit 1
fi
echo "Created VPC $VPC_ID"

# enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames --output text

# create a 2 subnets
SUBNET_ID1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR_BLOCK1 \
    --query 'Subnet.[SubnetId]' --output text | tr -d '\n')
SUBNET_ID2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR_BLOCK2 \
    --query 'Subnet.[SubnetId]' --output text | tr -d '\n')
echo "Created Subnets $SUBNET_ID1,$SUBNET_ID2"

# Step 2: Make Your Subnet Public
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.[InternetGatewayId]' --output text | tr -d '\n')
echo "Created Internet Gateway $IGW_ID"

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

RTB_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.[RouteTableId]' --output text | tr -d '\n')
echo "Created Route Table $RTB_ID"

# create a route in the route table that points all traffic (0.0.0.0/0) to the Internet gateway.
CREATE_ROUTE_RESULT=$(aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --output text | tr -d '\n')
if [ "$CREATE_ROUTE_RESULT" == 'True' ]; then
  echo "Created route for all traffic to the Internet Gateway"
fi

# make these public subnet
RTBASSOC_ID1=$(aws ec2 associate-route-table --subnet-id $SUBNET_ID1 --route-table-id $RTB_ID --output text | tr -d '\n')
RTBASSOC_ID2=$(aws ec2 associate-route-table --subnet-id $SUBNET_ID2 --route-table-id $RTB_ID --output text | tr -d '\n')
echo "Created Route Table Associations $RTBASSOC_ID1,$RTBASSOC_ID2"

# we need public IP addresses so instances can register with ECS clusters
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID2 --map-public-ip-on-launch

# create a security group for JMeter
SG_ID=$(aws ec2 create-security-group --group-name "JMeter" --description "JMeter Security Group" --vpc-id $VPC_ID --output text | tr -d '\n')
echo "Created Security Group $SG_ID"

JMETER_IP_PERMISSIONS='[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},{"IpProtocol": "tcp", "FromPort": 1099, "ToPort": 1099, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},{"IpProtocol": "udp", "FromPort": 4445, "ToPort": 4445, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},{"IpProtocol": "tcp", "FromPort": 50000, "ToPort": 50000, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},{"IpProtocol": "tcp", "FromPort": 51000, "ToPort": 51000, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'
aws ec2 authorize-security-group-ingress --group-id $SG_ID --ip-permissions "$JMETER_IP_PERMISSIONS"

# tag all created resources
aws ec2 create-tags --resources $VPC_ID $SUBNET_ID1 $SUBNET_ID2 $IGW_ID $RTB_ID $SG_ID --tags $VPC_TAGS --output text

echo "******** Use these two enviroment variables in 'docker run'"
echo "  --env SUBNET_ID=$SUBNET_ID1,$SUBNET_ID2"
echo "  --env SECURITY_GROUP=$SG_ID"
echo "********"

# ensure we have the Role name 'ecsInstanceRole' created
# In most cases, the Amazon ECS instance role is automatically created for you in the console first-run experience.
ECS_ROLE_ID=$(aws iam get-role --role-name ecsInstanceRole --query 'Role.[RoleId]' --output text | tr -d '\n')
if [ "$ECS_ROLE_ID" == '' ]; then
  echo "You must create the 'ecsInstanceRole' as outlined by this article:"
  echo "http://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html"
fi
