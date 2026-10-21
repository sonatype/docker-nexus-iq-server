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
# JRE: the SHA-256 fingerprints of the 16 impacted intermediates (the advisory's
# impacted-intermediates.json) and of the 4 roots they chain to (roots.json) are appended to
# <JAVA_HOME>/lib/security/blocked.certs, and the roots are also deleted from the JRE's cacerts.
#   - blocked.certs applies whatever trust store is configured, including a custom
#     -Djavax.net.ssl.trustStore, and the JDK checks the trust anchor against it too.
#   - Blocking the intermediates alone is not enough: blocked.certs matches certificate bytes, and
#     a signature can be re-encoded without any private key (ECDSA s -> n-s; RSA without the
#     signatureAlgorithm NULL), giving the same intermediate a fingerprint the list lacks. A root
#     comes from the trust store, not from the server, so blocking it stops every such copy.
#
# OS bundles: openssl/libcurl/git apply no blocklist to certificates a server sends, so the roots
# themselves must be gone from the PEM bundle.
#
# Usage:
#   distrust-emudhra-roots.sh jre   <JAVA_HOME> [<cacerts>]
#       Appends the missing intermediate and root fingerprints to blocked.certs and deletes the
#       roots from <cacerts> (default <JAVA_HOME>/lib/security/cacerts), then fails if any
#       fingerprint is missing or any root is still in <cacerts>. Idempotent. Pass <cacerts>
#       explicitly when the default is a symlink, so the right file is edited.
#   distrust-emudhra-roots.sh check <JAVA_HOME> <pem-bundle>...
#       Fails if any OS PEM bundle still contains one of the roots. Uses the JRE's keytool,
#       because not every image ships openssl. It does not read the JRE: `jre` verifies its own
#       changes, and EmudhraChainCheck.java proves the JRE rejects the advisory's chains.
#
# Keep both modes until the JRE and OS packages ship these changes themselves; `check`
# stays useful afterwards as a regression guard.
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

# The same four roots as ROOTS_PATTERN below, in blocked.certs format.
ROOTS="\
86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B \
D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4 \
7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D \
F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5"

# emSign ECC Root CA - G3, AAA Certificate Services, emSign Root TLS CA - G3,
# emSign Root CS CA - G3 (keytool's colon-separated SHA-256 format).
ROOTS_PATTERN="86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B|\
D7:A7:A0:FB:5D:7E:27:31:D7:71:E9:48:4E:BC:DE:F7:1D:5F:0C:3E:0A:29:48:78:2B:C8:3E:E0:EA:69:9E:F4|\
7D:D7:8D:5F:4F:13:45:9A:83:DF:F9:AB:BB:A6:2E:DB:AF:6F:2D:10:2B:F2:57:FD:71:2F:4D:9F:27:46:ED:8D|\
F2:ED:AA:FF:3D:9B:70:1F:B4:D1:4C:9F:28:5F:8C:0B:AD:90:FC:3B:CC:1F:A0:7D:47:F4:71:8E:DA:BA:34:A5"

usage() {
  echo "usage: $0 jre <JAVA_HOME> [<cacerts>] | check <JAVA_HOME> <pem-bundle>..." >&2
  exit 2
}

[ $# -ge 2 ] || usage
# Fail closed: without grep, `if ... | grep -q` reads as "no match" and a vulnerable store
# would pass.
for tool in grep sed tail; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: ${tool} is required" >&2
    exit 1
  fi
done
mode=$1
java_home=$2
shift 2
keytool="${java_home}/bin/keytool"

case "${mode}" in
  jre)
    [ $# -le 1 ] || usage
    blocked="${java_home}/lib/security/blocked.certs"
    cacerts="${1:-${java_home}/lib/security/cacerts}"
    if [ $# -eq 0 ] && [ -L "${cacerts}" ]; then
      echo "ERROR: ${cacerts} is a symlink; pass the keystore it should resolve to" >&2
      exit 1
    fi

    # The JDK loads blocked.certs with java.util.Properties: `Algorithm` names the digest
    # every other key is compared in, a key may be followed by `=`, `:` or whitespace, and a
    # repeated key keeps its last value. Require exactly one Algorithm key, set to SHA-256
    # (what every shipped JDK uses), so the appended fingerprints are compared at all.
    if [ ! -f "${blocked}" ] \
        || [ "$(grep -cE '^[[:space:]]*Algorithm([[:space:]=:]|$)' "${blocked}")" -ne 1 ] \
        || ! grep -q '^Algorithm=SHA-256$' "${blocked}"; then
      echo "ERROR: ${blocked} is missing or does not have exactly one Algorithm=SHA-256 line" >&2
      exit 1
    fi
    # Ensure the file ends in a newline, so the first appended entry gets its own line.
    if [ -n "$(tail -c 1 "${blocked}")" ]; then
      echo >> "${blocked}"
    fi
    added=0
    for fingerprint in ${INTERMEDIATES} ${ROOTS}; do
      if ! grep -qx "${fingerprint}" "${blocked}"; then
        echo "${fingerprint}" >> "${blocked}"
        added=$((added + 1))
      fi
    done
    for fingerprint in ${INTERMEDIATES} ${ROOTS}; do
      if ! grep -qx "${fingerprint}" "${blocked}"; then
        echo "ERROR: ${blocked} does not block ${fingerprint}" >&2
        exit 1
      fi
    done
    echo "Blocked the 16 compromised eMudhra intermediates and their 4 roots in ${blocked} (${added} added)"

    # Plain assignment so `set -e` aborts if keytool cannot read the keystore.
    listing=$("${keytool}" -list -v -keystore "${cacerts}" -storepass changeit 2>/dev/null)
    aliases=$(echo "${listing}" | grep -E '^Alias name:|SHA256:' \
      | grep -B1 -E "SHA256: (${ROOTS_PATTERN})" | sed -n 's/^Alias name: //p') || true
    echo "${aliases}" | while IFS= read -r alias; do
      [ -n "${alias}" ] || continue
      "${keytool}" -delete -noprompt -keystore "${cacerts}" -storepass changeit -alias "${alias}" 2>/dev/null
      echo "Removed '${alias}' from ${cacerts}"
    done
    listing=$("${keytool}" -list -v -keystore "${cacerts}" -storepass changeit 2>/dev/null)
    if ! echo "${listing}" | grep -qE 'SHA256:'; then
      echo "ERROR: could not read any certificate from ${cacerts}" >&2
      exit 1
    fi
    if echo "${listing}" | grep -qE "SHA256: (${ROOTS_PATTERN})"; then
      echo "ERROR: ${cacerts} still trusts a compromised eMudhra root" >&2
      exit 1
    fi
    echo "${cacerts} does not trust the compromised eMudhra roots"
    ;;
  check)
    [ $# -ge 1 ] || usage
    for bundle in "$@"; do
      # A missing or unreadable bundle must fail the check, not pass it vacuously.
      if ! certs=$("${keytool}" -printcert -file "${bundle}" 2>/dev/null) || [ -z "${certs}" ]; then
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
