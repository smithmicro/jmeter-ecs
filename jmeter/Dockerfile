FROM openjdk:8-alpine

LABEL maintainer="David Sperling <dsperling@smithmicro.com>"

ENV JMETER_VERSION apache-jmeter-5.2
ENV JMETER_HOME /opt/$JMETER_VERSION
ENV PATH $PATH:$JMETER_HOME/bin
ENV CMDRUNNER_VERSION 2.2
ENV PLUGINMGR_VERSION 1.3

# overridable environment variables
ENV RESULTS_LOG results.jtl
ENV JMETER_FLAGS=
ENV CUSTOM_PLUGIN_URL=

# Install the required tools for JMeter
RUN apk add --update --no-cache \
    curl \
    openssh-client

WORKDIR /opt

# install JMeter and the JMeter Plugins Manager
RUN curl -O https://archive.apache.org/dist/jmeter/binaries/$JMETER_VERSION.tgz \
  && tar -xvf $JMETER_VERSION.tgz \
  && rm $JMETER_VERSION.tgz \
  && rm -rf $JMETER_VERSION/docs $JMETER_VERSION/printable_docs \
  && cd $JMETER_HOME/lib \
  && curl -OL http://search.maven.org/remotecontent?filepath=kg/apc/cmdrunner/$CMDRUNNER_VERSION/cmdrunner-$CMDRUNNER_VERSION.jar \
  && cd $JMETER_HOME/lib/ext \
  && curl -OL4 http://search.maven.org/remotecontent?filepath=kg/apc/jmeter-plugins-manager/$PLUGINMGR_VERSION/jmeter-plugins-manager-$PLUGINMGR_VERSION.jar \
  && java -cp jmeter-plugins-manager-$PLUGINMGR_VERSION.jar org.jmeterplugins.repository.PluginManagerCMDInstaller

# install all available plugins except for those that are deprecated
RUN PluginsManagerCMD.sh install-all-except jpgc-hadoop,jpgc-oauth \
  && sleep 2 \
  && PluginsManagerCMD.sh status

# copy our entrypoint
COPY entrypoint.sh /opt/jmeter/

WORKDIR /logs

EXPOSE 1099 50000 51000 4445/udp

# default command in the entrypoint is 'minion'
ENTRYPOINT ["/opt/jmeter/entrypoint.sh"]
CMD ["minion"]
