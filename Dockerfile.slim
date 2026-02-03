#
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
#

# hadolint ignore=DL3026
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7 AS builder
ARG TEMP="/tmp/work"
# Build parameters
ARG IQ_SERVER_VERSION=1.199.0-01
ARG IQ_SERVER_SHA256_AARCH=762f8e7f0341195cdd24ca538730e4215360bad34bb27a0c106604ff8cf17e4a
ARG IQ_SERVER_SHA256_X86_64=39f0e3837dfcfab5576adaa440537a57b6aa955d8d60d6dc0e43c30d6e06a5b7
ARG SONATYPE_WORK="/sonatype-work"

# hadolint ignore=DL3041,DL3040
RUN mkdir -p ${TEMP} && \
    microdnf update -y && \
    microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y procps gzip unzip tar shadow-utils findutils util-linux less rsync git which crypto-policies crypto-policies-scripts

# Copy config.yml and set sonatypeWork to the correct value
COPY config.yml ${TEMP}

# hadolint ignore=DL4006,SC3060
RUN cat ${TEMP}/config.yml | sed -r "s/\s*sonatypeWork\s*:\s*\"?[-0-9a-zA-Z_/\\]+\"?/sonatypeWork: ${SONATYPE_WORK//\//\\/}/" > ${TEMP}/config-edited.yml

# Download the server bundle, verify its checksum, and extract the server jar to the install directory
WORKDIR ${TEMP}
# hadolint ignore=SC3010
RUN if [[ "$(uname -m)" = "x86_64" ]]; then \
      echo "${IQ_SERVER_SHA256_X86_64} nexus-iq-server.tar.gz" > nexus-iq-server.tar.gz.sha256; \
      curl -L https://download.sonatype.com/clm/server/nexus-iq-server-${IQ_SERVER_VERSION}-linux-x86_64.tgz --output nexus-iq-server.tar.gz; \
    elif [[ "$(uname -m)" = "aarch64" ]]; then \
      echo "${IQ_SERVER_SHA256_AARCH} nexus-iq-server.tar.gz" > nexus-iq-server.tar.gz.sha256; \
      curl -L https://download.sonatype.com/clm/server/nexus-iq-server-${IQ_SERVER_VERSION}-linux-aarch_64.tgz --output nexus-iq-server.tar.gz; \
    else \
      echo "Unsupported architecture: $ARCH" && exit 1; \
    fi

RUN sha256sum -c nexus-iq-server.tar.gz.sha256 \
    && tar -xvf nexus-iq-server.tar.gz \
    && mv nexus-iq-server-${IQ_SERVER_VERSION}-linux-* nexus-iq-server

# hadolint ignore=DL3026
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7

ARG IQ_SERVER_VERSION=1.199.0-01
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
ARG SONATYPE_WORK="/sonatype-work"
ARG CONFIG_HOME="/etc/nexus-iq-server"
ARG LOGS_HOME="/var/log/nexus-iq-server"
ARG GID=1000
ARG UID=1000
ARG TIMEOUT=600

LABEL name="Nexus IQ Server image" \
  maintainer="Sonatype <support@sonatype.com>" \
  vendor=Sonatype \
  version="${IQ_SERVER_VERSION}" \
  release="1.199.0" \
  url="https://www.sonatype.com" \
  summary="The Nexus IQ Server" \
  description="Nexus IQ Server is a policy engine powered by precise intelligence on open source components. \
    It provides a number of tools to improve component usage in your software supply chain, allowing you to \
    automate your processes and achieve accelerated speed to delivery while also increasing product quality" \
  com.sonatype.license="Apache License, Version 2.0" \
  com.sonatype.name="Nexus IQ Server image" \
  run="docker run -d -p 8070:8070 -p 8071:8071 IMAGE" \
  io.k8s.description="Nexus IQ Server is a policy engine powered by precise intelligence on open source components. \
    It provides a number of tools to improve component usage in your software supply chain, allowing you to \
    automate your processes and achieve accelerated speed to delivery while also increasing product quality" \
  io.k8s.display-name="Nexus IQ Server" \
  io.openshift.expose-services="8071:8071" \
  io.openshift.tags="Sonatype,Nexus,IQ Server"

USER root

# For testing
# hadolint ignore=DL3041
RUN microdnf update -y \
&& microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y procps gzip unzip tar shadow-utils findutils util-linux less rsync git which crypto-policies crypto-policies-scripts \
&& microdnf clean all

# Create folders & set permissions
RUN mkdir -p ${IQ_HOME} \
&& mkdir -p ${SONATYPE_WORK} \
&& mkdir -p ${CONFIG_HOME} \
&& mkdir -p ${LOGS_HOME} \
&& chmod 0755 "/opt/sonatype" ${IQ_HOME} \
&& chmod 0755 ${CONFIG_HOME} \
&& chmod 0755 ${LOGS_HOME}

# Add group and user
RUN groupadd -g ${GID} nexus \
&& adduser -u ${UID} -d ${IQ_HOME} -c "Nexus IQ user" -g nexus -s /bin/false nexus \
# Change owner to nexus user
&& chown -R nexus:nexus ${IQ_HOME} \
&& chown -R nexus:nexus ${SONATYPE_WORK} \
&& chown -R nexus:nexus ${CONFIG_HOME} \
&& chown -R nexus:nexus ${LOGS_HOME}
    
# Copy config.yml
COPY --from=builder /tmp/work/config-edited.yml ${CONFIG_HOME}/config.yml
RUN chmod 0644 ${CONFIG_HOME}/config.yml

# Copy server assemblies
COPY --chown=nexus:nexus --from=builder /tmp/work/nexus-iq-server ${IQ_HOME}

# Create start script
RUN echo "trap 'kill -TERM \`cut -f1 -d@ ${SONATYPE_WORK}/lock\`; timeout ${TIMEOUT} tail --pid=\`cut -f1 -d@ ${SONATYPE_WORK}/lock\` -f /dev/null' SIGTERM" > ${IQ_HOME}/start.sh \
&& echo "/opt/sonatype/nexus-iq-server/bin/nexus-iq-server server ${CONFIG_HOME}/config.yml 2> ${LOGS_HOME}/stderr.log & " >> ${IQ_HOME}/start.sh \
&& echo "wait" >> ${IQ_HOME}/start.sh \
&& chmod 0755 ${IQ_HOME}/start.sh

WORKDIR ${IQ_HOME}

# enabling back support for SHA1 signed certificates
RUN update-crypto-policies --set DEFAULT:SHA1

# This is where we will store persistent data
VOLUME ${SONATYPE_WORK}
VOLUME ${LOGS_HOME}

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Wire up health check
HEALTHCHECK CMD curl --fail --silent --show-error http://localhost:8071/healthcheck || exit 1

# Change to nexus user
USER nexus

ENV JAVA_OPTS=" -Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs "
ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

WORKDIR ${IQ_HOME}

CMD [ "sh", "./start.sh" ]
