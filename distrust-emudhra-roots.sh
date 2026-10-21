#!/bin/sh
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
# Distrusts the roots that chain to the compromised eMudhra intermediate CAs
# (https://emudhra.we-have-a-problem.com/, CLM-55187):
#   emSign ECC Root CA - G3   (cross-signs emSign Root TLS CA - G3)
#   AAA Certificate Services  (Sectigo cross-signs; still in Temurin 17 cacerts)
# Roots are matched by SHA-256 fingerprint, not by keystore alias, so the script keeps
# working when a JDK renames its aliases.
#
# Usage:
#   distrust-emudhra-roots.sh jre   <IQ_HOME>
#       Deletes the roots from the bundled JRE's lib/security/cacerts, then fails if
#       either is still present.
#   distrust-emudhra-roots.sh check <IQ_HOME> <pem-bundle>...
#       Fails if any OS PEM bundle still contains either root. Uses the bundled keytool,
#       because not every image ships openssl.
#
# Drop the `jre` step once Temurin ships a cacerts without these roots, and the UBI
# blocklist step once RHEL ships a fixed ca-certificates. Keep `check` as a regression guard.
set -eu

FINGERPRINTS="86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B \
D7:A7:A0:FB:5D:7E:27:31:D7:71:E9:48:4E:BC:DE:F7:1D:5F:0C:3E:0A:29:48:78:2B:C8:3E:E0:EA:69:9E:F4"
# Unquoted on purpose: word splitting collapses the list to single spaces before tr.
# shellcheck disable=SC2086
FINGERPRINT_PATTERN=$(echo ${FINGERPRINTS} | tr ' ' '|')

mode=$1
iq_home=$2
shift 2
keytool="${iq_home}/bin/keytool"
cacerts="${iq_home}/lib/security/cacerts"

list_cacerts() {
  "${keytool}" -list -v -keystore "${cacerts}" -storepass changeit 2>/dev/null
}

case "${mode}" in
  jre)
    # Plain assignment so `set -e` aborts if keytool cannot read the keystore.
    all_entries=$(list_cacerts)
    entries=$(echo "${all_entries}" | grep -E '^Alias name:|SHA256:')
    for fingerprint in ${FINGERPRINTS}; do
      alias=$(echo "${entries}" | grep -B1 "${fingerprint}" | sed -n 's/^Alias name: //p')
      if [ -n "${alias}" ]; then
        "${keytool}" -delete -noprompt -keystore "${cacerts}" -storepass changeit -alias "${alias}" 2>/dev/null
        echo "Removed '${alias}' from ${cacerts}"
      fi
    done
    if list_cacerts | grep -qE "${FINGERPRINT_PATTERN}"; then
      echo "ERROR: ${cacerts} still trusts a compromised eMudhra root" >&2
      exit 1
    fi
    ;;
  check)
    for bundle in "$@"; do
      # A missing or unreadable bundle must fail the check, not pass it vacuously.
      if ! certs=$("${keytool}" -printcert -file "${bundle}" 2>/dev/null) || [ -z "${certs}" ]; then
        echo "ERROR: could not read any certificate from ${bundle}" >&2
        exit 1
      fi
      if echo "${certs}" | grep -qE "${FINGERPRINT_PATTERN}"; then
        echo "ERROR: ${bundle} still trusts a compromised eMudhra root" >&2
        exit 1
      fi
      echo "${bundle} does not trust the compromised eMudhra roots"
    done
    ;;
  *)
    echo "usage: $0 jre <IQ_HOME> | check <IQ_HOME> <pem-bundle>..." >&2
    exit 2
    ;;
esac
