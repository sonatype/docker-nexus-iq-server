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
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6 AS builder
ARG TEMP="/tmp/work"
# Build parameters
ARG IQ_SERVER_VERSION=1.206.0-01
ARG IQ_SERVER_SHA256_AARCH=4a906004ecf0b79616245da07871defaedc3ebead70d6baf0151977757611c8c
ARG IQ_SERVER_SHA256_X86_64=18923bad4a06d7d5525520a344ecfcebd339b8cdd08582fd3053dd95f44338c2
ARG SONATYPE_WORK="/sonatype-work"

# hadolint ignore=DL3041,DL3040
RUN mkdir -p ${TEMP} && \
    microdnf update -y && \
    microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y gzip unzip tar shadow-utils findutils less rsync git-core openssh-clients which crypto-policies crypto-policies-scripts

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
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6 AS runtime-base

ARG IQ_SERVER_VERSION=1.206.0-01
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
  release="1.206.0" \
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

# hadolint ignore=DL3066
USER root

# For testing
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

# Remove packages not needed at runtime to reduce vulnerability surface
# microdnf remove handles dependency resolution for the bulk of removals:
# - Package management stack: microdnf, libdnf, librepo, librhsm, libsolv, libmodulemd
# - Package management deps: gobject-introspection, libpeas, json-glib, glib2, gpgme, gnupg2
# - crypto-policies-scripts + python3 stack: only needed for update-crypto-policies above
# - gnutls: TLS handled by openssl; nothing at runtime links against libgnutls (verified via ldd)
# - libxml2, sqlite-libs, libarchive, libusbx, rpm, rpm-libs: no runtime consumers
# - shadow-utils + libsemanage: shadow-utils' user-management binaries (useradd/userdel/usermod)
#   were only used at BUILD time to create the nexus user (line ~105 above). The image runs
#   as that user and never re-invokes them. libsemanage is shadow-utils' SELinux helper.
#   Listing them in microdnf's removal alongside bzip2-libs is what allows microdnf's
#   depsolver to remove bzip2-libs cleanly (libsemanage was the only declared requirer).
# - bzip2-libs: no runtime binary in the image links libbz2 once shadow-utils and libsemanage
#   are also removed (verified via ldd survey across /usr/bin, /usr/sbin, /usr/libexec,
#   /usr/lib64, and the JRE bundle).
# - xz-libs (liblzma): no runtime binary links liblzma once microdnf is gone (microdnf used
#   it for compressed-package-metadata reads during its own removal step). Verified via ldd.
# - openldap (libldap): no runtime binary links libldap. Image runs no LDAP server. The
#   original cascade-dep concern (libarchive -> libxml2) is moot because those are already
#   in the microdnf removal list.
# - libgcrypt: no runtime binary in the image links libgcrypt (verified via readelf -d
#   across all 951 ELF files in the built image: 0 NEEDED entries for libgcrypt.so). Java
#   uses BouncyCastle FIPS via JSSE for all cryptographic operations, not libgcrypt.
#   Present only as a transitive install-time dep of packages that are themselves removed
#   later in this block (systemd-libs pulls it in; systemd-libs is in the rpm -e list above).
# - cracklib, cracklib-dicts, gzip: transitively pulled in by pam. pam is removed via the
#   rpm -e --nodeps step above, which leaves cracklib and gzip as orphans. Nothing at runtime
#   invokes gzip (verified: no reference in start.sh or the IQ Server bundle).
#
# rpm -e --nodeps required only for packages with RPM-level deps that aren't actual runtime links:
# - gawk: krb5-libs has a scriptlet-only dep on it
# - systemd-libs: libfido2 depends on libudev (from systemd-libs) but both are unused at runtime
# - p11-kit, p11-kit-trust, libtasn1: only used at build time by update-ca-trust; at runtime
#   OpenSSL reads the PEM bundle directly without loading these (verified via LD_DEBUG)
# - libfido2: openssh-clients declares dep but ssh binary doesn't link against it (ssh-sk-helper does)
# - expat: only linked by /usr/libexec/git-core/git-http-push (legacy "dumb HTTP" git push,
#   WebDAV-based) and by /usr/bin/xmlwf (expat's own XML well-formedness checker).
#   Modern git over HTTPS uses git-remote-https -> git-remote-http, which does NOT link
#   libexpat (verified via ldd in the baseline image). No code path in IQ Server uses
#   dumb-HTTP git push, and the JRE parses XML with Xerces, not libexpat.
# - util-linux, util-linux-core, libblkid, libmount, libsmartcols, libuuid, libfdisk: no
#   runtime binary in the image links libblkid/libmount/libsmartcols/libuuid/libfdisk (0 NEEDED
#   entries across all ELFs, verified via readelf). openssh declares an RPM file-dep on
#   /sbin/nologin (owned by util-linux); --nodeps breaks that declared dep and we substitute
#   a symlink to /bin/false (which coreutils-single provides with identical exit behavior)
#   so any /etc/passwd shell entries referencing nologin still resolve.
# - sqlite-libs, xz-libs, bzip2-libs, libarchive, libxml2, rpm, rpm-libs: kept alive until the
#   last step because rpm binary itself dynamically links against them (or transitively through
#   librpm/librpmio -> libarchive -> libxml2); removed together in the final rpm -e call.
# hadolint ignore=DL3059
RUN rpm -e --nodeps gawk libfido2 systemd-libs p11-kit p11-kit-trust libtasn1 \
    pam libpwquality expat \
