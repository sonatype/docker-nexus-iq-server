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

# Red Hat Hardened Images (Hummingbird) — base swap per CLM-42750.
# Digest pinned to the multi-arch index snapshot captured on 2026-07-23 for the
# `hi/core-runtime:latest-builder` tag. Bump this digest by re-running
# `docker buildx imagetools inspect registry.access.redhat.com/hi/core-runtime:latest-builder`
# and copying the top-level `Digest:` value.
# hadolint ignore=DL3026
FROM registry.access.redhat.com/hi/core-runtime@sha256:e8de00220ad4953bf99b464e84008b41d2642e70618c0015733e6570b082558f AS builder

# hi/core-runtime defaults to non-root user 65532; the builder stage needs
# root to run microdnf. Switch here rather than in the base.
USER root

ARG TEMP="/tmp/work"
# Build parameters
ARG IQ_SERVER_VERSION=1.205.0-03
ARG IQ_SERVER_SHA256_AARCH=5dc7782190512e4aa512bc070b3b0b5841d7938ac7b06e60269441c707f7a876
ARG IQ_SERVER_SHA256_X86_64=232290398ef4958ba7af6d5438ac4ab88c67285037d7be481b1f5b09a9c1ead4
ARG SONATYPE_WORK="/sonatype-work"

# unzip and rsync are intentionally NOT installed — neither is available in the
# Hummingbird repo and neither is invoked by the build (jar extraction uses
# java.util.zip; nothing rsyncs). curl and tar are already in the base builder.
# hadolint ignore=DL3041,DL3040
RUN mkdir -p ${TEMP} && \
    microdnf update -y && \
    microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y gzip tar shadow-utils findutils less git-core openssh-clients which crypto-policies crypto-policies-scripts

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
FROM registry.access.redhat.com/hi/core-runtime@sha256:e8de00220ad4953bf99b464e84008b41d2642e70618c0015733e6570b082558f

ARG IQ_SERVER_VERSION=1.205.0-03
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
  release="1.205.0" \
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

# Runtime packages. The Hummingbird base image already ships
# openssl-fips-provider-upstream + fips.so, so OS-level FIPS is available
# out-of-the-box for the native code paths in openssh-clients / git / libcurl.
# IQ Server's own FIPS mode (BouncyCastle FIPS) activates via the
# FIPS_MODE_ENABLED=true env var at runtime, independently of the OS
# provider. See CLM-42750 §5.
# hadolint ignore=DL3041
RUN microdnf update -y \
&& microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y gzip shadow-utils findutils less git-core openssh-clients which crypto-policies crypto-policies-scripts \
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

