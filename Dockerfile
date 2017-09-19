# Copyright (c) 2016-present Sonatype, Inc.
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
  com.sonatype.name="Nexus IQ base image"

# Optional parameters. Assign empty string to use default.
ENV iqVersion=""
ENV iqSha256=""
ENV javaUrl=""
ENV javaSha256=""

# Mandatory paramters. Docker needs to know volume mountpoint and location of startup script.
ENV sonatypeWork="/sonatype-work"
ENV installDir="/opt/sonatype/nexus-iq-server/"

# Create chef configuration file solo.json
RUN mkdir -p /var/chef/ && \
    echo "{ \"run_list\": [\"recipe[nexus-iq-server::docker]\"], " > /var/chef/solo.json && \
    echo "\"java\": { \"jdk_version\": 8, \"install_flavor\": \"oracle\", \"oracle\": { \"accept_oracle_download_terms\": true }" >> /var/chef/solo.json && \
    if [ "x${javaUrl}" != "x" ] ; then echo ", \"jdk\": { \"8\": { \"x86_64\": { \"url\": \"${javaUrl}\", \"checksum\": \"${javaSha256}\" } } }" >> /var/chef/solo.json ; fi && \
    echo "}" >>/var/chef/solo.json && \
    echo ",\"nexus-iq-server\": {" >> /var/chef/solo.json && \
    if [ "x${iqVersion}" != "x" ] ; then echo "\"version\": \"${iqVersion}\", \"checksum\": \"${iqSha256}\"," >> /var/chef/solo.json ; fi && \
    if [ "x${installDir}" != "x" ] ; then echo "\"install_dir\": \"${installDir}\"," >> /var/chef/solo.json ; fi && \
    echo "\"config\": { \"sonatypeWork\": \"${sonatypeWork}\" } } }" >> /var/chef/solo.json && \

# Install using chef-solo
    curl -L https://www.getchef.com/chef/install.sh | bash && \
    chef-solo --recipe-url https://s3.amazonaws.com/int-public/nexus-iq-server-cookbook.tar.gz --json-attributes /var/chef/solo.json

VOLUME ${sonatypeWork}

EXPOSE 8070
EXPOSE 8071

USER nexus

CMD ["sh", "-c", "${installDir}/start-nexus-iq-server.sh"]
