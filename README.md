# JMeter for ECS
JMeter Image for Distributed Testing on EC2 Container Service (ECS)

For more information on JMeter Distributed Testing, see:
* http://jmeter.apache.org/usermanual/remote-test.html

_Warning: Using this Docker image will incur compute and storate costs in AWS.  Care is taken to terminate all instances and volumes after JMeter tests complete, but bugs could allow these resources to continue to run.  See the issues list for more detail._

## How to Use
The Docker image can be run as-is with a number of required environement variables.

Prerequisites to use this image:
* Create a VPC with at least one subnet as ECS requires the use of VPC **
* Create a VPC security group that allows ports 22, 1099, 50000 and 51000 (tcp) to the VPC **
* Create a security key pair and place in the `keys` subdirectory
* Have your AWS CLI Access Key ID/Secret Access Key handy
* Replace or edit the included `plans/demo.jmx` to run your specific tests
* A Role named `ecsInstanceRole` created as per:
  * http://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html

** If you do not have a VPC created, you can use the included `aws-setup.sh` script to create the VPC, Subnet and required Security Group.

Docker run template:
```
docker run -v <oath to jmx>:/plans -v <path to pem>:/keys -v <path to logs>:/logs \
    --env AWS_ACCESS_KEY_ID=<key id> \
    --env AWS_SECRET_ACCESS_KEY=<access key> \
    --env AWS_DEFAULT_REGION=<region> \
    --env SECURITY_GROUP=<security group within your VPC> \
    --env SUBNET_ID=<subnet ID within your VPC> \
    --env KEY_NAME=<key pair name without extension> \
    --env MINION_COUNT=<number of minions> \
    --enc INSTANCE_TYPE=<valid ECS instance type> \
    smithmicro/jmeter-ecs /plans/demo.jmx
```
For 5 test instances in N. Virginia, `docker run` would look like this, assuming your `jmeter-key.pem` file is located in the `keys` subdirectory:
```
docker run -v $PWD/plans:/plans -v $PWD/keys:/keys -v $PWD/logs:/logs \
    --env AWS_ACCESS_KEY_ID=ABCDEFGHIJKLMNOPQRST \
    --env AWS_SECRET_ACCESS_KEY=abcdefghijklmnopqrstuvwxyz0123456789ABCDEF \
    --env AWS_DEFAULT_REGION=us-east-1 \
    --env SECURITY_GROUP=sg-12345678 \
    --env SUBNET_ID=subnet-12345678 \
    --env KEY_NAME=jmeter-key \
    --env MINION_COUNT=5 \
    --enc INSTANCE_TYPE=t2.small \
    smithmicro/jmeter-ecs /plans/demo.jmx
```

## Architecture
This Docker image replaces the JMeter master/slave nomenclature with *Gru*, *Minion* and *Lucy*.  *Gru* manages the *Minions* from within EC2, but *Lucy* orchestrates the entire process.

*Lucy* runs the `lucy.sh` script to perform the following steps:
* Step 1 - Create an ECS Cluster
* Step 2 - Create all instances and register them with the Cluster
* Step 3 - Create the Minion ECS task
* Step 4 - Wait until the instances are running and registered with the Cluster
* Step 5 - Fetch our Contatiner Instance IDs
* Step 6 - Run a Minion Task with the requested instance count
* Step 7 - Get public IP addresses from Gru and Minions
* Step 8 - Run Gru with the specified JMX
  * JMeter does its thing here
  * Once complete, copy the jmeter.log and results.jtl files from Gru to Lucy
* Step 9 - Stop all Tasks
* Step 10 - Terminate all instances
* Step 100 - Delete the cluster

```
+-------------------------------------+
|  EC2           +-----------------+  |
|                |  ECS            |  |
|  +---------+   | +--------+      |  |
|  |         |   | | +--------+    |  |
|  |   Gru   |---->| | +--------+  |  |      +--------+
|  |         |<----| | |        |  |  |      |        |
|  +---------+   | +-| | Minion |----------->| Target |
|      ^ |       |   +-|        |  |  |      |        |
|      | |       |     +--------+  |  |      +--------+
|      | |       +-----------------+  |
+------|-|----------------------------+
       | |
  .jmx | | .log/.jtl
       | v
   +----------+
   |          |
   |   Lucy   |
   |          |
   +----------+
```

### Volumes
This image has 3 volumes:
* `/plans` - mapped into the orchestrator to provide the input JMX files
* `/keys` - mapped into the orchestrator to provide the PEM file
* `/logs` - mapped into the orchestrator to provide the output jmeter.log and results.jtl

## Local Testing with Docker Compose
The included docker-compose.yml file allows for local testing of the Gru and Minion nodes without incurring costs from AWS.
Edit the docker-compose.yml file and replicate the `links`, `environment` and `minionN` sections to increase the number of Minions to test.
```
version: '2'

services:
  gru:
    ...
    links: 
      - minion1
      - minion2
      - minion3
      - minion4
    environment: 
      - MINION_HOSTS=minion1,minion2,minion3,minion4
    ...
  minion1:
    image: smithmicro/jmeter-ecs:latest
  minion2:
    image: smithmicro/jmeter-ecs:latest
  minion3:
    image: smithmicro/jmeter-ecs:latest
  minion4:
    image: smithmicro/jmeter-ecs:latest

```
Then run:
```
docker-compose up
```
Using the `docker-compose scale` command does not work as it creates hostnames like `minion_1`.  This causes an error in JMeter as it uses the hostname in URL form and sees the underscore as an illegal URL character.

## Notes
This Docker image uses the Instance Metadata API documented here:
* http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html

To get the instance public hostname within the `entrypoint.sh` script, we call:
* `curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-hostname`

## Inspired by...
https://en.wikipedia.org/wiki/Despicable_Me_2

![Minions](https://pbs.twimg.com/tweet_video_thumb/C8CtmUbVwAAaboL.jpg "Minions")