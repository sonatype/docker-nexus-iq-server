package com.sonatype.docker.nexus.iq.server

@Library(['jenkins-shared']) _
import com.sonatype.jenkins.shared.Expectation

public final class DockerNexusIqServerTest
{
  public static Expectation[] nexusIqServerontainerExpectations() {
    return [
      new Expectation('nexus-group', 'grep', '^nexus: /etc/group', 'nexus:x:1000:'),
      new Expectation('nexus-user', 'grep', '^nexus: /etc/passwd', 'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/bin/false'),
      new Expectation('iq-process', 'ps', '-e -o command,user | grep -q ^/usr/bin/java.*nexus$ | echo $?', '0'),
      new Expectation('application-port', 'curl', '-s --fail --connect-timeout 120 http://localhost:8070/ | echo $?', '0'),
      new Expectation('admin-port', 'curl', '-s --fail --connect-timeout 120 http://localhost:8071/ | echo $?', '0'),
      new Expectation('log-directory', 'ls', '-la /var/log | awk \'\$9 !~ /^\\.*$/{print \$1,\$3,\$4,\$9}\'', 'drwxr-xr-x nexus nexus nexus-iq-server'),
      new Expectation('clm-server-log', 'test', '-f /var/log/nexus-iq-server/clm-server-log.log | echo $?', '0'),
      new Expectation('audit-log', 'test', '-f /var/log/nexus-iq-server/audit.log | echo $?', '0'),
      new Expectation('request-log', 'test', '-f /var/log/nexus-iq-server/request.log | echo $?', '0'),
      new Expectation('stderr-log', 'test', '-f /var/log/nexus-iq-server/stderr.log | echo $?', '0'),
      new Expectation('home-directory', 'ls', '-la /opt/sonatype | grep nexus-iq-server | awk \'\$9 !~ /^\\.*$/{print \$1,\$3,\$4,\$9}\'', 'drwxr-xr-x nexus nexus nexus-iq-server'),
      new Expectation('start-script', 'test', '-f /opt/sonatype/nexus-iq-server/start.sh | echo $?', '0'),
      new Expectation('start-script-has-java-opts', 'grep', '\'JAVA_OPTS\' /opt/sonatype/nexus-iq-server/start.sh | echo $?', '0'), 
      new Expectation('work-directory', 'ls', '-la / | grep sonatype-work | awk \'\$9 !~ /^\\.*$/{print \$1,\$3,\$4,\$9}\'', 'drwxr-xr-x nexus nexus sonatype-work'), 
      new Expectation('data-directory', 'test', '-d /sonatype-work/data | echo $?', '0'), 
      new Expectation('config-directory', 'ls', '-la /etc | grep nexus-iq-server | awk \'\$9 !~ /^\\.*$/{print \$1,\$3,\$4,\$9}\'', 'drwxr-xr-x nexus nexus nexus-iq-server'), 
      new Expectation('config-file', 'test', '-f /etc/nexus-iq-server | echo $?', '0') 
    ]     
  }
}