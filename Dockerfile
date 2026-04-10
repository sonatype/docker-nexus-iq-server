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
# hadolint ignore=DL3006,DL3026
FROM sonatype.repo.sonatype.app/docker-all/chainguard/wolfi-base AS packages
ARG IQ_SERVER_VERSION=1.203.0-SNAPSHOT

# Install Maven + JRE (for artifact download) and runtime deps into isolated root.
# Runtime deps rationale:
# - busybox: provides /bin/sh (runtime image is distroless, needs shell for start.sh)
# - tini-static: init daemon for zombie process reaping
# - git: required for IQ Server SCM integrations
# hadolint ignore=DL3018
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
RUN apk add --no-cache maven-3.9 openjdk-17-jre \
    && apk add --no-cache --initdb --root /runtime-deps \
        --keys-dir /etc/apk/keys \
        --repositories-file /etc/apk/repositories \
        busybox \
        tini-static \
        git

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

# === Builder stage ===
# Uses the JDK dev variant for javac (healthcheck) and sed (config)
# hadolint ignore=DL3026
FROM sonatype.repo.sonatype.app/docker-all/sonatype-infosec/jdk:openjdk-17-dev AS builder
ARG TEMP="/tmp/work"

RUN mkdir -p ${TEMP}

WORKDIR ${TEMP}

# Copy config.yml (already configured for Docker with absolute paths)
COPY config.yml .

# Compile the Java healthcheck class (used instead of curl in the distroless runtime)
COPY Healthcheck.java .
RUN javac Healthcheck.java

# === Runtime stage ===
# Uses the minimal variant (no package manager)
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

# The infosec runtime image defaults to a non-root user; switch to root for setup
USER root

# Copy runtime dependencies (git, tini) and all their transitive deps from the
# packages stage
COPY --from=packages /runtime-deps/ /

# Ensure nonroot user/group entries exist for UID/GID resolution
RUN echo 'nonroot:x:65532:' >> /etc/group \
&& echo 'nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin' >> /etc/passwd

# Create folders & set permissions
RUN mkdir -p ${IQ_HOME} \
&& mkdir -p ${SONATYPE_WORK} \
&& mkdir -p ${CONFIG_HOME} \
&& mkdir -p ${LOGS_HOME} \
&& chmod 0755 "/opt/sonatype" ${IQ_HOME} \
&& chmod 0755 ${CONFIG_HOME} \
&& chmod 0755 ${LOGS_HOME} \
&& chown -R 65532:65532 ${IQ_HOME} \
&& chown -R 65532:65532 ${SONATYPE_WORK} \
&& chown -R 65532:65532 ${CONFIG_HOME} \
&& chown -R 65532:65532 ${LOGS_HOME}

# Copy config.yml
COPY --from=builder /tmp/work/config.yml ${CONFIG_HOME}/config.yml
RUN chmod 0644 ${CONFIG_HOME}/config.yml

# Copy server assemblies
COPY --chown=65532:65532 --from=packages /tmp/download/nexus-iq-server ${IQ_HOME}

# Copy healthcheck class (precompiled in builder - replaces curl dependency)
COPY --from=builder /tmp/work/Healthcheck.class /opt/sonatype/healthcheck/Healthcheck.class


# Create start script
RUN echo "trap 'kill -TERM \`cut -f1 -d@ ${SONATYPE_WORK}/lock\`; timeout ${TIMEOUT} tail --pid=\`cut -f1 -d@ ${SONATYPE_WORK}/lock\` -f /dev/null' SIGTERM" > ${IQ_HOME}/start.sh \
&& echo "java @${IQ_HOME}/jvm.options \$JAVA_OPTS -jar ${IQ_HOME}/nexus-iq-server.jar server ${CONFIG_HOME}/config.yml 2> ${LOGS_HOME}/stderr.log & " >> ${IQ_HOME}/start.sh \
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
HEALTHCHECK CMD java -cp /opt/sonatype/healthcheck Healthcheck || exit 1

# Change to nonroot user (uid 65532 - infosec standard)
USER 65532

ENV JAVA_OPTS=" -Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs "
ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

WORKDIR ${IQ_HOME}

# tini as init daemon for zombie process reaping
ENTRYPOINT ["/sbin/tini-static", "--"]
CMD [ "sh", "./start.sh" ]
