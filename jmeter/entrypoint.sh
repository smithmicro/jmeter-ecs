#!/bin/sh
#
# Main entrypoint for our Docker image - runs Gru, Minions or other commands

# any .jmx file passed in the command line we act as 'Gru'
if [ ${1##*.} = 'jmx' ]; then

  if [ "$MINION_COUNT" = '' ]; then
    echo "MINION_COUNT must be specified - a command separated list of minion counts of the same length as list of .jmx files in 1st command line argument"
    exit 1
  fi
  if [ "$MINION_HOSTS" = '' ]; then
    echo "MINION_HOSTS must be specified - a command separated list of hostnames or IP addresses"
    exit 1
  fi
  echo "Connecting to $MINION_HOSTS"

  # AWS Public HOSTNAME API
  echo "Detecting an AWS Environment"
  PUBLIC_HOSTNAME=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-hostname)

  if [ "$PUBLIC_HOSTNAME" = '' ]; then
    echo "Not running in AWS.  Using Gru HOSTNAME $HOSTNAME"
  else
    HOSTNAME=$PUBLIC_HOSTNAME
    echo "Using Gru AWS Public HOSTNAME $HOSTNAME"
  fi
  # empty the logs directory, or jmeter may fail
  rm -rf /logs/report /logs/*.log /logs/*.jtl

  # remove setting JAVA heap
  sed -i 's/-Xms1g -Xmx1g -XX:MaxMetaspaceSize=256m//' $JMETER_HOME/bin/jmeter

  # run jmeter in client (gru) mode for all testplans
  TEMP_INPUT_JMX=$1,
  TEMP_MINION_COUNT=$MINION_COUNT,
  TEMP_MINION_HOSTS=$MINION_HOSTS

  while [ "$TEMP_INPUT_JMX" ]
  do
    INPUT_JMX_FOR_TESTPLAN=${TEMP_INPUT_JMX%%,*}
    MINION_COUNT_FOR_TESTPLAN=${TEMP_MINION_COUNT%%,*}
    MINION_HOSTS_FOR_TESTPLAN=$(echo $TEMP_MINION_HOSTS | cut -f1-$MINION_COUNT_FOR_TESTPLAN -d,)
    PORT_FOR_TESTPLAN=$((51000 + ${#TEMP_INPUT_JMX}))
    NAME_FOR_TESTPLAN=$(basename $INPUT_JMX_FOR_TESTPLAN .jmx)
    echo MINION_COUNT_FOR_TESTPLAN $MINION_COUNT_FOR_TESTPLAN
    echo TEMP_MINION_HOSTS $TEMP_MINION_HOSTS

    jmeter -n $JMETER_FLAGS \
      -R $MINION_HOSTS_FOR_TESTPLAN \
      -Dclient.rmi.localport=$PORT_FOR_TESTPLAN \
      -Dserver.rmi.ssl.disable=true \
      -Djava.rmi.server.hostname=${PUBLIC_HOSTNAME} \
      -l $NAME_FOR_TESTPLAN.jtl \
      -j $NAME_FOR_TESTPLAN.log \
      -t $INPUT_JMX_FOR_TESTPLAN \
      -e -o /logs/$NAME_FOR_TESTPLAN &

    TEMP_INPUT_JMX=${TEMP_INPUT_JMX#*,}
    TEMP_MINION_COUNT=${TEMP_MINION_COUNT#*,}
    TEMP_MINION_HOSTS=$(echo $TEMP_MINION_HOSTS | cut -f$(($MINION_COUNT_FOR_TESTPLAN + 1))- -d,)
  done

  # wait for jmeter processes to finish
  while pgrep jmeter > /dev/null
  do
    sleep 20
  done

  exit

fi

# act as a 'Minion'
if [ "$1" = 'minion' ]; then

  # AWS Public HOSTNAME API
  echo "Detecting an AWS Environment"
  PUBLIC_HOSTNAME=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-hostname)

  if [ "$PUBLIC_HOSTNAME" = '' ]; then
    echo "Not running in AWS.  Using Minion HOSTNAME $HOSTNAME"
  else
    HOSTNAME=$PUBLIC_HOSTNAME
    echo "Using Minion AWS Public HOSTNAME $HOSTNAME"
  fi

  # remove setting JAVA heap
  sed -i 's/-Xms1g -Xmx1g -XX:MaxMetaspaceSize=256m//' $JMETER_HOME/bin/jmeter

  # install custom plugin if requested
  if [ "$CUSTOM_PLUGIN_URL" != '' ]; then
    echo "Installing custom plugin $CUSTOM_PLUGIN_URL"
    CUSTOM_PLUGIN_FILE="${CUSTOM_PLUGIN_URL##*/}"
    curl -o $JMETER_HOME/lib/ext/$CUSTOM_PLUGIN_FILE $CUSTOM_PLUGIN_URL
  fi

  # run jmeter in server (minion) mode
  exec jmeter-server -n $JMETER_FLAGS \
    -Dserver.rmi.localport=50000 \
    -Dserver.rmi.ssl.disable=true \
    -Djava.rmi.server.hostname=${HOSTNAME}

fi

exec "$@"
