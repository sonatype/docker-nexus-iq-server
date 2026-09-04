#!/usr/bin/env bash
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

set -o nounset                              # Treat unset variables as an error

# Enable for debugging
set -x
set -e

# General args about the build.
#
# Per-variant releases: set DOCKERFILE to the variant Dockerfile and TAG_SUFFIX to the
# variant tag suffix (e.g. -hardened). The default (empty TAG_SUFFIX + default Dockerfile)
# produces the primary ubi image. Callers can then pass unadorned tag names ("1.206.0",
# "latest") and get variant-suffixed tags out (1.206.0-hardened, latest-hardened) without
# duplicating the suffix at every callsite.
#
# TAG_SUFFIX also gates the temporary per-arch scratch tags (`arm64-latest`/`amd64-latest`)
# that this script pushes, manifests from, and then deletes. Without the suffix, parallel
# releases of different variants that all export the same OCI_REPO could cross-assemble a
# multi-arch manifest -- the manifest step here would combine one variant's arm64 image
# with another variant's amd64 image if both were mid-flight. Suffixing keeps each variant
# in its own lane. (Jenkinsfile.slim.release embeds the -slim suffix inline in the tags it
# passes to this script and does not use TAG_SUFFIX; it is unaffected by the change.)
REPO="${OCI_REPO}"
REF="${OCI_REGISTRY:-docker.io}/${REPO}"
TAGS="$@"
DOCKERFILE=${DOCKERFILE:-Dockerfile}
TAG_SUFFIX="${TAG_SUFFIX:-}"

if [ -n "${TAG_SUFFIX}" ]; then
  SUFFIXED_TAGS=""
  for TAG in $TAGS; do
    SUFFIXED_TAGS="${SUFFIXED_TAGS} ${TAG}${TAG_SUFFIX}"
  done
  # Strip the leading space introduced by the concat.
  TAGS="${SUFFIXED_TAGS# }"
fi

ARM64_TAG="arm64-latest${TAG_SUFFIX}"
AMD64_TAG="amd64-latest${TAG_SUFFIX}"

echo "Building images"
docker buildx build --progress=plain --platform=linux/arm64 -f ${DOCKERFILE} --push --provenance=false --tag "${REF}:${ARM64_TAG}" .
docker buildx build --progress=plain --platform=linux/amd64 -f ${DOCKERFILE} --push --provenance=false --tag "${REF}:${AMD64_TAG}" .

for TAG in $TAGS; do
  echo "Creating manifest"
  docker manifest create "${REF}:${TAG}" "${REF}:${ARM64_TAG}" "${REF}:${AMD64_TAG}" --amend

  echo "Inspecting manifest"
  docker manifest inspect "${REF}:${TAG}"

  echo "Pushing manifest"
  docker manifest push "${REF}:${TAG}" --purge
done

# Delete the temporary tags
HUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d "{\"username\": \"${DOCKERHUB_API_USERNAME}\", \"password\": \"${DOCKERHUB_API_PASSWORD}\"}" https://hub.docker.com/v2/users/login/ | jq -r .token)
curl "https://hub.docker.com/v2/repositories/${REPO}/tags/${ARM64_TAG}" -H "Authorization: Bearer ${HUB_TOKEN}" -X DELETE
curl "https://hub.docker.com/v2/repositories/${REPO}/tags/${AMD64_TAG}" -H "Authorization: Bearer ${HUB_TOKEN}" -X DELETE

echo "Done!"