&& microdnf remove -y \
    crypto-policies-scripts python3 python3-libs python3-pip-wheel python3-setuptools-wheel \
    microdnf libdnf librepo librhsm libsolv libmodulemd \
    gobject-introspection libpeas json-glib glib2 \
    gpgme gnupg2 libusbx \
    gnutls \
    shadow-utils libsemanage openldap \
    libgcrypt \
    cracklib cracklib-dicts gzip \
&& rpm -e --nodeps util-linux util-linux-core libblkid libmount libsmartcols libuuid libfdisk \
&& ln -sf /bin/false /sbin/nologin \
&& rpm -e --nodeps rpm rpm-libs libarchive libxml2 sqlite-libs xz-libs bzip2-libs

# This is where we will store persistent data
VOLUME ${SONATYPE_WORK}
VOLUME ${LOGS_HOME}

# Expose the ports
EXPOSE 8070
EXPOSE 8071

# Wire up health check
HEALTHCHECK CMD ["curl", "--fail", "--silent", "--show-error", "http://localhost:8071/healthcheck"]

# Change to nexus user
# hadolint ignore=DL3066
USER nexus

ENV JAVA_OPTS=" -Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs "
ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

WORKDIR ${IQ_HOME}

CMD [ "sh", "./start.sh" ]

#
# ---------------------------------------------------------------------------
# Image validation (goss). These stages fork off `runtime-base` and contribute
# nothing to the shipped image.
#
# IMPORTANT: `runtime` must stay the LAST stage in this file. With no --target,
# BuildKit builds the last stage -- if an export stage were last, plain
# `docker build .` (and build_and_push_images.sh, which passes no --target)
# would build/push a scratch image containing only test results.
#
#   Run the tests and export JUnit XML to ./build/test-results:
#     docker buildx build --target test-results --no-cache-filter test \
#         --output type=local,dest=build/test-results .
#
#   In CI (CI env var set) all tests run and the build always succeeds so the
#   report is exported; Jenkins' junit step decides build status. Locally the
#   build fails on any test failure.
#     docker buildx build --target test-results --no-cache-filter test \
#         --build-arg CI --output type=local,dest=build/test-results .
# ---------------------------------------------------------------------------
#

# Fetch the goss binary for the target architecture. `builder` already has
# curl and tar, and runs on the target platform so uname -m is correct.
FROM builder AS goss-bin
ARG GOSS_VERSION=0.4.10
WORKDIR /tmp/goss
# hadolint ignore=DL4006
RUN case "$(uname -m)" in \
      x86_64)  GOSS_ARCH=x86_64 ;; \
      aarch64) GOSS_ARCH=arm64  ;; \
      *) echo "Unsupported architecture for goss: $(uname -m)" && exit 1 ;; \
    esac \
 && curl -fsSL -O "https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}/goss_${GOSS_VERSION}_linux_${GOSS_ARCH}.tar.gz" \
 && curl -fsSL -O "https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}/goss_${GOSS_VERSION}_SHA256SUMS" \
 && grep "goss_${GOSS_VERSION}_linux_${GOSS_ARCH}.tar.gz" "goss_${GOSS_VERSION}_SHA256SUMS" | sha256sum -c - \
 && tar -xzf "goss_${GOSS_VERSION}_linux_${GOSS_ARCH}.tar.gz" goss \
 && chmod 0755 goss

