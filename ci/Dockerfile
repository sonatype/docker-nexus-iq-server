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

FROM quay.io/podman/stable

USER root

# For testing
RUN dnf update -y \
&& dnf install -y git wget \
&& dnf clean all

# ENV SONATYPE_INTERNAL_HOST_SYSTEM=Docker

# get preflight
RUN wget -q https://github.com/redhat-openshift-ecosystem/openshift-preflight/releases/download/1.3.1/preflight-linux-amd64 \
  && chmod 755 preflight-linux-amd64 \
  && mv preflight-linux-amd64 /usr/bin/preflight

VOLUME /workspace

WORKDIR /workspace
