#!/usr/bin/env bash
#
# Copyright (c) 2011-present Sonatype, Inc. All rights reserved.
# Includes the third-party code listed at http://links.sonatype.com/products/clm/attributions.
# "Sonatype" is a trademark of Sonatype, Inc.
#

# prerequisites:
# * software:
#   * https://github.com/redhat-openshift-ecosystem/openshift-preflight
#   * https://podman.io/
# * environment variables:
#   * VERSION of the docker image  to build for the red hat registry
#   * REGISTRY_LOGIN from Red Hat config page for image
#   * REGISTRY_PASSWORD from Red Hat config page for image
#   * API_TOKEN from red hat token/account page for API access

set -x # log commands as they execute
set -e # stop execution on the first failed command

DOCKERFILE=Dockerfile.rh

# from config/scanning page at red hat
CERT_PROJECT_ID=5e61602c2f3c1acdd05f61d3

REPOSITORY="quay.io"
IMAGE_TAG="${REPOSITORY}/redhat-isv-containers/${CERT_PROJECT_ID}:${TAG}"
IMAGE_LATEST="${REPOSITORY}/redhat-isv-containers/${CERT_PROJECT_ID}:latest"

AUTHFILE="${HOME}/.docker/config.json"

docker build -f "${DOCKERFILE}" --build-arg IQ_SERVER_VERSION="${VERSION}" --build-arg IQ_SERVER_SHA256="${CHECKSUM}" --build-arg IQ_RELEASE="${RELEASE}" -t "${IMAGE_TAG}" .
docker tag "${IMAGE_TAG}" "${IMAGE_LATEST}"

docker login "${REPOSITORY}" \
       -u "${REGISTRY_LOGIN}" \
       --password "${REGISTRY_PASSWORD}"

docker push "${IMAGE_TAG}"
docker push "${IMAGE_LATEST}"

preflight check container \
          "${IMAGE_TAG}" \
          --docker-config="${AUTHFILE}" \
          --submit \
          --certification-component-id="${CERT_PROJECT_ID}" \
          --pyxis-api-token="${API_TOKEN}"
