#!/bin/sh
#
# jmeter-ecs Orchestrator, aka 'Lucy'

# Leverages the AWS ECS CLI tool:
# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_AWSCLI.html

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
if [ "$AWS_DEFAULT_REGION" == '' ]; then
  AWS_DEFAULT_REGION=$(aws configure get region)
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
if [ "$OWNER" == '' ]; then
  OWNER=jmeter-ecs
fi
if [ "$MINION_CLUSTER_NAME" == '' ]; then
  MINION_CLUSTER_NAME=JMeter
fi
if [ "$GRU_CLUSTER_NAME" == '' ]; then
  GRU_CLUSTER_NAME=JMeterGru
fi
if [ "$MINION_TASK_DEFINITION" == '' ]; then
  MINION_TASK_DEFINITION=Minion
fi
if [ "$MINION_TAGS" == '' ]; then
  MINION_TAGS=ResourceType=instance,Tags=[{Key=Name,Value=Minion},{Key=Owner,Value=$OWNER},{Key=Stack,Value=JMeter}]
fi
if [ "$GRU_TAGS" == '' ]; then
  GRU_TAGS=ResourceType=instance,Tags=[{Key=Name,Value=Gru},{Key=Owner,Value=$OWNER},{Key=Stack,Value=JMeter}]
fi

# derive IMAGE_ID from AWS_DEFAULT_REGION
# see: http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI_launch_latest.html
case "$AWS_DEFAULT_REGION" in
    us-east-1)
        IMAGE_ID=ami-275ffe31 ;;
    us-east-2)
        IMAGE_ID=ami-62745007 ;;
    us-west-1)
        IMAGE_ID=ami-689bc208 ;;
    us-west-2)
        IMAGE_ID=ami-62d35c02 ;;
    eu-west-1)
        IMAGE_ID=ami-95f8d2f3 ;;
    eu-west-2)
        IMAGE_ID=ami-bf9481db ;;
    eu-central-1)
        IMAGE_ID=ami-085e8a67 ;;
    ap-northeast-1)
        IMAGE_ID=ami-f63f6f91 ;;
    ap-southeast-1)
        IMAGE_ID=ami-b4ae1dd7 ;;
    ap-southeast-2)
        IMAGE_ID=ami-fbe9eb98 ;;
    ca-central-1)
        IMAGE_ID=ami-ee58e58a ;;
    *)
        echo "AWS_DEFAULT_REGION must be set to a valid AWS ECS region"
        exit 5
esac

echo "Using image $IMAGE_ID for $AWS_DEFAULT_REGION"

# Step 1 - Create an ECS Cluster
echo "Creating cluster/$MINION_CLUSTER_NAME"
aws ecs create-cluster --cluster-name $MINION_CLUSTER_NAME --query 'cluster.[clusterArn]' --output text

# create a setup script to configure our Cluster name that we pass to --user-data
MINION_CLUSTER_SCRIPT=$'#!/bin/bash\necho ECS_CLUSTER='
MINION_CLUSTER_SCRIPT="${MINION_CLUSTER_SCRIPT}$MINION_CLUSTER_NAME >> /etc/ecs/ecs.config"
MINION_CLUSTER_BASE64=$(echo "$MINION_CLUSTER_SCRIPT" | base64 | tr -d '\n')

# Step 2 - Create all instances and register them with the Cluster
echo "Creating $MINION_COUNT Minion instances and register them to cluster/$MINION_CLUSTER_NAME"
MINION_INSTANCE_IDS=$(aws ec2 run-instances --image-id $IMAGE_ID --count $MINION_COUNT --instance-type $INSTANCE_TYPE \
    --iam-instance-profile Name="ecsInstanceRole" --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP --subnet-id $SUBNET_ID --user-data $MINION_CLUSTER_BASE64 \
    --tag-specifications "$MINION_TAGS" \
    --query 'Instances[*].[InstanceId]' --output text |
      tr '\n' ' ')
if [ "$MINION_INSTANCE_IDS" == '' ]; then
  echo "Creating Minions failed"
  echo "Deleting cluster/$MINION_CLUSTER_NAME"
  aws ecs delete-cluster --cluster $MINION_CLUSTER_NAME --query 'cluster.[clusterArn]' --output text
  exit 6
fi
echo "Minion instances started: $MINION_INSTANCE_IDS"

# create a setup script to configure our Gru Cluster name that we pass to --user-data
GRU_CLUSTER_SCRIPT=$'#!/bin/bash\necho ECS_CLUSTER='
GRU_CLUSTER_SCRIPT="${GRU_CLUSTER_SCRIPT}$GRU_CLUSTER_NAME >> /etc/ecs/ecs.config"
GRU_CLUSTER_BASE64=$(echo "$GRU_CLUSTER_SCRIPT" | base64 | tr -d '\n')

echo "Creating Gru instance"
GRU_INSTANCE_ID=$(aws ec2 run-instances --image-id $IMAGE_ID --count 1 --instance-type $INSTANCE_TYPE \
    --iam-instance-profile Name="ecsInstanceRole" --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP --subnet-id $SUBNET_ID --user-data $GRU_CLUSTER_BASE64  \
    --tag-specifications "$GRU_TAGS" \
    --query 'Instances[*].[InstanceId]' --output text |
      tr '\n' ' ')
