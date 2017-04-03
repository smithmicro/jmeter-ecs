FROM alpine:3.5

LABEL maintainer="David Sperling <dsperling@smithmicro.com>"

# overridable environment variables
ENV MINION_HOSTS=
ENV RESULTS_LOG results.jtl
ENV JMETER_FLAGS=
ENV AWS_ACCESS_KEY_ID=
ENV AWS_SECRET_ACCESS_KEY=
ENV AWS_DEFAULT_REGION=

# Install the AWS CLI
RUN apk add --update --no-cache \
    openssh-client \
    python \
    py-pip \
  && pip install \
    awscli

# copy our scripts and Task definition
COPY lucy.sh cluster.sh minion.json /opt/jmeter/
RUN chmod +x /opt/jmeter/*.sh

WORKDIR /logs

# default command in the entrypoint is 'minion'
ENTRYPOINT ["/opt/jmeter/lucy.sh"]