# Start IQ Server, wait for readiness, then validate the image.
FROM runtime-base AS test
# CI: when non-empty (Jenkins sets CI=true), always exit 0 so the results are
# exported and the pipeline's junit step owns pass/fail. Empty (local): fail the
# build on any test failure.
ARG CI=""
ARG IQ_HOME="/opt/sonatype/nexus-iq-server"
# NOT named GOSS_*: build args are exposed to RUN as environment variables, and
# goss itself reads GOSS_RETRY_TIMEOUT/GOSS_SLEEP from the environment. Naming
# these GOSS_* silently made the no-retry phase retry anyway.
ARG READY_TIMEOUT=300s
ARG READY_SLEEP=5s
# Pass --build-arg CACHEBUST=<unique> to force the tests to re-run; the test RUN
# has no file inputs, so BuildKit would otherwise serve a cached pass forever.
# Referenced inside the RUN below because BuildKit only rekeys on args a command
# actually uses. ARG is stage-scoped, so runtime-base's cache is unaffected.
ARG CACHEBUST=""
# hadolint ignore=DL3066
USER root
COPY --from=goss-bin /tmp/goss/goss /usr/local/bin/goss
COPY goss_wait.yaml goss.yaml /test/
RUN mkdir -p /results && chown nexus:nexus /results
# run the validation as the same user the image ships with
# hadolint ignore=DL3066
USER nexus
# Two phases, on purpose:
#   1. goss_wait.yaml -- only the asynchronously-created things, WITH retry.
#      This is the sole phase allowed to burn the retry window. Its output is a
#      LOG, not JUnit: with --retry-timeout goss re-emits its whole report per
#      attempt, so a junit-formatted retry produces N concatenated XML documents
#      interleaved with "Retrying in ..." text, which no JUnit parser accepts.
#      A readiness failure is reported via a synthesized single-testcase XML.
#   2. goss.yaml -- the full suite, exactly ONCE. --retry-timeout 0s is explicit
#      so it cannot be re-enabled by a stray environment variable. One attempt
#      means exactly one XML document, which is what Jenkins can parse.
# Phase 2 runs even when phase 1 times out, so a server that never starts still
# produces a full report of everything that failed rather than one timeout.
RUN echo "starting IQ Server (cachebust=${CACHEBUST:-none})"; \
    sh "${IQ_HOME}/start.sh" & \
    goss --gossfile /test/goss_wait.yaml validate \
        --format documentation \
        --retry-timeout "${READY_TIMEOUT}" \
        --sleep "${READY_SLEEP}" \
        > /results/readiness.log 2>&1; \
    wait_status=$?; \
    tail -30 /results/readiness.log; \
    goss --gossfile /test/goss.yaml validate \
        --format junit \
        --retry-timeout 0s \
        > /results/goss-results.xml; \
    status=$?; \
    cat /results/goss-results.xml; \
    if [ "${wait_status}" -ne 0 ]; then \
      echo "readiness gate FAILED (goss exit ${wait_status}): not ready within ${READY_TIMEOUT}"; \
      echo "--- healthcheck body ---" >> /results/readiness.log; \
      curl -s --max-time 10 http://localhost:8071/healthcheck >> /results/readiness.log 2>&1 || true; \
      { echo '<?xml version="1.0" encoding="UTF-8"?>'; \
        echo '<testsuite name="goss-readiness" tests="1" failures="1" errors="0" skipped="0">'; \
        echo '<testcase name="IQ Server becomes ready" classname="readiness">'; \
        printf '<failure message="readiness gate failed">goss exit %s after %s. See readiness.log</failure>\n' \
            "${wait_status}" "${READY_TIMEOUT}"; \
        echo '</testcase>'; \
        echo '</testsuite>'; \
      } > /results/readiness-results.xml; \
      status="${wait_status}"; \
    fi; \
    echo "${status}" > /results/exit-code; \
    if [ -n "${CI}" ]; then \
      echo "CI set: exporting results regardless of failures (exit ${status})"; \
      exit 0; \
    fi; \
    exit "${status}"

# Export target: `--output type=local` writes just the results to the host.
FROM scratch AS test-results
COPY --from=test /results/ /

# The shipped image. MUST be the last stage so it is the default build target.
# No instructions: a stage with no instructions inherits its base's layers and
# full image config (ENV, WORKDIR, USER, CMD, EXPOSE, VOLUME, LABEL,
# HEALTHCHECK), so this is byte-for-byte the runtime-base image.
FROM runtime-base AS runtime