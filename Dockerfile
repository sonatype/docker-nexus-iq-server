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
# ENV iqVersion=""
# ENV iqSha256=""
# ENV javaUrl=""
# ENV javaSha256=""

# Mandatory parameters. Docker needs to know volume mount point and location of startup script.
ENV sonatypeWork="/sonatype-work"
ENV installDir="/opt/sonatype/nexus-iq-server/"

ADD solo.json.erb /var/chef/solo.json.erb

# Install using chef-solo
RUN curl -L https://www.getchef.com/chef/install.sh | bash && \
    /opt/chef/embedded/bin/erb /var/chef/solo.json.erb > /var/chef/solo.json && \
    chef-solo --recipe-url https://s3.amazonaws.com/int-public/nexus-iq-server-cookbook.tar.gz --json-attributes /var/chef/solo.json

VOLUME ${sonatypeWork}

EXPOSE 8070
EXPOSE 8071

USER nexus

CMD ["sh", "-c", "${installDir}/start-nexus-iq-server.sh"]