if [ "$GRU_INSTANCE_ID" == '' ]; then
  echo "Creating Gru failed - terminating Minion instances"
  aws ec2 terminate-instances --instance-ids $MINION_INSTANCE_IDS \
    --query 'TerminatingInstances[*].[InstanceId]' --output text

  echo "Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids $MINION_INSTANCE_IDS --output text

  echo "Deleting cluster/$MINION_CLUSTER_NAME"
  aws ecs delete-cluster --cluster $MINION_CLUSTER_NAME --query 'cluster.[clusterArn]' --output text
  exit 7
fi
echo "Gru instance started: $GRU_INSTANCE_ID"

# Step 3 - Create the Minion ECS task

# load the requested Docker image using jmeter:JMETER_VERSION with name MINION_TASK_DEFINITION
sed -i 's/JMeterMinion/'"$MINION_TASK_DEFINITION"'/' /opt/jmeter/minion.json
sed -i 's*smithmicro/jmeter:latest*smithmicro/jmeter:'"$JMETER_VERSION"'*' /opt/jmeter/minion.json

echo "Register Minion task definition"
MINION_TASK_ARN=$(aws ecs register-task-definition --cli-input-json file:///opt/jmeter/minion.json --query 'taskDefinition.taskDefinitionArn' --output text | tr -d '\n')
echo "Minion task registered: $MINION_TASK_ARN"

# Step 4 - Wait until the instances are running and registered with the Cluster
echo "Waiting for instances to run..."
aws ec2 wait instance-running --instance-ids $MINION_INSTANCE_IDS $GRU_INSTANCE_ID --output text
echo "All instances running - return code $?"

while true; do
  CONTAINER_INSTANCE_COUNT=$(aws ecs list-container-instances --cluster $MINION_CLUSTER_NAME --output text | grep -c container-instance)
  if [[ $CONTAINER_INSTANCE_COUNT == $MINION_COUNT ]]; then
    echo "Container instances started: $CONTAINER_INSTANCE_COUNT"
    break
  fi
  echo "Waiting 15 seconds for Container instances to register..."
  sleep 15
done

# Step 5 - Fetch our Contatiner Instance IDs
CONTAINER_INSTANCE_IDS=$(aws ecs list-container-instances --cluster $MINION_CLUSTER_NAME --output text |
    awk '{print $2}' | tr '\n' ' ')
echo "Container instances IDs: $CONTAINER_INSTANCE_IDS"

# Step 6 - Run the Minion task with the requested count
echo "Running task: $MINION_TASK_DEFINITION, instance count: $MINION_COUNT"
MINION_TASK_IDS=$(aws ecs run-task --cluster $MINION_CLUSTER_NAME --task-definition $MINION_TASK_DEFINITION --count $MINION_COUNT \
  --query 'tasks[*].[taskArn]' --output text | tr '\n' ' ')

echo "Waiting for tasks to run: $MINION_TASK_IDS"
aws ecs wait tasks-running --cluster $MINION_CLUSTER_NAME --tasks $MINION_TASK_IDS
if [ "$?" = '0' ]; then
  echo "Minion tasks running"
else
  echo "Minion tasks failed to run - return code $?"
fi

# Step 7 - Get public IP addresses from Gru and Minions
GRU_HOST=$(aws ec2 describe-instances --instance-ids $GRU_INSTANCE_ID \
      --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text | tr -d '\n')
echo "Gru at $GRU_HOST"

MINION_HOSTS=$(aws ec2 describe-instances --instance-ids $MINION_INSTANCE_IDS \
      --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text | tr '\n' ',')
echo "Minions at at $MINION_HOSTS"

# uncomment if you want to pause Lucy to inspect Gru or a Minion
#read -p "Press enter to start Gru setup: "

# Step 8 - Run Gru with the specified JMX
echo "Copying $INPUT_JMX to Gru"
scp -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $INPUT_JMX ec2-user@${GRU_HOST}:/tmp

echo "Running Docker to start JMeter in Gru mode"
JMX_IN_COMTAINER=/plans/$(basename $INPUT_JMX)
ssh -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ec2-user@${GRU_HOST} \
 "docker run -p 1099:1099 -p 51000:51000 -v /tmp:/plans -v /logs:/logs --env MINION_HOSTS=$MINION_HOSTS smithmicro/jmeter:$JMETER_VERSION $JMX_IN_COMTAINER"

echo "Copying JTL files from Gru"
scp -i $PEM_PATH/$KEY_NAME.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ec2-user@${GRU_HOST}:/logs/* /logs

# Step 9 - Stop all tesks
echo "Stopping tasks"
aws ecs list-tasks --cluster $MINION_CLUSTER_NAME --output text |
  awk '{print $2}' |
  while read line; do
    aws ecs stop-task --cluster $MINION_CLUSTER_NAME --task $line --query 'task.[taskArn]' --output text;
  done

# Step 10 - Terminate all instances
echo "Terminating instances: $MINION_INSTANCE_IDS $GRU_INSTANCE_ID"
aws ec2 terminate-instances --instance-ids $MINION_INSTANCE_IDS $GRU_INSTANCE_ID \
  --query 'TerminatingInstances[*].[InstanceId]' --output text

echo "Waiting for instances to terminate..."
aws ec2 wait instance-terminated --instance-ids $MINION_INSTANCE_IDS $GRU_INSTANCE_ID --output text

# Step 11 - Final cleanup
echo "Deregister task $MINION_TASK_ARN"
aws ecs deregister-task-definition --task-definition $MINION_TASK_ARN --query 'taskDefinition.[taskDefinitionArn]' --output text

echo "Deleting cluster/$MINION_CLUSTER_NAME"
aws ecs delete-cluster --cluster $MINION_CLUSTER_NAME --query 'cluster.[clusterArn]' --output text

echo "Complete"
