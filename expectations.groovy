/*
 * Copyright (c) 2011-present Sonatype, Inc. All rights reserved.
 * Includes the third-party code listed at http://links.sonatype.com/products/clm/attributions.
 * "Sonatype" is a trademark of Sonatype, Inc.
 */

import com.sonatype.jenkins.shared.Expectation

def containerExpectations(String containerName = 'iq-server-test') {
  def c = containerName
  return [
    new Expectation('nexus-group', 'docker', "exec ${c} grep '^nexus:' /etc/group", 'nexus:x:1000:'),
    new Expectation('nexus-user', 'docker', "exec ${c} grep '^nexus:' /etc/passwd", 'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/bin/false'),
    new Expectation('iq-process', 'docker', "exec ${c} sh -c 'ps -e -o command,user | grep -q ^/usr/bin/java.*nexus\$ | echo \$?'", '0'),
    new Expectation('application-port', 'docker', "exec ${c} sh -c 'localcheck --port 8070 --path / && echo OK'", 'OK'),
    new Expectation('admin-port', 'docker', "exec ${c} sh -c 'localcheck --port 8071 && echo OK'", 'OK'),
    new Expectation('log-directory', 'docker', "exec ${c} ls -ld /var/log/nexus-iq-server", 'drwxr-xr-x.*nexus.*nexus.*nexus-iq-server'),
    new Expectation('clm-server-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/clm-server.log && echo OK'", 'OK'),
    new Expectation('audit-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/audit.log && echo OK'", 'OK'),
    new Expectation('request-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/request.log && echo OK'", 'OK'),
    new Expectation('stderr-log', 'docker', "exec ${c} sh -c 'test -f /var/log/nexus-iq-server/stderr.log && echo OK'", 'OK'),
    new Expectation('home-directory', 'docker', "exec ${c} ls -ld /opt/sonatype/nexus-iq-server", 'drwxr-xr-x.*nexus.*nexus.*nexus-iq-server'),
    new Expectation('start-script', 'docker', "exec ${c} sh -c 'test -f /opt/sonatype/nexus-iq-server/start.sh && echo OK'", 'OK'),
    new Expectation('start-script-has-java-opts', 'docker', "exec ${c} grep JAVA_OPTS /opt/sonatype/nexus-iq-server/start.sh", 'JAVA_OPTS'),
    new Expectation('work-directory', 'docker', "exec ${c} ls -ld /sonatype-work", 'drwxr-xr-x.*nexus.*nexus.*sonatype-work'),
    new Expectation('data-directory', 'docker', "exec ${c} sh -c 'test -d /sonatype-work/data && echo OK'", 'OK'),
    new Expectation('config-directory', 'docker', "exec ${c} ls -ld /etc/nexus-iq-server", 'drwxr-xr-x.*nexus.*nexus.*nexus-iq-server'),
    new Expectation('config-file', 'docker', "exec ${c} sh -c 'test -f /etc/nexus-iq-server/config.yml && echo OK'", 'OK'),
    new Expectation('tini', 'docker', "exec ${c} sh -c 'test -x /sbin/tini-static && echo OK'", 'OK'),
    new Expectation('localcheck', 'docker', "exec ${c} sh -c 'which localcheck && echo OK'", 'OK')
  ]
}

return this;
