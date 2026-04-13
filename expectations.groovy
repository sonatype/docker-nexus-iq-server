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
  def c = containerName
  return [
    new Expectation('nonroot-group', 'docker', "exec ${c} grep '^nonroot:' /etc/group", 'nonroot:x:65532:'),
    new Expectation('nonroot-user', 'docker', "exec ${c} grep '^nonroot:' /etc/passwd", 'nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin'),
    new Expectation('iq-process', 'docker', "exec ${c} sh -c 'ps -e -o command,user | grep -q ^/usr/bin/java.*nonroot\$ | echo \$?'", '0'),
    new Expectation('application-port', 'docker', "exec ${c} sh -c 'java -cp /opt/sonatype/healthcheck Healthcheck --app > /dev/null | echo \$?'", '0'),
    new Expectation('admin-port', 'docker', "exec ${c} sh -c 'java -cp /opt/sonatype/healthcheck Healthcheck | echo \$?'", '0'),
    new Expectation('log-directory', 'docker', "exec ${c} ls -ld /var/log/nexus-iq-server", 'drwxr-xr-x.*nonroot.*nonroot.*nexus-iq-server'),
    new Expectation('clm-server-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/clm-server-log.log && echo OK'", 'OK'),
    new Expectation('audit-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/audit.log && echo OK'", 'OK'),
    new Expectation('request-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/request.log && echo OK'", 'OK'),
    new Expectation('stderr-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/stderr.log && echo OK'", 'OK'),
    new Expectation('home-directory', 'docker', "exec ${c} ls -ld /opt/sonatype/nexus-iq-server", 'drwxr-xr-x.*nonroot.*nonroot.*nexus-iq-server'),
    new Expectation('start-script', 'docker', "exec ${c} sh -c 'test -f /opt/sonatype/nexus-iq-server/start.sh && echo OK'", 'OK'),
    new Expectation('start-script-has-java-opts', 'docker', "exec ${c} grep JAVA_OPTS /opt/sonatype/nexus-iq-server/start.sh", 'JAVA_OPTS'),
    new Expectation('work-directory', 'docker', "exec ${c} ls -ld /sonatype-work", 'drwxr-xr-x.*nonroot.*nonroot.*sonatype-work'),
    new Expectation('data-directory', 'docker', "exec ${c} sh -c 'test -d /sonatype-work/data && echo OK'", 'OK'),
    new Expectation('config-directory', 'docker', "exec ${c} ls -ld /etc/nexus-iq-server", 'drwxr-xr-x.*nonroot.*nonroot.*nexus-iq-server'),
    new Expectation('config-file', 'docker', "exec ${c} sh -c 'test -f /etc/nexus-iq-server/config.yml && echo OK'", 'OK'),
    new Expectation('tini', 'docker', "exec ${c} sh -c 'test -x /sbin/tini-static && echo OK'", 'OK'),
    new Expectation('healthcheck-class', 'docker', "exec ${c} sh -c 'test -f /opt/sonatype/healthcheck/Healthcheck.class && echo OK'", 'OK')
  ]
}

return this;
