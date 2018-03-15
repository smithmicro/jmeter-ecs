# JMeter for ECS
JMeter Images for Distributed Testing on EC2 Container Service (ECS)

This application uses two images:
* `smithmicro/jmeter` - Contains the JMeter software that is deployed in ECS
* `smithmicro/lucy` - The orchestration image that can run behind a corporate firewall and manages AWS resources

_Warning: Using these Docker images will incur compute and storage costs in AWS.  Care is taken to terminate all instances and volumes after JMeter tests complete, but bugs could allow these resources to continue to run.  See the issues list for more detail._

## How to Use
The `smithmicro/lucy` Docker image can be run as-is with a number of required environement variables.

Prerequisites to use this image:
* Create a VPC with at least one subnet as ECS requires the use of VPC **
* Create a VPC security group that allows ports 22, 1099, 50000 and 51000 (tcp) and 4445 (udp) to the VPC **
* Create a security key pair and place in the `keys` subdirectory
* Have your AWS CLI Access Key ID/Secret Access Key handy
* Replace or edit the included `plans/demo.jmx` to run your specific tests
* Ensure you have a Role named `ecsInstanceRole`.  This is created by the ECS first-run experience.
  * More details here: http://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html

** If you do not have a VPC created, you can use the included `aws-setup.sh` script to create the VPC, Subnet and required Security Group.

Docker run template:
```
docker run -v <oath to jmx>:/plans -v <path to pem>:/keys -v <path to logs>:/logs \
    --env AWS_ACCESS_KEY_ID=<key id> \
    --env AWS_SECRET_ACCESS_KEY=<access key> \
    --env AWS_DEFAULT_REGION=<region> \
    --env SECURITY_GROUP=<security group within your VPC> \
    --env SUBNET_ID=<subnet IDs within your VPC> \
    --env KEY_NAME=<key pair name without extension> \
    --env MINION_COUNT=<number of minions> \
    smithmicro/lucy /plans/demo.jmx
```
For 5 test instances in N. Virginia, `docker run` would look like this, assuming your `jmeter-key.pem` file is located in the `keys` subdirectory:
```
docker run -v $PWD/plans:/plans -v $PWD/keys:/keys -v $PWD/logs:/logs \
    --env AWS_ACCESS_KEY_ID=ABCDEFGHIJKLMNOPQRST \
    --env AWS_SECRET_ACCESS_KEY=abcdefghijklmnopqrstuvwxyz0123456789ABCDEF \
    --env AWS_DEFAULT_REGION=us-east-1 \
    --env SECURITY_GROUP=sg-12345678 \
    --env SUBNET_ID=subnet-12345678,subnet-87654321 \
    --env KEY_NAME=jmeter-key \
    --env MINION_COUNT=5 \
    smithmicro/lucy /plans/demo.jmx
```

## Architecture
This Docker image replaces the JMeter master/slave nomenclature with *Gru*, *Minion* and *Lucy*.  *Gru* manages the *Minions* from within ECS, but *Lucy* orchestrates the entire process.

```
+--------------------------------------+
|  EC2                                 |
|  +--------------------------------+  |
|  |  ECS                           |  |
|  |                +--------+      |  |
|  |  +-------+     | +--------+    |  |      +--------+
|  |  |       |---->| | +--------+ ---------->|        |
|  |  |  Gru  |<----| | |        | ---------->| Target |
|  |  |       |     +-| | Minion | ---------->|        |
|  |  +-------+       +-|        |  |  |      +--------+
|  |     ^ |            +--------+  |  |
|  +-----|-|------------------------+  |
+--------|-|---------------------------+
         | |
    .jmx | | .log/.jtl
         | v
     +----------+
     |          |
     |   Lucy   |
     |          |
     +----------+
```

*Lucy* runs the `lucy.sh` script to perform the following steps:
* Step 1 - Create the ECS Cluster
* Step 2 - Wait for the cluster to have all container instances registered
* Step 3 - Run a Minion Task with the requested instance count
* Step 4 - Get Gru and Minion's instance ID's
* Step 5 - Get IP addresses from Gru and Minions
* Step 6 - Run Gru with the specified JMX
* Step 7 - Fetch the results from Gru
* Step 8 - Delete the cluster

### Volumes
The `lucy` container uses 3 volumes:
* `/plans` - mapped into the orchestrator to provide the input JMX files
* `/keys` - mapped into the orchestrator to provide the PEM file
* `/logs` - mapped into the orchestrator to provide the output jmeter.log and results.jtl

## Environment Variables
The following required and optional environment variables are supported:

| Variable | Required | Default | Notes |
|---|---|---|---|
|AWS_DEFAULT_REGION|Yes|None|AWS Region (e.g. `us-east-1`)|
|AWS_ACCESS_KEY_ID|Yes|None|AWS Access Key|
|AWS_SECRET_ACCESS_KEY|Yes|None|AWS Secret Key|
|INPUT_JMX|Yes|None|File path of JMeter Test file to run (.jmx).  You can optionally specify this as the first command line option of `docker run`|
|KEY_NAME|Yes|None|AWS Security Key Pair .pem file (do not specify the .pem extension)|
|SECURITY_GROUP|Yes|None|AWS Secuirty group that allows ports 22,1099,50000,51000/tcp and 4445/udp from all ports (e.g. sg-12345678)|
|SUBNET_ID|Yes|None|One or more Subnets (comma separated) that are assigned to your VPC|
|VPC_ID||VPC assigned to SUBNET_ID|We dautomatically erive this from your SUBNET_ID|
|JMETER_VERSION||latest|smithmicro/lucy Image tag.  See Docker Hub for [available versions](https://hub.docker.com/r/smithmicro/jmeter/tags/).|
|INSTANCE_TYPE||t2.micro|To double your memory, pass `t2.small`|
|MEM_LIMIT||950m|If you are using t2.small, set MEM_LIMIT to `1995m`|
|MINION_COUNT||2||
|PEM_PATH||/keys|This must match your Volume map.  See Volume section above.|
|CLUSTER_NAME||JMeter|Name that appears in your AWS Cluster UI|
|GRU_PRIVATE_IP||None|Set to `true` if you would like to run Lucy within AWS.  See GitHub [Issue 8](https://github.com/smithmicro/jmeter-ecs/issues/8) for details.|
|JMETER_FLAGS||None|Custom JMeter command line options.  For example, passing `-X` will tell the Minion to exit at the end of the test|
|RETAIN_CLUSTER||None|Set to `true` if you want to re-use your cluster for future tests.  Warning, you will incur AWS charges if you leave your cluster running.|

## Notes
For more information on JMeter Distributed Testing, see:
* http://jmeter.apache.org/usermanual/remote-test.html

## Inspired by...
https://en.wikipedia.org/wiki/Despicable_Me_2

![Minions](https://pbs.twimg.com/tweet_video_thumb/C8CtmUbVwAAaboL.jpg "Minions")
