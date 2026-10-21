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

# Distrusts the compromised eMudhra intermediate CAs (https://emudhra.we-have-a-problem.com/,
# CLM-55187) in a JRE, and guards OS PEM bundles against the roots they chain to.
#
# JRE: appends the SHA-256 fingerprints of the 16 impacted intermediates (the advisory's
# impacted-intermediates.json) to <JAVA_HOME>/lib/security/blocked.certs. The JRE rejects a
# blocked certificate whatever trust store is configured, so this also covers a
# -Djavax.net.ssl.trustStore override, and the roots keep working for other certificates.
#
# OS bundles: openssl/libcurl/git have no blocklist, so the roots themselves must be gone:
#   emSign ECC Root CA - G3   (cross-signs emSign Root TLS CA - G3)
#   AAA Certificate Services  (Sectigo cross-signs)
#
# Usage:
#   distrust-emudhra-roots.sh jre   <JAVA_HOME>
#       Appends the missing intermediate fingerprints to blocked.certs (idempotent), then
#       fails if any is still missing.
#   distrust-emudhra-roots.sh check <JAVA_HOME> <pem-bundle>...
#       Fails if any OS PEM bundle still contains either root. Uses the JRE's keytool,
#       because not every image ships openssl.
#
# Drop the `jre` step once the JRE ships these fingerprints itself, and keep `check` as a
# regression guard.
set -eu

INTERMEDIATES="\
42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493 \
45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE \
98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B \
5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699 \
E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838 \
579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512 \
0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19 \
62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72 \
CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F \
7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489 \
432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3 \
FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F \
9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4 \
A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8 \
4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1 \
84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD"

ROOTS_PATTERN="86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B|\
D7:A7:A0:FB:5D:7E:27:31:D7:71:E9:48:4E:BC:DE:F7:1D:5F:0C:3E:0A:29:48:78:2B:C8:3E:E0:EA:69:9E:F4"

usage() {
  echo "usage: $0 jre <JAVA_HOME> | check <JAVA_HOME> <pem-bundle>..." >&2
  exit 2
}

[ $# -ge 2 ] || usage
mode=$1
java_home=$2
shift 2
blocked="${java_home}/lib/security/blocked.certs"

case "${mode}" in
  jre)
    if ! grep -q '^Algorithm=SHA-256$' "${blocked}"; then
      echo "ERROR: ${blocked} is missing or is not a SHA-256 blocklist" >&2
      exit 1
    fi
    # Ensure the file ends in a newline, so the first appended entry gets its own line.
    if [ -n "$(tail -c 1 "${blocked}")" ]; then
      echo >> "${blocked}"
    fi
    added=0
    for fingerprint in ${INTERMEDIATES}; do
      if ! grep -qx "${fingerprint}" "${blocked}"; then
        echo "${fingerprint}" >> "${blocked}"
        added=$((added + 1))
      fi
    done
    for fingerprint in ${INTERMEDIATES}; do
      if ! grep -qx "${fingerprint}" "${blocked}"; then
        echo "ERROR: ${blocked} does not block ${fingerprint}" >&2
        exit 1
      fi
    done
    echo "Blocked the 16 compromised eMudhra intermediates in ${blocked} (${added} added)"
    ;;
  check)
    [ $# -ge 1 ] || usage
    for bundle in "$@"; do
      # A missing or unreadable bundle must fail the check, not pass it vacuously.
      if ! certs=$("${java_home}/bin/keytool" -printcert -file "${bundle}" 2>/dev/null) || [ -z "${certs}" ]; then
        echo "ERROR: could not read any certificate from ${bundle}" >&2
        exit 1
      fi
      if echo "${certs}" | grep -qE "${ROOTS_PATTERN}"; then
        echo "ERROR: ${bundle} still trusts a compromised eMudhra root" >&2
        exit 1
      fi
      echo "${bundle} does not trust the compromised eMudhra roots"
    done
    ;;
  *)
    usage
    ;;
esac
