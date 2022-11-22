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
  echo "Please set a SECURITY_GROUP that allows ports 22,1099,50000,51000/tcp and 4445/udp from all ports (e.g. sg-12345678)"
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
if [ "$MEM_LIMIT" == '' ]; then
  MEM_LIMIT=950m
fi
if [ "$MINION_COUNT" == '' ]; then
  MINION_COUNT=2
fi
if [ "$PEM_PATH" == '' ]; then
  PEM_PATH=/keys
fi
if [ "$CLUSTER_NAME" == '' ]; then
  CLUSTER_NAME=JMeter
fi
if [ "$VPC_ID" == '' ]; then
  VPC_ID=$(aws ec2 describe-security-groups --group-ids $SECURITY_GROUP --query 'SecurityGroups[*].[VpcId]' --output text)
fi

# Step 1 - Create our ECS Cluster with MINION_COUNT+1 instances
ecs-cli --version
echo "Detecting existing cluster/$CLUSTER_NAME"
INSTANCE_COUNT=$((MINION_COUNT+1))
CONTAINER_INSTANCE_COUNT=$(aws ecs describe-clusters --cluster $CLUSTER_NAME \
  --query 'clusters[*].[registeredContainerInstancesCount]' --output text)
if [ "$CONTAINER_INSTANCE_COUNT" == $INSTANCE_COUNT ]; then
  echo "Using existing cluster/$CLUSTER_NAME"
else
  if [ "$CONTAINER_INSTANCE_COUNT" != '0' ]; then
    echo "Instance count is $CONTAINER_INSTANCE_COUNT, but requested instance count is $INSTANCE_COUNT"
  fi
  echo "Creating cluster/$CLUSTER_NAME"
  ecs-cli up --cluster $CLUSTER_NAME --size $INSTANCE_COUNT --capability-iam --instance-type $INSTANCE_TYPE --keypair $KEY_NAME \
    --security-group $SECURITY_GROUP --vpc $VPC_ID --subnets $SUBNET_ID --force --verbose
fi

# Step 2 - Wait for the cluster to have all container instances registered
while true; do
  CONTAINER_INSTANCE_COUNT=$(aws ecs describe-clusters --cluster $CLUSTER_NAME \
    --query 'clusters[*].[registeredContainerInstancesCount]' --output text)
  echo "Instance count is $CONTAINER_INSTANCE_COUNT"
  if [ "$CONTAINER_INSTANCE_COUNT" == $INSTANCE_COUNT ]; then
    break
  fi
  sleep 10
done

# Step 3 - Run the Minion task with the requested JMeter version, flags, instance count and memory
sed -i 's/jmeter:latest/jmeter:'"$JMETER_VERSION"'/' /opt/jmeter/lucy.yml
sed -i 's/JMETER_FLAGS=/JMETER_FLAGS='"$JMETER_FLAGS"'/' /opt/jmeter/lucy.yml
sed -i 's/950m/'"$MEM_LIMIT"'/' /opt/jmeter/lucy.yml
sed -i 's/CUSTOM_PLUGIN_URL=/CUSTOM_PLUGIN_URL='"$CUSTOM_PLUGIN_URL"'/' /opt/jmeter/lucy.yml
ecs-cli compose --file /opt/jmeter/lucy.yml up --cluster $CLUSTER_NAME
ecs-cli compose --file /opt/jmeter/lucy.yml --cluster $CLUSTER_NAME scale $MINION_COUNT

# Step 4 - Get Gru and Minion's instance ID's.  Gru is the container with a runningTasksCount = 0
CONTAINER_INSTANCE_IDS=$(aws ecs list-container-instances --cluster $CLUSTER_NAME --output text |
      awk '{print $2}' | tr '\n' ' ')
echo "Container instances IDs: $CONTAINER_INSTANCE_IDS"

GRU_INSTANCE_ID=$(aws ecs describe-container-instances --cluster $CLUSTER_NAME \
  --container-instances $CONTAINER_INSTANCE_IDS --query 'containerInstances[*].[ec2InstanceId,runningTasksCount]' --output text | grep -m 1 '\t0' | awk '{print $1}')
echo "Gru instance ID: $GRU_INSTANCE_ID"

MINION_INSTANCE_IDS=$(aws ecs describe-container-instances --cluster $CLUSTER_NAME \
  --container-instances $CONTAINER_INSTANCE_IDS --query 'containerInstances[*].[ec2InstanceId,runningTasksCount]' --output text | grep '\t1' | awk '{print $1}')
echo "Minion instances IDs: $MINION_INSTANCE_IDS"

# Step 5 - Get IP addresses from Gru (Public or Private) and Minions (always Private)
if [ "$GRU_PRIVATE_IP" == '' ]; then
  GRU_HOST=$(aws ec2 describe-instances --instance-ids $GRU_INSTANCE_ID \
      --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text | tr -d '\n')
else
  echo "Using Gru's Private IP"
  GRU_HOST=$(aws ec2 describe-instances --instance-ids $GRU_INSTANCE_ID \
      --query 'Reservations[*].Instances[*].[PrivateIpAddress]' --output text | tr -d '\n')
fi
echo "Gru at $GRU_HOST"

if [ "$MINION_INSTANCE_IDS" == '' ]; then
  echo "Error - no Minion instance IDs found."
else
  MINION_HOSTS=$(aws ec2 describe-instances --instance-ids $MINION_INSTANCE_IDS \
      --query 'Reservations[*].Instances[*].[PrivateIpAddress]' --output text | tr '\n' ',')

  echo "Minions at $MINION_HOSTS"
  # uncomment if you want to pause Lucy to inspect Gru or a Minion
  #read -p "Press enter to start Gru setup: "

  # Step 6 - Copy all files to Minions/Gru, or just the JMX
  if [ "$COPY_DIR" == '' ]; then
    echo "Copying $INPUT_JMX to Gru"
    scp -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $INPUT_JMX ec2-user@${GRU_HOST}:/tmp
  else
    # Get Gru and Minion public hosts (space delimited) so Lucy can reach them for scp.
    PUBLIC_HOSTS=$(aws ec2 describe-instances --instance-ids $GRU_INSTANCE_ID $MINION_INSTANCE_IDS \
          --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text | tr '\n' ' ')
    JMX_DIR=$(dirname $INPUT_JMX)

    for HOST in $PUBLIC_HOSTS; do
      echo "Copying $INPUT_JMX and test files to $HOST"
      scp -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $JMX_DIR/* ec2-user@${HOST}:/tmp
    done
  fi

  # Step 7 - Run Gru with the specified JMX
  echo "Running Docker to start JMeter in Gru mode"
  JMX_IN_COMTAINER=/plans/$(basename $INPUT_JMX)
  ssh -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ec2-user@${GRU_HOST} \
  "docker run --network host -v /tmp:/plans -v /logs:/logs --env MINION_HOSTS=$MINION_HOSTS \
  --env JMETER_FLAGS=$JMETER_FLAGS --env TIME_LIMIT=$TIME_LIMIT smithmicro/jmeter:$JMETER_VERSION $JMX_IN_COMTAINER"

  # Step 8 - Fetch the results from Gru
  echo "Copying results from Gru"
  scp -r -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ec2-user@${GRU_HOST}:/logs/* /logs
fi

# Step 9 - Delete the cluster
if [ "$RETAIN_CLUSTER" == '' ]; then
  echo "Deleting cluster/$CLUSTER_NAME"
  ecs-cli down --cluster $CLUSTER_NAME --force
else
  echo "cluster/$CLUSTER_NAME is retained upon request."
fi
echo "Complete"
