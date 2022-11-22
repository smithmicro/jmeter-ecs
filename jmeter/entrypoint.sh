#!/bin/sh
#
# Main entrypoint for our Docker image - runs Gru, Minions or other commands

# any .jmx file passed in the command line we act as 'Gru'
if [ ${1##*.} = 'jmx' ]; then

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

  # limit thread duration in .jmx if TIME_LIMIT is positive number
  if [ "${TIME_LIMIT}" -gt "0" ] 2> /dev/null
  then
    xml ed --inplace \
    --update "//boolProp[@name='ThreadGroup.scheduler']" --value true \
    --update "//stringProp[@name='ThreadGroup.duration' and (.='' or .<${TIME_LIMIT})]" --value $TIME_LIMIT \
    $1
  fi

  # run jmeter in client (gru) mode
  exec jmeter -n $JMETER_FLAGS \
    -R $MINION_HOSTS \
    -Dclient.rmi.localport=51000 \
    -Dserver.rmi.ssl.disable=true \
    -Djava.rmi.server.hostname=${PUBLIC_HOSTNAME} \
    -l $RESULTS_LOG \
    -t $1 \
    -e -o /logs/report

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
