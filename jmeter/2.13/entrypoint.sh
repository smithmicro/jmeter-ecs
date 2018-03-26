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
  rm /logs/*.log /logs/*.jtl
  # run jmeter in client (gru) mode
  exec jmeter -n $JMETER_FLAGS \
    -R $MINION_HOSTS \
    -Dclient.rmi.localport=51000 \
    -Djava.rmi.server.hostname=${PUBLIC_HOSTNAME} \
    -l $RESULTS_LOG \
    -t $1

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
  # run jmeter in server (minion) mode
  exec jmeter-server -n \
    -Dserver.rmi.localport=50000 \
    -Djava.rmi.server.hostname=${HOSTNAME}

fi

exec "$@"
