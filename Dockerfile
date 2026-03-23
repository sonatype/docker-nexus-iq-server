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

# === Packages stage ===
# Uses a Wolfi base with apk to install runtime dependencies into an isolated
# root. This ensures all transitive deps (shared libs, etc.) are captured
# automatically and stay correct as packages evolve over time.
# hadolint ignore=DL3026,DL3018
FROM sonatype.repo.sonatype.app/docker-all/chainguard/wolfi-base AS packages
RUN apk add --no-cache --initdb --root /runtime-deps \
        --keys-dir /etc/apk/keys \
        --repositories-file /etc/apk/repositories \
        tini-static \
        git

# === Builder stage ===
# Uses the dev variant which includes busybox/shell for build operations
# hadolint ignore=DL3026
FROM sonatype.repo.sonatype.app/docker-all/sonatype-infosec/jdk:openjdk-17-dev AS builder
ARG TEMP="/tmp/work"
# Build parameters
ARG IQ_SERVER_VERSION=1.201.0-02
ARG IQ_SERVER_SHA256_AARCH=dcaeb10bd6caf4b073ad5453d87e3214f57ed60a25701ee65ba0db695b8fbacd
ARG IQ_SERVER_SHA256_X86_64=d3e16ee86eac5b0d00792ad2aa27c74faea19cc4083b35eb540b1b48604baa1e
ARG SONATYPE_WORK="/sonatype-work"

RUN mkdir -p ${TEMP}

WORKDIR ${TEMP}

# Copy config.yml and set sonatypeWork to the correct value
COPY config.yml .

# hadolint ignore=SC3060
RUN sed -ri "s/\s*sonatypeWork\s*:\s*\"?[-0-9a-zA-Z_/\\]+\"?/sonatypeWork: ${SONATYPE_WORK//\//\\/}/" config.yml

# Download the server bundle, verify its checksum, and extract the server jar to the install directory
# hadolint ignore=SC3010
RUN if [[ "$(uname -m)" = "x86_64" ]]; then \
      echo "${IQ_SERVER_SHA256_X86_64} nexus-iq-server.tar.gz" > nexus-iq-server.tar.gz.sha256; \
      wget -q -O nexus-iq-server.tar.gz https://download.sonatype.com/clm/server/nexus-iq-server-${IQ_SERVER_VERSION}-linux-x86_64.tgz; \
    elif [[ "$(uname -m)" = "aarch64" ]]; then \
      echo "${IQ_SERVER_SHA256_AARCH} nexus-iq-server.tar.gz" > nexus-iq-server.tar.gz.sha256; \
      wget -q -O nexus-iq-server.tar.gz https://download.sonatype.com/clm/server/nexus-iq-server-${IQ_SERVER_VERSION}-linux-aarch_64.tgz; \
    else \
      echo "Unsupported architecture: $(uname -m)" && exit 1; \
    fi

RUN sha256sum -c nexus-iq-server.tar.gz.sha256 \
    && tar -xvf nexus-iq-server.tar.gz \
    && mv nexus-iq-server-${IQ_SERVER_VERSION}-linux-* nexus-iq-server

# Compile the Java healthcheck class (used instead of curl in the distroless runtime)
COPY healthcheck.java .
RUN javac healthcheck.java

# === Runtime stage ===
# Uses the minimal variant (no package manager)
# hadolint ignore=DL3026
FROM sonatype.repo.sonatype.app/docker-all/sonatype-infosec/jdk:openjdk-17

ARG IQ_SERVER_VERSION=1.201.0-02
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
ARG SONATYPE_WORK="/sonatype-work"
ARG CONFIG_HOME="/etc/nexus-iq-server"
ARG LOGS_HOME="/var/log/nexus-iq-server"
ARG TIMEOUT=600

LABEL name="Nexus IQ Server image" \
  maintainer="Sonatype <support@sonatype.com>" \
  vendor=Sonatype \
  version="${IQ_SERVER_VERSION}" \
  release="1.201.0" \
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

# Copy runtime dependencies (git, tini) and all their transitive deps from the
# packages stage
COPY --from=packages /runtime-deps/ /

# Create folders & set permissions
# Using the infosec image's built-in nonroot user (uid/gid 65532)
RUN mkdir -p ${IQ_HOME} \
&& mkdir -p ${SONATYPE_WORK} \
&& mkdir -p ${CONFIG_HOME} \
&& mkdir -p ${LOGS_HOME} \
&& chmod 0755 "/opt/sonatype" ${IQ_HOME} \
&& chmod 0755 ${CONFIG_HOME} \
&& chmod 0755 ${LOGS_HOME} \
&& chown -R nonroot:nonroot ${IQ_HOME} \
&& chown -R nonroot:nonroot ${SONATYPE_WORK} \
&& chown -R nonroot:nonroot ${CONFIG_HOME} \
&& chown -R nonroot:nonroot ${LOGS_HOME}

# Copy config.yml
COPY --from=builder /tmp/work/config.yml ${CONFIG_HOME}/config.yml
RUN chmod 0644 ${CONFIG_HOME}/config.yml

# Copy server assemblies
COPY --chown=nonroot:nonroot --from=builder /tmp/work/nexus-iq-server ${IQ_HOME}

# Copy healthcheck class (precompiled in builder - replaces curl dependency)
COPY --from=builder /tmp/work/healthcheck.class /opt/sonatype/healthcheck/healthcheck.class


# Create start script
RUN echo "trap 'kill -TERM \`cut -f1 -d@ ${SONATYPE_WORK}/lock\`; timeout ${TIMEOUT} tail --pid=\`cut -f1 -d@ ${SONATYPE_WORK}/lock\` -f /dev/null' SIGTERM" > ${IQ_HOME}/start.sh \
&& echo "/opt/sonatype/nexus-iq-server/bin/nexus-iq-server server ${CONFIG_HOME}/config.yml 2> ${LOGS_HOME}/stderr.log & " >> ${IQ_HOME}/start.sh \
&& echo "wait" >> ${IQ_HOME}/start.sh \
&& chmod 0755 ${IQ_HOME}/start.sh

WORKDIR ${IQ_HOME}

# This is where we will store persistent data
VOLUME ${SONATYPE_WORK}
VOLUME ${LOGS_HOME}

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Wire up health check using precompiled Java class (no curl needed)
HEALTHCHECK CMD java -cp /opt/sonatype/healthcheck healthcheck || exit 1

# Change to nonroot user (uid 65532 - infosec standard)
USER 65532

ENV JAVA_OPTS=" -Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs "
ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

WORKDIR ${IQ_HOME}

# tini as init daemon for zombie process reaping
ENTRYPOINT ["/sbin/tini-static", "--"]
CMD [ "sh", "./start.sh" ]
