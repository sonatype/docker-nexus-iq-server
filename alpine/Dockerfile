FROM openjdk:8u201-alpine

LABEL maintainer="Sonatype <cloud-ops@sonatype.com>"

LABEL vendor=Sonatype \
  com.sonatype.license="Apache License, Version 2.0" \
  com.sonatype.name="Nexus IQ Server image"

# This is where we will store persistent data
VOLUME /sonatype-work

# Create needed directories
RUN mkdir -p /opt/sonatype/nexus-iq-server /etc/nexus-iq-server /var/log/nexus-iq-server

# Change working dir
WORKDIR /opt/sonatype/nexus-iq-server

# Add nexus user and group
RUN adduser -s /bin/false -S nexus nexus
RUN addgroup nexus
RUN chown nexus:nexus /opt/sonatype/nexus-iq-server /etc/nexus-iq-server /var/log/nexus-iq-server

# Change to nexus user
USER nexus

# Version to download
ARG IQ_SERVER_VERSION=1.64.0-02
ARG IQ_SERVER_SHA256=d79cae556c60982191a026d8407ca4c8b96f26876d088067fa4ae7ef1c39cb99

# Fetch and configure IQ
RUN mkdir /tmp/work && cd /tmp/work \
&& wget https://download.sonatype.com/clm/server/nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz \
&& tar xvf nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz \
&& mv nexus-iq-server-${IQ_SERVER_VERSION}.jar /opt/sonatype/nexus-iq-server \
&& cd /opt/sonatype/nexus-iq-server \
&& rm -rf /tmp/work

# Copy the standard config.yml to the container
COPY config.yml /etc/nexus-iq-server

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Configure the start script
ENV JAVA_OPTS="-Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs"
RUN echo "/usr/bin/java ${JAVA_OPTS} -jar nexus-iq-server-${IQ_SERVER_VERSION}.jar server /etc/nexus-iq-server/config.yml" > start.sh
RUN chmod u+x start.sh

CMD [ "sh","./start.sh" ]
