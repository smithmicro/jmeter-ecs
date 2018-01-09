#!/bin/sh
#
# jmeter-ecs Orchestrator, aka 'Lucy'

# Leverages the AWS CLI tool and the AWS ECS CLI tool:
# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_AWSCLI.html
# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_CLI.html

# if the command line is not a .jmx file, then it's another command the user wants to call
if [ "${1}" != '' ]; then
  if [ ${1##*.} != 'jmx' ]; then
    exec "$@"
  fi
fi

# check for all required variables
if [ "$1" != '' ]; then
  INPUT_JMX=$1
fi
if [ "$INPUT_JMX" == '' ]; then
  echo "Please set a INPUT_JMX or pass a JMX file on the command line"
  exit 1
fi
if [ "$KEY_NAME" == '' ]; then
  echo "Please specify KEY_NAME and provide the filename (without the path and extension)"
  exit 2
fi
if [ "$SECURITY_GROUP" == '' ]; then
  echo "Please set a SECURITY_GROUP that allows ports 22, 1099, 50000, 51000 (tcp) from all ports (e.g. sg-12345678)"
  exit 3
fi
if [ "$SUBNET_ID" == '' ]; then
  echo "ECS requires using a VPC, so you must specify a SUBNET_ID of yor VPC"
  exit 4
fi

# check all optional variables
if [ "$JMETER_VERSION" == '' ]; then
  JMETER_VERSION=latest
fi
if [ "$AWS_REGION" == '' ]; then
  AWS_REGION=$AWS_DEFAULT_REGION
fi
if [ "$AWS_REGION" == '' ]; then
  AWS_REGION=$(aws configure get region)
fi
if [ "$AWS_ACCESS_KEY_ID" == '' ]; then
  AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
fi
if [ "$AWS_SECRET_ACCESS_KEY" == '' ]; then
  AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
fi
if [ "$INSTANCE_TYPE" == '' ]; then
  INSTANCE_TYPE=t2.micro
fi
if [ "$MINION_COUNT" == '' ]; then
  MINION_COUNT=2
fi
if [ "$PEM_PATH" == '' ]; then
  PEM_PATH=/keys
fi
if [ "$MINION_CLUSTER_NAME" == '' ]; then
  MINION_CLUSTER_NAME=JMeterMinion
fi
if [ "$GRU_CLUSTER_NAME" == '' ]; then
  GRU_CLUSTER_NAME=JMeterGru
fi
if [ "$VPC_ID" == '' ]; then
  VPC_ID=$(aws ec2 describe-security-groups --group-ids $SECURITY_GROUP --query 'SecurityGroups[*].[VpcId]' --output text)
fi

# Step 0 - Detect if Lucy is running in AWS
echo "Detecting an AWS Environment"
PUBLIC_HOSTNAME=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-hostname)
if [ "$PUBLIC_HOSTNAME" = '' ]; then
  echo "Lucy not running in AWS.  Using Gru's Public IP Addresses."
else
  echo "Lucy running in AWS.  Using Gru's Private IP Addresses."
fi

# Step 1 - Create 2 ECS Clusters
ecs-cli --version
echo "Creating cluster/$MINION_CLUSTER_NAME"
ecs-cli up --cluster $MINION_CLUSTER_NAME --size $MINION_COUNT --capability-iam --instance-type $INSTANCE_TYPE --keypair $KEY_NAME \
  --security-group $SECURITY_GROUP --vpc $VPC_ID --subnets $SUBNET_ID --force --verbose
echo "Creating cluster/$GRU_CLUSTER_NAME"
ecs-cli up --cluster $GRU_CLUSTER_NAME --capability-iam --instance-type $INSTANCE_TYPE --keypair $KEY_NAME \
  --security-group $SECURITY_GROUP --vpc $VPC_ID --subnets $SUBNET_ID --force --verbose

# Step 2 - Fetch our Contatiner Instance IDs
while [ "$MINION_CONTAINER_INSTANCE_IDS" = '' ]
do
  MINION_CONTAINER_INSTANCE_IDS=$(aws ecs list-container-instances --cluster $MINION_CLUSTER_NAME --output text |
      awk '{print $2}' | tr '\n' ' ')
  if [ "$MINION_CONTAINER_INSTANCE_IDS" == '' ]; then
    echo "Waiting for Minion container instances IDs.."
    sleep 5
  fi
done
echo "Minion container instances IDs: $MINION_CONTAINER_INSTANCE_IDS"
MINION_INSTANCE_IDS=$(aws ecs describe-container-instances --cluster $MINION_CLUSTER_NAME \
    --container-instances $MINION_CONTAINER_INSTANCE_IDS --query 'containerInstances[*].[ec2InstanceId]' --output text)
echo "Minion instances IDs: $MINION_INSTANCE_IDS"

while [ "$GRU_CONTAINER_INSTANCE_ID" = '' ]
do
  GRU_CONTAINER_INSTANCE_ID=$(aws ecs list-container-instances --cluster $GRU_CLUSTER_NAME --output text |
      awk '{print $2}' | tr '\n' ' ')
  if [ "$GRU_CONTAINER_INSTANCE_ID" == '' ]; then
    echo "Waiting for Gru container instances ID.."
    sleep 5
  fi
done
echo "Gru container instances ID: $GRU_CONTAINER_INSTANCE_ID"
GRU_INSTANCE_ID=$(aws ecs describe-container-instances --cluster $GRU_CLUSTER_NAME \
    --container-instances $GRU_CONTAINER_INSTANCE_ID --query 'containerInstances[*].[ec2InstanceId]' --output text)
echo "Gru instances ID: $GRU_INSTANCE_ID"

# Step 3 - Run the Minion task with the requested count
ecs-cli compose --file /opt/jmeter/lucy.yml up --cluster $MINION_CLUSTER_NAME
ecs-cli compose --file /opt/jmeter/lucy.yml --cluster $MINION_CLUSTER_NAME scale $MINION_COUNT

# Step 4 - Get IP addresses from Gru (Public or Private) and Minions (always Private)
if [ "$PUBLIC_HOSTNAME" = '' ]; then
  GRU_HOST=$(aws ec2 describe-instances --instance-ids $GRU_INSTANCE_ID \
      --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text | tr -d '\n')
else
  GRU_HOST=$(aws ec2 describe-instances --instance-ids $GRU_INSTANCE_ID \
      --query 'Reservations[*].Instances[*].[PrivateIpAddress]' --output text | tr -d '\n')
fi
echo "Gru at $GRU_HOST"

MINION_HOSTS=$(aws ec2 describe-instances --instance-ids $MINION_INSTANCE_IDS \
      --query 'Reservations[*].Instances[*].[PrivateIpAddress]' --output text | tr '\n' ',')
echo "Minions at $MINION_HOSTS"
# uncomment if you want to pause Lucy to inspect Gru or a Minion
#read -p "Press enter to start Gru setup: "

# Step 5 - Run Gru with the specified JMX
echo "Copying $INPUT_JMX to Gru"
scp -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $INPUT_JMX ec2-user@${GRU_HOST}:/tmp

echo "Running Docker to start JMeter in Gru mode"
JMX_IN_COMTAINER=/plans/$(basename $INPUT_JMX)
ssh -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ec2-user@${GRU_HOST} \
 "docker run -p 1099:1099 -p 51000:51000 -v /tmp:/plans -v /logs:/logs --env MINION_HOSTS=$MINION_HOSTS smithmicro/jmeter:$JMETER_VERSION $JMX_IN_COMTAINER"

# Step 6 - Fetch the results
echo "Copying results from Gru"
scp -r -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ec2-user@${GRU_HOST}:/logs/* /logs

# Step 7 - Delete the clusters
echo "Deleting cluster/$MINION_CLUSTER_NAME"
ecs-cli down --cluster $MINION_CLUSTER_NAME --force
echo "Deleting cluster/$GRU_CLUSTER_NAME"
ecs-cli down --cluster $GRU_CLUSTER_NAME --force

echo "Complete"
