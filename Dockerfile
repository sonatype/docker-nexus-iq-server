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
# Uses a Wolfi base with apk to:
# 1. Install runtime dependencies (git, tini) into an isolated root
# 2. Download the IQ Server artifacts from Maven (needs Maven for auth + SNAPSHOT resolution)
# 3. Create users, groups, and directory structure for the runtime image
# hadolint ignore=DL3006,DL3026
FROM sonatype.repo.sonatype.app/docker-all/chainguard/wolfi-base AS packages

ARG IQ_SERVER_VERSION=1.203.0-SNAPSHOT
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
ARG SONATYPE_WORK="/sonatype-work"
ARG CONFIG_HOME="/etc/nexus-iq-server"
ARG LOGS_HOME="/var/log/nexus-iq-server"
ARG GID=1000
ARG UID=1000

# Install Maven + JRE (for artifact download) and runtime deps into isolated root.
# Runtime deps rationale:
# - tini-static: init daemon for zombie process reaping and signal forwarding
# - git: required for IQ Server SCM integrations
# - gcc: compile the launcher.c (build-time only, not copied to runtime)
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
# hadolint ignore=DL3018
RUN apk add --no-cache maven-3.9 openjdk-17-jre gcc \
    && apk add --no-cache --initdb --root /runtime-deps \
        --keys-dir /etc/apk/keys \
        --repositories-file /etc/apk/repositories \
        tini-static \
        git

# Copy and compile the launcher with build-time paths
COPY launcher.c /tmp/launcher.c
RUN gcc -DIQ_HOME=\"${IQ_HOME}\" \
         -DCONFIG_HOME=\"${CONFIG_HOME}\" \
         -DLOGS_HOME=\"${LOGS_HOME}\" \
         -o /runtime-deps/bin/launcher /tmp/launcher.c

# Create user/group entries in runtime root.
# Include root user (UID 0) for system compatibility, plus nexus user.
RUN mkdir -p /runtime-deps/etc \
    && echo "root:x:0:0:root:/root:/bin/sh" > /runtime-deps/etc/passwd \
    && echo "nexus:x:${UID}:${GID}:Nexus IQ user:${IQ_HOME}:/bin/false" >> /runtime-deps/etc/passwd \
    && echo "root:x:0:" > /runtime-deps/etc/group \
    && echo "nexus:x:${GID}:" >> /runtime-deps/etc/group

# Create directory structure with proper ownership in runtime root
RUN mkdir -p /runtime-deps/opt/sonatype/nexus-iq-server \
    && mkdir -p /runtime-deps/sonatype-work \
    && mkdir -p /runtime-deps/etc/nexus-iq-server \
    && mkdir -p /runtime-deps/var/log/nexus-iq-server \
    && chown -R ${UID}:${GID} /runtime-deps/opt/sonatype/nexus-iq-server \
    && chown -R ${UID}:${GID} /runtime-deps/sonatype-work \
    && chown -R ${UID}:${GID} /runtime-deps/etc/nexus-iq-server \
    && chown -R ${UID}:${GID} /runtime-deps/var/log/nexus-iq-server

# Download the server jar and JVM options file as individual Maven artifacts.
# Uses BuildKit secret mount for settings.xml so credentials never appear in any layer.
# Maven handles SNAPSHOT version resolution automatically.
WORKDIR /tmp/download/nexus-iq-server
# hadolint ignore=SC2046
RUN --mount=type=secret,id=maven-settings,target=/root/.m2/settings.xml \
    mvn dependency:copy \
        -Dartifact=com.sonatype.insight.brain:insight-brain-service:${IQ_SERVER_VERSION}:jar:server \
        -DoutputDirectory=. \
    && mvn dependency:copy \
        -Dartifact=com.sonatype.insight.brain:nexus-iq-server:${IQ_SERVER_VERSION}:options:jvm \
        -DoutputDirectory=. \
    && mv insight-brain-service-*-server.jar nexus-iq-server.jar \
    && mv nexus-iq-server-*-jvm.options jvm.options

# Copy downloaded server files into runtime root with correct ownership
RUN cp -r /tmp/download/nexus-iq-server/* /runtime-deps/opt/sonatype/nexus-iq-server/ \
    && chown -R ${UID}:${GID} /runtime-deps/opt/sonatype/nexus-iq-server

# Copy config.yml into runtime root with correct permissions
COPY config.yml /runtime-deps/etc/nexus-iq-server/config.yml
RUN chown ${UID}:${GID} /runtime-deps/etc/nexus-iq-server/config.yml \
    && chmod 0644 /runtime-deps/etc/nexus-iq-server/config.yml

# === Runtime stage ===
# Uses the minimal variant (no package manager, no shell)
# hadolint ignore=DL3026
FROM sonatype.repo.sonatype.app/docker-all/sonatype-infosec/jre:openjdk-17

ARG IQ_SERVER_VERSION=1.203.0-SNAPSHOT
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
ARG SONATYPE_WORK="/sonatype-work"
ARG CONFIG_HOME="/etc/nexus-iq-server"
ARG LOGS_HOME="/var/log/nexus-iq-server"
ARG TIMEOUT=600

LABEL name="Nexus IQ Server image" \
  maintainer="Sonatype <support@sonatype.com>" \
  vendor=Sonatype \
  version="${IQ_SERVER_VERSION}" \
  release="1.203.0" \
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

# Copy the entire runtime filesystem from packages stage:
# - /etc/passwd and /etc/group (nexus user/group)
# - /bin/launcher
# - /sbin/tini-static
# - /opt/sonatype/nexus-iq-server (with server jar and jvm.options)
# - /etc/nexus-iq-server/config.yml
# - /var/log/nexus-iq-server directory
# - /sonatype-work directory
# - git and its dependencies
COPY --from=packages /runtime-deps/ /

WORKDIR ${IQ_HOME}

# This is where we will store persistent data
VOLUME ${SONATYPE_WORK}
VOLUME ${LOGS_HOME}

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Wire up health check using localcheck (built into infosec base images)
HEALTHCHECK CMD ["localcheck", "--port", "8071"]

# Change to nexus user (created in packages stage)
USER nexus

ENV JAVA_OPTS=" -Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs "
ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

# tini as init daemon for zombie process reaping and signal forwarding
ENTRYPOINT ["/sbin/tini-static", "--"]
CMD ["/bin/launcher"]
