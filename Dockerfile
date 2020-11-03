# Copyright (c) 2017-present Sonatype, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM registry.access.redhat.com/ubi8/openjdk-8

# Build parameters
ARG IQ_SERVER_VERSION=1.101.0-01
ARG IQ_SERVER_SHA256=07824c61dd92dfede79df7515f3af7269972f4354ec8a32efc986be7e81b6fec
ARG TEMP="/tmp/work"
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
ARG SONATYPE_WORK="/sonatype-work"
ARG CONFIG_HOME="/etc/nexus-iq-server"
ARG LOGS_HOME="/var/log/nexus-iq-server"

ENV DOCKER_TYPE="docker"

LABEL vendor=Sonatype \
  maintainer="Sonatype <support@sonatype.com>" \
  com.sonatype.license="Apache License, Version 2.0" \
  com.sonatype.name="Nexus IQ Server image"

USER root

# For testing
RUN microdnf install procps

# Create folders
RUN mkdir -p ${TEMP} \
&& mkdir -m 0755 -p ${IQ_HOME} \
&& mkdir -m 0755 -p ${SONATYPE_WORK} \
&& mkdir -m 0755 -p ${CONFIG_HOME} \
&& mkdir -m 0755 -p ${LOGS_HOME}

# Copy config.yml and set sonatypeWork to the correct value
COPY config.yml ${TEMP}
RUN cat ${TEMP}/config.yml | sed -r "s/\s*sonatypeWork\s*:\s*\"?[-0-9a-zA-Z_/\\]+\"?/sonatypeWork: ${SONATYPE_WORK//\//\\/}/" > ${CONFIG_HOME}/config.yml \
&& chmod 0644 ${CONFIG_HOME}/config.yml

# Create start script
RUN echo "/usr/bin/java ${JAVA_OPTS} -jar nexus-iq-server-${IQ_SERVER_VERSION}.jar server ${CONFIG_HOME}/config.yml 2> ${LOGS_HOME}/stderr.log" > ${IQ_HOME}/start.sh \
&& chmod 0755 ${IQ_HOME}/start.sh

# Download the server bundle, verify its checksum, and extract the server jar to the install directory
RUN cd ${TEMP} \
&& curl -L https://download.sonatype.com/clm/server/nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz --output nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz \
&& echo "${IQ_SERVER_SHA256} nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz" > nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz.sha256 \
&& sha256sum -c nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz.sha256 \
&& tar -xvf nexus-iq-server-${IQ_SERVER_VERSION}-bundle.tar.gz \
&& mv nexus-iq-server-${IQ_SERVER_VERSION}.jar ${IQ_HOME} \
&& cd ${IQ_HOME} \
&& rm -rf ${TEMP}

# Add group and user
RUN groupadd nexus \
&& adduser -d ${IQ_HOME} -c "Nexus IQ user" -g nexus -s /bin/false -r nexus

# Change owner to nexus user
RUN chown -R nexus:nexus ${IQ_HOME} \
&& chown -R nexus:nexus ${SONATYPE_WORK} \
&& chown -R nexus:nexus ${CONFIG_HOME} \
&& chown -R nexus:nexus ${LOGS_HOME}

# This is where we will store persistent data
VOLUME ${SONATYPE_WORK}
VOLUME ${LOGS_HOME}

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Change to nexus user
USER nexus

ENV JAVA_OPTS="-Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs"

WORKDIR ${IQ_HOME}

CMD [ "sh", "./start.sh" ]
