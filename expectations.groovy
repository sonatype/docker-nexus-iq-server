/*
 * Copyright (c) 2017-present Sonatype, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import com.sonatype.jenkins.shared.Expectation

def containerExpectations() {
  return [
    new Expectation('nexus-group', 'grep', '^nexus: /etc/group', 'nexus:x:1000:'),
    new Expectation('nexus-user', 'grep', '^nexus: /etc/passwd', 'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/bin/false'),
    // openssh 10.4p1 is compiled from source and overlaid onto the image (CLM-42794).
    // These pin the version and assert no server-side or setuid artifacts leak in.
    // NOTE: We can't run 'ssh -V' here because upstream OpenSSH refuses to start when
    // the calling UID isn't in /etc/passwd ("No user exists for uid X"), and the CI
    // agent runs the container as its own unmapped UID. Inspect the binary directly
    // instead — the version string is compiled in and always present.
    // Absence checks use the 5-arg statusCode form so the harness routes them through
    // testForFailure (returnStatus, not returnStdout). That path never throws and never
    // writes an XML attribute on failure, so args stay free of '&' — a regression can't
    // silently tank the JUnit report parse the way `test ! -e X && echo absent` would.
    new Expectation('ssh-version', 'grep', '-ac "OpenSSH_10\\.4p1" /usr/bin/ssh', '1'),
    new Expectation('ssh-client-installed', 'stat', '-c \'%n\' /usr/bin/ssh', '/usr/bin/ssh'),
    new Expectation('ssh-config-present', 'stat', '-c \'%n\' /etc/ssh/ssh_config', '/etc/ssh/ssh_config'),
    new Expectation('ssh-no-sshd', 'test', '-e /usr/sbin/sshd', '', 1),
    new Expectation('ssh-no-sshd-session', 'test', '-e /usr/libexec/openssh/sshd-session', '', 1),
    new Expectation('ssh-no-sftp-server', 'test', '-e /usr/libexec/openssh/sftp-server', '', 1),
    new Expectation('ssh-no-setuid-keysign', 'test', '-e /usr/libexec/openssh/ssh-keysign', '', 1),
    // Arbitrary-UID handoff for openssh 10.4p1 — see the Dockerfile /etc/passwd
    // chmod and start.sh passwd-fixup for context. Lock in both halves so a
    // future refactor cannot silently strip either.
    new Expectation('etc-passwd-group-writable', 'stat', '-c "%a %G" /etc/passwd', '664 root'),
    new Expectation('start-script-has-passwd-fixup', 'grep', '-c "iqserver:" /opt/sonatype/nexus-iq-server/start.sh', '1'),
    new Expectation('iq-process', 'test', '-d /proc/1 -a "$(cat /proc/1/comm)" = java | echo $?', '0'),
    new Expectation('application-port', 'curl', '-s --fail --connect-timeout 120 http://localhost:8070/ | echo $?', '0'),
    new Expectation('admin-port', 'curl', '-s --fail --connect-timeout 120 http://localhost:8071/ | echo $?', '0'),
    new Expectation('log-directory', 'stat', '-c \'%A %U %G\' /var/log/nexus-iq-server', 'drwxr-xr-x nexus nexus'),
    new Expectation('clm-server-log', 'test', '-f /var/log/nexus-iq-server/clm-server-log.log | echo $?', '0'),
    new Expectation('audit-log', 'test', '-f /var/log/nexus-iq-server/audit.log | echo $?', '0'),
    new Expectation('request-log', 'test', '-f /var/log/nexus-iq-server/request.log | echo $?', '0'),
    new Expectation('stderr-log', 'test', '-f /var/log/nexus-iq-server/stderr.log | echo $?', '0'),
    new Expectation('home-directory', 'stat', '-c \'%A %U %G\' /opt/sonatype/nexus-iq-server', 'drwxr-xr-x nexus nexus'),
    new Expectation('start-script', 'test', '-f /opt/sonatype/nexus-iq-server/start.sh | echo $?', '0'),
    new Expectation('start-script-has-java-opts', 'grep', '\'JAVA_OPTS\' /opt/sonatype/nexus-iq-server/start.sh | echo $?', '0'), 
    new Expectation('work-directory', 'stat', '-c \'%A %U %G\' /sonatype-work', 'drwxr-xr-x nexus nexus'),
    new Expectation('data-directory', 'test', '-d /sonatype-work/data | echo $?', '0'), 
    new Expectation('config-directory', 'stat', '-c \'%A %U %G\' /etc/nexus-iq-server', 'drwxr-xr-x nexus nexus'),
    new Expectation('config-file', 'test', '-f /etc/nexus-iq-server | echo $?', '0') 
  ]     
}

return this; 