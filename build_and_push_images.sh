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

# This script expects that docker trust keys have already been loaded

set -o nounset                              # Treat unset variables as an error

# Enable for debugging
set -x
set -e

# This is used by the notary tool for auth
export NOTARY_AUTH="$(printf "${DOCKERHUB_API_USERNAME}:${DOCKERHUB_API_PASSWORD}" | base64)"

TRUST_DIR="${TRUST_DIR:-${HOME}/.docker/trust/}"

# General args about the build
REPO="${OCI_REPO}"
REF="${OCI_REGISTRY:-docker.io}/${REPO}"
TAGS="$@"
DOCKERFILE=${DOCKERFILE:-Dockerfile}

ARM64_TAG=arm64-latest
AMD64_TAG=amd64-latest

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

  echo "Getting docker token"
  DOCKER_TOKEN="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPO}:pull" -H "Authorization: Basic ${NOTARY_AUTH}" | jq -r '.token')"

  echo "Parsing content-length and sha256 hash from manifest list response headers"
  HEADERS=$(curl -I -s -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' https://registry-1.docker.io/v2/${REPO}/manifests/${TAG} -H "Authorization: Bearer ${DOCKER_TOKEN}" -XGET)
  BYTES_SIZE=$(echo "$HEADERS" | grep -i 'content-length' | awk '{print $2}' | tr -d '\r')
  SHA_256=$(echo "$HEADERS" | grep -i 'docker-content-digest' | awk '{print $2}' | tr -d '\r' | sed 's/^sha256://')

  echo "Manifest SHA-256: ${SHA_256}"
  echo "Manifest-inspect BYTES: ${BYTES_SIZE}"
  echo "Sign ${SHA_256} with the notary"

  echo "Signing the manifest list"
  notary -D -s https://notary.docker.io -d "${TRUST_DIR}" addhash "${REF}" "${TAG}" "${BYTES_SIZE}" --sha256 "${SHA_256}" --publish --verbose --roles targets/sonatype --roles targets
  docker trust inspect --pretty "${REF}:${TAG}"
done

# Delete the temporary tags
HUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d "{\"username\": \"${DOCKERHUB_API_USERNAME}\", \"password\": \"${DOCKERHUB_API_PASSWORD}\"}" https://hub.docker.com/v2/users/login/ | jq -r .token)
curl "https://hub.docker.com/v2/repositories/${REPO}/tags/${ARM64_TAG}" -H "Authorization: Bearer ${HUB_TOKEN}" -X DELETE
curl "https://hub.docker.com/v2/repositories/${REPO}/tags/${AMD64_TAG}" -H "Authorization: Bearer ${HUB_TOKEN}" -X DELETE


unset NOTARY_AUTH

echo "Done!"
