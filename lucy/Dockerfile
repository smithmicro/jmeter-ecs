FROM alpine:3.8

LABEL maintainer="David Sperling <dsperling@smithmicro.com>"

# overridable environment variables
ENV MINION_HOSTS=
ENV RESULTS_LOG results.jtl
ENV JMETER_FLAGS=
ENV AWS_ACCESS_KEY_ID=
ENV AWS_SECRET_ACCESS_KEY=
ENV AWS_DEFAULT_REGION=
ENV RETAIN_CLUSTER=
ENV CUSTOM_PLUGIN_URL=

# Install the AWS CLI
RUN apk add --update --no-cache \
    ca-certificates \
    openssh-client \
    openssl \
    python \
    py-pip \
  && pip install \
    awscli

# Install the ECS CLI
RUN wget -O /usr/local/bin/ecs-cli -q https://s3.amazonaws.com/amazon-ecs-cli/ecs-cli-linux-amd64-latest \
  && chmod +x /usr/local/bin/ecs-cli

# copy our entrypoint script and compose file for the Minions
COPY lucy.sh lucy.yml /opt/jmeter/

WORKDIR /logs

# default command in the entrypoint is 'minion'
ENTRYPOINT ["/opt/jmeter/lucy.sh"]
