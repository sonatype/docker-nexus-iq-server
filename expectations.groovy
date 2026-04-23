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

def containerExpectations(String containerName = 'iq-server-test') {
  return [
    // === Process verification ===
    // docker top reads container processes via the docker daemon, so it works
    // even when the Jenkins agent runs in its own PID namespace and can't see
    // host PIDs directly.
    new Expectation('java-process', 'sh', "-c 'docker top ${containerName} | grep -wq java && echo java'", 'java'),
    new Expectation('java-opts-applied', 'sh', "-c 'docker top ${containerName} | grep -o -- -Dtest.java.opts=works'", '-Dtest.java.opts=works'),

    // === Port checks (localcheck is built into base image) ===
    // Use host sh to chain && echo OK because localcheck succeeds silently and
    // the Expectation class requires a non-empty expectedOutput.
    new Expectation('application-port', 'sh', "-c 'docker exec ${containerName} localcheck --port 8070 --path / && echo OK'", 'OK'),
    new Expectation('admin-port', 'sh', "-c 'docker exec ${containerName} localcheck --port 8071 && echo OK'", 'OK'),

    // === Git executable verification ===
    new Expectation('git-exists', 'sh', "-c 'docker exec ${containerName} git --version'", 'git version'),

    // === File existence (via docker cp | tar -t) ===
    new Expectation('launcher-exists', 'sh', "-c 'docker cp ${containerName}:/bin/launcher - | tar -t | grep launcher'", 'launcher'),
    new Expectation('tini-exists', 'sh', "-c 'docker cp ${containerName}:/sbin/tini-static - | tar -t | grep tini-static'", 'tini-static'),
    new Expectation('config-file', 'sh', "-c 'docker cp ${containerName}:/etc/nexus-iq-server/config.yml - | tar -t | grep config.yml'", 'config.yml'),
    new Expectation('iq-home', 'sh', "-c 'docker cp ${containerName}:/opt/sonatype/nexus-iq-server/nexus-iq-server.jar - | tar -t | grep nexus-iq-server.jar'", 'nexus-iq-server.jar'),

    // === Log files ===
    new Expectation('stderr-log', 'sh', "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/stderr.log - | tar -t | grep stderr.log'", 'stderr.log'),
    new Expectation('clm-server-log', 'sh', "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/clm-server.log - | tar -t | grep clm-server.log'", 'clm-server.log'),
    new Expectation('audit-log', 'sh', "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/audit.log - | tar -t | grep audit.log'", 'audit.log'),
    new Expectation('request-log', 'sh', "-c 'docker cp ${containerName}:/var/log/nexus-iq-server/request.log - | tar -t | grep request.log'", 'request.log'),

    // === User/group verification (via docker cp | tar -xO) ===
    new Expectation('nexus-user', 'sh', "-c 'docker cp ${containerName}:/etc/passwd - | tar -xO | grep ^nexus'", 'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/usr/sbin/nologin'),
    new Expectation('nexus-group', 'sh', "-c 'docker cp ${containerName}:/etc/group - | tar -xO | grep ^nexus'", 'nexus:x:1000:'),
  ]
}

return this;
