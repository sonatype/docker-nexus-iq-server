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
FROM sonatype.repo.sonatype.app/docker-all/ubi9/ubi-minimal:9.6 AS builder
ARG TEMP="/tmp/work"
# Build parameters
ARG IQ_SERVER_VERSION=1.206.0-01
ARG IQ_SERVER_SHA256_AARCH=4a906004ecf0b79616245da07871defaedc3ebead70d6baf0151977757611c8c
ARG IQ_SERVER_SHA256_X86_64=18923bad4a06d7d5525520a344ecfcebd339b8cdd08582fd3053dd95f44338c2
ARG SONATYPE_WORK="/sonatype-work"

# hadolint ignore=DL3041,DL3040
RUN mkdir -p ${TEMP} && \
    microdnf update -y && \
    microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y gzip unzip tar shadow-utils findutils less rsync git-core which crypto-policies crypto-policies-scripts

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

# Build openssh 10.4p1 from upstream source to pick up the fix for CVE-2026-60002 (and
# CVE-2026-59999, CVE-2026-60000, CVE-2023-51767). Red Hat's UBI9 openssh package
# (9.9p1-9.el9_8) has not backported these fixes, so the RH package cannot be used.
# Binaries are compiled with client-oriented flags (no PAM, no SELinux, no libedit) and
# installed into the final image at the same paths as the RH openssh-clients package so
# git-over-ssh works transparently.
# hadolint ignore=DL3026
FROM sonatype.repo.sonatype.app/docker-all/ubi9/ubi-minimal:9.6 AS openssh-builder
ARG OPENSSH_VERSION=10.4p1
ARG OPENSSH_SHA256=ef6026dd2aea8d56059638d5d3262902c892ceba9f88395835e0d06d3fb63238

# hadolint ignore=DL3041,DL3040
RUN microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y \
      gcc make tar gzip \
      openssl-devel zlib-devel \
 && microdnf clean all

WORKDIR /build
# hadolint ignore=DL4006
RUN curl -sSL "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz" -o openssh.tar.gz \
 && echo "${OPENSSH_SHA256}  openssh.tar.gz" | sha256sum -c - \
 && tar -xzf openssh.tar.gz

WORKDIR /build/openssh-${OPENSSH_VERSION}
RUN ./configure \
      --prefix=/usr \
      --sysconfdir=/etc/ssh \
      --libexecdir=/usr/libexec/openssh \
      --without-pam \
      --without-selinux \
      --without-libedit \
      --without-zlib-version-check \
 && make -j"$(nproc)" \
 && make DESTDIR=/build/dest install-nokeys \
 # Client-only install. sshd itself lands in /usr/sbin and is never COPYed; the paths
 # below are server-side or unusable-client artifacts under libexecdir/sysconfdir that
 # would otherwise leak in via the wholesale COPY of /usr/libexec/openssh and /etc/ssh.
 # ssh-keysign is upstream-installed setuid root but only supports HostbasedAuthentication
 # which needs host keys that install-nokeys never generates; moduli is only read by sshd.
 && rm -f /build/dest/usr/libexec/openssh/sshd-auth \
          /build/dest/usr/libexec/openssh/sshd-session \
          /build/dest/usr/libexec/openssh/sftp-server \
          /build/dest/usr/libexec/openssh/ssh-keysign \
          /build/dest/etc/ssh/moduli \
          /build/dest/etc/ssh/sshd_config

# hadolint ignore=DL3026
FROM sonatype.repo.sonatype.app/docker-all/ubi9/ubi-minimal:9.6

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

# git-core hard-depends on openssh + openssh-clients (and openssh-clients pulls in libfido2)
# on RHEL9, so those packages get installed here even though we do not list them and pass
# install_weak_deps=0. Remove them explicitly so the RPM DB no longer advertises the
# vulnerable 9.9p1-9.el9_8 build. The compiled openssh 10.4p1 client binaries copied in
# below take over the same /usr/bin, /usr/libexec/openssh, and /etc/ssh paths, so git-over-
# ssh keeps working transparently. Fixes CVE-2026-60002 and companion CVEs unpatched in
# RHEL9's openssh build. (CLM-42794)
# hadolint ignore=DL3041
RUN microdnf update -y \
&& microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y gzip shadow-utils findutils less git-core which crypto-policies crypto-policies-scripts \
&& microdnf clean all \
&& rpm -e --nodeps openssh-clients openssh libfido2

COPY --from=openssh-builder /build/dest/usr/bin/ /usr/bin/
COPY --from=openssh-builder /build/dest/usr/libexec/openssh/ /usr/libexec/openssh/
COPY --from=openssh-builder /build/dest/etc/ssh/ /etc/ssh/

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
# - systemd-libs: no runtime consumer once the packages it supported (originally libfido2 for
#   openssh-clients) are gone; kept in the removal list defensively
# - p11-kit, p11-kit-trust, libtasn1: only used at build time by update-ca-trust; at runtime
#   OpenSSL reads the PEM bundle directly without loading these (verified via LD_DEBUG)
# - expat: only linked by /usr/libexec/git-core/git-http-push (legacy "dumb HTTP" git push,
#   WebDAV-based) and by /usr/bin/xmlwf (expat's own XML well-formedness checker).
#   Modern git over HTTPS uses git-remote-https -> git-remote-http, which does NOT link
#   libexpat (verified via ldd in the baseline image). No code path in IQ Server uses
#   dumb-HTTP git push, and the JRE parses XML with Xerces, not libexpat.
# - util-linux, util-linux-core, libblkid, libmount, libsmartcols, libuuid, libfdisk: no
#   runtime binary in the image links libblkid/libmount/libsmartcols/libuuid/libfdisk (0 NEEDED
#   entries across all ELFs, verified via readelf). We substitute /sbin/nologin with a symlink
#   to /bin/false (which coreutils-single provides with identical exit behavior) so any
#   /etc/passwd shell entries referencing nologin still resolve after util-linux is removed.
# - sqlite-libs, xz-libs, bzip2-libs, libarchive, libxml2, rpm, rpm-libs: kept alive until the
#   last step because rpm binary itself dynamically links against them (or transitively through
#   librpm/librpmio -> libarchive -> libxml2); removed together in the final rpm -e call.
# hadolint ignore=DL3059
RUN rpm -e --nodeps gawk systemd-libs p11-kit p11-kit-trust libtasn1 \
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
