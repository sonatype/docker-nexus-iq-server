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

FROM       centos:centos7

MAINTAINER Sonatype <cloud-ops@sonatype.com>

LABEL vendor=Sonatype \
  com.sonatype.license="Apache License, Version 2.0" \
  com.sonatype.name="Nexus IQ Server image"

# Optional parameters. Uncomment to override default:
# ENV IQ_SERVER_VERSION=""
# ENV IQ_SERVER_SHA256=""
# ENV JAVA_URL=""
# ENV JAVA_SHA256=""

# Mandatory parameters. Docker needs to know volume mount point and location of startup script.
ENV SONATYPE_WORK="/sonatype-work"
ENV IQ_HOME="/opt/sonatype/nexus-iq-server/"
ENV IQ_SERVER_COOKBOOK_VERSION="release-0.2.0-01"

ADD solo.json.erb /var/chef/solo.json.erb

# Install using chef-solo
RUN curl -L https://www.getchef.com/chef/install.sh | bash \
    && /opt/chef/embedded/bin/erb /var/chef/solo.json.erb > /var/chef/solo.json \
    && chef-solo \
       --recipe-url https://github.com/sonatype/chef-nexus-iq-server/releases/download/${IQ_SERVER_COOKBOOK_VERSION}/chef-nexus-iq-server.tar.gz \
       --json-attributes /var/chef/solo.json \
    && rpm -qa *chef* | xargs rpm -e \
    && rpm --rebuilddb \
    && rm -rf /etc/chef \
    && rm -rf /opt/chefdk \
    && rm -rf /var/cache/yum \
    && rm -rf /var/chef

VOLUME ${SONATYPE_WORK}

EXPOSE 8070
EXPOSE 8071

USER nexus

CMD ["sh", "-c", "${IQ_HOME}/start-nexus-iq-server.sh"]
