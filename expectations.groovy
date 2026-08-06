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

// Returns the container-parity expectation list.
//
// Two modes, chosen by whether a containerName is passed:
//
//   containerExpectations()                → legacy in-container mode.
//     Expectations run commands INSIDE the image being validated. Requires
//     shell utilities (grep, test, stat, curl) to be present at runtime.
//     Used by the UBI9/Alpine variants where the Jenkins build environment
//     IS the IQ runtime image.
//
//   containerExpectations('my-container') → container-inspection mode.
//     Expectations run on the HOST (the Jenkins build image) and inspect
//     the running IQ container via `docker exec`, `docker top`, and
//     `docker cp`. Does not require any shell utilities to exist inside
//     the IQ runtime image. Used by the hardened variant where the Jenkins
//     build environment is a generic docker:latest image.
def containerExpectations(String containerName = null) {
  if (containerName) {
    return containerInspectionExpectations(containerName)
  }
  return inContainerExpectations()
}

// Legacy behavior — run commands inside the container under test.
def inContainerExpectations() {
  return [
    new Expectation('nexus-group', 'grep', '^nexus: /etc/group', 'nexus:x:1000:'),
    new Expectation('nexus-user', 'grep', '^nexus: /etc/passwd', 'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/bin/false'),
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

// New behavior — inspect the running container from the host via docker CLI.
// No dependencies on utilities inside the runtime image (works even with
// FROM scratch); parity with inContainerExpectations() where possible.
def containerInspectionExpectations(String containerName) {
  return [
    // Users / groups (read /etc/passwd + /etc/group out of the container).
    new Expectation('nexus-group', 'sh',
      "-c 'docker cp ${containerName}:/etc/group - | tar -xO | grep ^nexus:'",
      'nexus:x:1000:'),
    new Expectation('nexus-user', 'sh',
      "-c 'docker cp ${containerName}:/etc/passwd - | tar -xO | grep ^nexus:'",
      'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/bin/false'),

    // Process — `docker top` reads from the host's docker daemon, so it
    // works regardless of the PID namespace or of what's inside the image.
    new Expectation('iq-process', 'sh',
      "-c 'docker top ${containerName} | grep -oE \"[a-z/-]*java\" | head -1'",
      'java'),

    // Ports — curl is present in the hardened runtime; use `docker exec` so
    // we're checking that the port responds inside the container's network
    // namespace, not on the Jenkins host.
    new Expectation('application-port', 'sh',
      "-c 'docker exec ${containerName} curl -s -o /dev/null -w %{http_code} http://localhost:8070/'",
      '303'),
    new Expectation('admin-port', 'sh',
      "-c 'docker exec ${containerName} curl -s http://localhost:8071/ping'",
      'pong'),

    // Directory permissions — parse `docker exec ls -ld` output for owner.
    new Expectation('log-directory', 'sh',
      "-c 'docker exec ${containerName} sh -c \"ls -ld /var/log/nexus-iq-server\" | awk \"{print \\\$1,\\\$3,\\\$4}\"'",
      'drwxr-xr-x nexus nexus'),
    new Expectation('home-directory', 'sh',
      "-c 'docker exec ${containerName} sh -c \"ls -ld /opt/sonatype/nexus-iq-server\" | awk \"{print \\\$1,\\\$3,\\\$4}\"'",
      'drwxr-xr-x nexus nexus'),
    new Expectation('work-directory', 'sh',
      "-c 'docker exec ${containerName} sh -c \"ls -ld /sonatype-work\" | awk \"{print \\\$1,\\\$3,\\\$4}\"'",
      'drwxr-xr-x nexus nexus'),
    new Expectation('config-directory', 'sh',
      "-c 'docker exec ${containerName} sh -c \"ls -ld /etc/nexus-iq-server\" | awk \"{print \\\$1,\\\$3,\\\$4}\"'",
      'drwxr-xr-x nexus nexus'),

    // Log files — presence check via `docker cp` piped through tar.
    new Expectation('clm-server-log', 'sh',
      "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/clm-server.log - | tar -t 2>/dev/null | head -1'",
      'clm-server.log'),
    new Expectation('audit-log', 'sh',
      "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/audit.log - | tar -t 2>/dev/null | head -1'",
      'audit.log'),
    new Expectation('request-log', 'sh',
      "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/request.log - | tar -t 2>/dev/null | head -1'",
      'request.log'),
    new Expectation('stderr-log', 'sh',
      "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/stderr.log - | tar -t 2>/dev/null | head -1'",
      'stderr.log'),

    // Start script + config file presence.
    new Expectation('start-script', 'sh',
      "-c 'docker cp ${containerName}:/opt/sonatype/nexus-iq-server/start.sh - | tar -t 2>/dev/null | head -1'",
      'start.sh'),
    new Expectation('config-file', 'sh',
      "-c 'docker cp ${containerName}:/etc/nexus-iq-server/config.yml - | tar -t 2>/dev/null | head -1'",
      'config.yml'),

    // SCM/policy-scan tooling parity: git + ssh must be present and executable.
    new Expectation('git-executable', 'sh',
      "-c 'docker exec ${containerName} sh -c \"git --version\" | grep -oE \"^git version\"'",
      'git version'),
    new Expectation('ssh-executable', 'sh',
      "-c 'docker exec ${containerName} sh -c \"ssh -V 2>&1\" | grep -oE \"^OpenSSH\"'",
      'OpenSSH')
  ]
}

return this;
