FROM openjdk:8-alpine

LABEL maintainer="David Sperling <dsperling@smithmicro.com>"

ENV JMETER_VERSION apache-jmeter-3.1
ENV JMETER_HOME /opt/$JMETER_VERSION
ENV PATH $JMETER_HOME/bin:$PATH

# overridable environment variables
ENV MINION_HOSTS=
ENV RESULTS_LOG results.jtl
ENV JMETER_FLAGS=
ENV AWS_ACCESS_KEY_ID=
ENV AWS_SECRET_ACCESS_KEY=
ENV AWS_DEFAULT_REGION=

# Install the AWS CLI which requires PIP
RUN apk add --update --no-cache \
    curl \
    openssh-client \
    python \
    py-pip \
    unzip \
  && pip install awscli

WORKDIR /opt

# install JMeter and a few Plugins
RUN curl -O https://archive.apache.org/dist/jmeter/binaries/$JMETER_VERSION.tgz \
  && tar -xvf $JMETER_VERSION.tgz \
  && rm $JMETER_VERSION.tgz \
  && rm -rf $JMETER_VERSION/docs $JMETER_VERSION/printable_docs \
  && curl -O https://jmeter-plugins.org/files/JMeterPlugins-Standard-1.4.0.zip \
    -O https://jmeter-plugins.org/files/JMeterPlugins-Extras-1.4.0.zip \
    -O https://jmeter-plugins.org/files/JMeterPlugins-ExtrasLibs-1.4.0.zip \
  && unzip -n '*.zip' \
  && rm *.zip

# copy our scripts and Task definition
COPY entrypoint.sh lucy.sh cluster.sh minion.json ./jmeter/
RUN chmod +x jmeter/*.sh

WORKDIR /logs

EXPOSE 1099 4445 50000 51000

# default command in the entrypoint is 'minion'
ENTRYPOINT ["/opt/jmeter/entrypoint.sh"]
CMD ["minion"]