# Remove packages not needed at runtime to reduce vulnerability surface.
# The list below adapts the audited-UBI9 removal set to the Hummingbird base:
# every package we removed on UBI9 is either (a) removed here, (b) not
# installed in the Hummingbird base to begin with (so removal is redundant),
# or (c) named differently in Hummingbird (microdnf → dnf5; libdnf → libdnf5).
#
# NEVER remove these from the runtime image (called out for future auditors):
# - openssl-fips-provider-upstream + openssl-libs (both preinstalled in the
#   Hummingbird base): provide OS-level FIPS-validated OpenSSL (fips.so).
#   Activated on demand via `update-crypto-policies --set FIPS` at container
#   start. IQ Server's own FIPS mode (BouncyCastle FIPS) activates via
#   FIPS_MODE_ENABLED=true and doesn't require the OS provider, but keeping
#   these ensures native code paths (ssh/git/curl) can be FIPS-compliant too.
#
# Packages NOT removed here because they aren't installed in the Hummingbird
# base (differences vs. UBI9): gawk, libpwquality, python3-pip-wheel,
# python3-setuptools-wheel, microdnf, libdnf, librhsm, gobject-introspection,
# libpeas, json-glib, gpgme, gnupg2, libusbx, gnutls, libgcrypt, cracklib,
# cracklib-dicts, util-linux, util-linux-core, libfdisk.
#
# microdnf-equivalent (dnf5) removal handles dependency resolution for the bulk:
# - Package management stack: dnf5, libdnf5, libdnf5-cli, librepo, libsolv, libmodulemd
# - crypto-policies-scripts + python3 stack: only needed for update-crypto-policies above
# - libxml2, sqlite-libs, libarchive, rpm, rpm-libs, rpm-sequoia: no runtime consumers
# - shadow-utils + libsemanage: shadow-utils' user-management binaries were only used
#   at BUILD time to create the nexus user. The image runs as that user and never
#   re-invokes them. libsemanage is shadow-utils' SELinux helper.
# - bzip2-libs, xz-libs, zstd (libzstd): compression libs only reachable via rpm/dnf5
#   at build time. No runtime binary links them once package management is gone.
# - openldap (libldap): KEPT in the Hummingbird build. Hummingbird's libcurl
#   is compiled with LDAP support and dynamically links libldap/liblber. Since
#   IQ Server's healthcheck (`curl --fail ...`) is our only in-image use of
#   curl, removing openldap would break healthcheck. On UBI9 the same libcurl
#   did not link libldap (different build config), which is why the UBI9
#   strip block removed openldap.
# - gzip: transitively pulled in by other packages; nothing at runtime invokes gzip
#   (verified: no reference in start.sh or the IQ Server bundle).
# - glib2: no runtime binary links libglib once package management is gone.
#
# rpm -e --nodeps required only for packages with RPM-level deps that aren't actual runtime links:
# - systemd-libs: KEPT in the Hummingbird build. Hummingbird's coreutils-single
#   (the multi-call binary that provides ls/cat/cp/mkdir/ln/etc.) is compiled
#   with libsystemd support and dynamically links libsystemd.so.0. Removing
#   systemd-libs breaks every basic command in the container. On UBI9 the
#   same binary did not link libsystemd (different build config), which is
#   why the UBI9 strip block removed systemd-libs.
# - p11-kit, p11-kit-trust, libtasn1: only used at build time by update-ca-trust; at runtime
#   OpenSSL reads the PEM bundle directly without loading these
# - libfido2: KEPT in the Hummingbird build. Hummingbird's libcurl and libssh
#   both dynamically link libfido2.so.1. Since IQ Server's healthcheck uses
#   curl, removing libfido2 breaks the healthcheck. On UBI9 the same libcurl
#   did not link libfido2 (different build config), which is why the UBI9
#   strip block removed it.
# - expat: only linked by /usr/libexec/git-core/git-http-push (legacy dumb-HTTP git push,
#   WebDAV-based). Modern git over HTTPS uses git-remote-https which does NOT link libexpat.
#   No code path in IQ Server uses dumb-HTTP git push, and the JRE parses XML with Xerces.
# - pam: interactive login stack; the nexus user is a system daemon account with
#   /bin/false as its shell — pam is never invoked at runtime.
# - libblkid, libmount, libsmartcols, libuuid: no runtime binary links these (0 NEEDED
#   entries across all ELFs when audited on UBI9). openssh declares an RPM file-dep on
#   /sbin/nologin (owned by util-linux on UBI9 / coreutils-single on Hummingbird);
#   --nodeps breaks that declared dep and we substitute a symlink to /bin/false.
# - sqlite-libs, xz-libs, libzstd, bzip2-libs, libarchive, libxml2, rpm, rpm-libs,
#   rpm-sequoia: kept alive until the last step because rpm binary itself dynamically
#   links against them (or transitively); removed together in the final rpm -e call.
# hadolint ignore=DL3059
# Order matters:
# 1. microdnf remove (uses dnf5) while its dependencies (libsystemd, librepo,
#    libsolv, libmodulemd, glib2, libdnf5) are still installed. Only remove
#    things the depsolver is happy to remove — packages the depsolver knows
#    are safe to unlink.
# 2. rpm -e --nodeps for packages with RPM-level file/scriptlet deps that
#    aren't actual runtime links (audited on UBI9, same logic applies here).
# 3. Final rpm -e --nodeps cascade for the package-management stack itself —
#    dnf5 is a "protected package" that refuses to remove itself; librepo /
#    libsolv / libmodulemd / glib2 / libdnf5 are its runtime deps and must
#    outlive it. All go together in this final step.
RUN ln -sf /bin/false /sbin/nologin \
&& microdnf remove -y \
    crypto-policies-scripts python3 python3-libs \
    shadow-utils libsemanage \
    gzip \
&& rpm -e --nodeps p11-kit p11-kit-trust libtasn1 \
    pam-libs expat \
&& rpm -e --nodeps libblkid libmount libsmartcols libuuid \
&& rpm -e --nodeps dnf5 libdnf5-cli libdnf5 librepo libsolv libmodulemd glib2 \
    rpm rpm-libs rpm-sequoia libarchive libxml2-16 sqlite-libs xz-libs libzstd bzip2-libs

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
