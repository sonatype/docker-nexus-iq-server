#
# Copyright (c) 2011-present Sonatype, Inc. All rights reserved.
# Includes the third-party code listed at http://links.sonatype.com/products/clm/attributions.
# "Sonatype" is a trademark of Sonatype, Inc.
#

# === Packages stage ===
# Uses Alpine to:
# 1. Install runtime dependencies (git, tini, JRE) into an isolated root
# 2. Compile launcher.c and localcheck
# 3. Download the IQ Server artifacts from Maven (needs Maven for auth + SNAPSHOT resolution)
# 4. Create users, groups, and directory structure for the runtime image
# hadolint ignore=DL3006,DL3026
FROM alpine:3 AS packages

ARG IQ_SERVER_VERSION=1.203.0-SNAPSHOT
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
ARG SONATYPE_WORK="/sonatype-work"
ARG CONFIG_HOME="/etc/nexus-iq-server"
ARG LOGS_HOME="/var/log/nexus-iq-server"
ARG GID=1000
ARG UID=1000

# Build tools (not copied to runtime):
# - maven + openjdk17: artifact download
# - gcc + musl-dev: compile launcher.c (Alpine needs musl-dev for headers)
# - cargo: compile localcheck from submodule
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
# hadolint ignore=DL3018
RUN apk add --no-cache maven openjdk17 gcc musl-dev cargo

# Install runtime deps into isolated root.
# Runtime deps rationale:
# - tini-static: init daemon for zombie process reaping and signal forwarding
# - git: required for IQ Server SCM integrations
# - openjdk17-jre-headless: JVM (musl-native, available for amd64 + arm64)
# - libgcc: required by localcheck (Rust unwinding)
# hadolint ignore=DL3018
RUN apk add --no-cache --initdb --root /runtime-deps \
        --keys-dir /etc/apk/keys \
        --repositories-file /etc/apk/repositories \
        tini-static \
        git \
        openjdk17-jre-headless \
        libgcc

# Strip packages only needed during apk install scripts:
# - busybox, busybox-binsh, ssl_client: shell (pulled in by java-common/ca-certificates /bin/sh dep)
# - git-init-template: auto-installed with git, just sample hook scripts (not needed at runtime)
RUN for pkg in busybox busybox-binsh ssl_client git-init-template; do \
        apk info --root /runtime-deps -L $pkg 2>/dev/null \
            | tail -n +2 \
            | while read f; do [ -n "$f" ] && rm -f "/runtime-deps/$f"; done; \
        sed -i "/^P:${pkg}$/,/^$/d" /runtime-deps/lib/apk/db/installed; \
    done

# Copy and compile the launcher with build-time paths.
# Output to /runtime-deps/usr/bin/ because Alpine's /bin is a symlink to /usr/bin.
COPY launcher.c /tmp/launcher.c
RUN gcc -DIQ_HOME=\"${IQ_HOME}\" \
         -DCONFIG_HOME=\"${CONFIG_HOME}\" \
         -DLOGS_HOME=\"${LOGS_HOME}\" \
         -o /runtime-deps/usr/bin/launcher /tmp/launcher.c

# Compile localcheck from submodule for healthcheck.
# Localcheck is only deployed as a Wolfi package, which we can't use,
# so we compile it ourselves. Dynamic linking is fine (musl is in runtime).
COPY localcheck/ /tmp/localcheck/
RUN cd /tmp/localcheck && cargo build --release \
    && cp target/release/localcheck /runtime-deps/usr/bin/localcheck

# Create user/group entries in runtime root.
# Include root user (UID 0) for system compatibility, plus nexus user.
# Use nologin as shell since the runtime image has no shell anyway.
RUN mkdir -p /runtime-deps/etc \
    && echo "root:x:0:0:root:/root:/usr/sbin/nologin" > /runtime-deps/etc/passwd \
    && echo "nexus:x:${UID}:${GID}:Nexus IQ user:${IQ_HOME}:/usr/sbin/nologin" >> /runtime-deps/etc/passwd \
    && echo "root:x:0:" > /runtime-deps/etc/group \
    && echo "nexus:x:${GID}:" >> /runtime-deps/etc/group

# Create directory structure with proper ownership in runtime root
RUN mkdir -p /runtime-deps/opt/sonatype/nexus-iq-server \
    && mkdir -p /runtime-deps/sonatype-work \
    && mkdir -p /runtime-deps/etc/nexus-iq-server \
    && mkdir -p /runtime-deps/var/log/nexus-iq-server \
    && mkdir -p /runtime-deps/tmp \
    && chown -R ${UID}:${GID} /runtime-deps/opt/sonatype/nexus-iq-server \
    && chown -R ${UID}:${GID} /runtime-deps/sonatype-work \
    && chown -R ${UID}:${GID} /runtime-deps/etc/nexus-iq-server \
    && chown -R ${UID}:${GID} /runtime-deps/var/log/nexus-iq-server \
    && chown -R ${UID}:${GID} /runtime-deps/tmp \
    && chmod 1777 /runtime-deps/tmp

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
# FROM scratch: no shell, no package manager, no busybox.
# The isolated root becomes the entire filesystem.
FROM scratch

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
# - /usr/bin/launcher
# - /usr/bin/localcheck
# - /sbin/tini-static
# - /usr/lib/jvm/java-17-openjdk (JVM)
# - /opt/sonatype/nexus-iq-server (with server jar and jvm.options)
# - /etc/nexus-iq-server/config.yml
# - /var/log/nexus-iq-server directory
# - /sonatype-work directory
# - git and its dependencies
# - musl libc and other runtime libs
COPY --from=packages /runtime-deps/ /

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk

WORKDIR ${IQ_HOME}

# This is where we will store persistent data
VOLUME ${SONATYPE_WORK}
VOLUME ${LOGS_HOME}

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Wire up health check using localcheck (compiled in packages stage)
HEALTHCHECK CMD ["localcheck", "--port", "8071"]

# Change to nexus user (created in packages stage)
USER nexus

ENV JAVA_OPTS=" -Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs "
ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

# tini as init daemon for zombie process reaping and signal forwarding
ENTRYPOINT ["/sbin/tini-static", "--"]
CMD ["/usr/bin/launcher"]
