#!/usr/bin/env bash

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

# prerequisites:
# * software:
#   * https://github.com/redhat-openshift-ecosystem/openshift-preflight
#   * https://podman.io/
# * environment variables:
#   * IMAGE name of the docker image to build for the red hat registry
#   * VERSION of the docker image  to build for the red hat registry
#   * PROJECT_ID from red hat config page for image
#   * CERT_PROJECT_ID from the url to red hat config page for image
#   * REGISTRY_PASSWORD from red hat config page for image
#   * API_TOKEN from red hat token/account page for API access
#   * DOCKERFILE to use to build the red hat image

set -x # log commands as they execute
set -e # stop execution on the first failed command

AUTHFILE=temp-auth.json

podman login scan.connect.redhat.com -u unused \
       --password "${REGISTRY_PASSWORD}" \
       --authfile "${AUTHFILE}"

podman build \
       -f "${DOCKERFILE}" \
       -t "scan.connect.redhat.com/${PROJECT_ID}/${IMAGE}:${VERSION}"

podman push "scan.connect.redhat.com/${PROJECT_ID}/${IMAGE}:${VERSION}"

preflight check container \
          "scan.connect.redhat.com/${PROJECT_ID}/${IMAGE}:${VERSION}" \
          --docker-config="${AUTHFILE}" \
          --submit \
          --certification-project-id="${CERT_PROJECT_ID}" \
          --pyxis-api-token="${API_TOKEN}"

rm $AUTHFILE
