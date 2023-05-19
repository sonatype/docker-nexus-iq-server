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
@Library(['private-pipeline-library', 'jenkins-shared']) _
import com.sonatype.jenkins.shared.Expectation

dockerizedBuildPipeline(
  prepare: {
    githubStatusUpdate('pending')
  },
  setVersion: {
    env['VERSION'] = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}"
  },
  buildAndTest: {
    validateExpectations([
        new Expectation('nexus-group', 'grep', '^nexus: /etc/group', 'nexus:x:1000:'),
        new Expectation('nexus-user', 'grep', '^nexus: /etc/passwd', 'nexus:x:1000:1000:Nexus IQ user:/opt/sonatype/nexus-iq-server:/bin/false'),
        new Expectation('iq-process', 'ps', '-e -o command,user | grep -q ^/usr/bin/java.*nexus$ | echo $?', '0'),
        new Expectation('application-port', 'curl', '-s --fail --connect-timeout 120 http://localhost:8070/ | echo $?', '0'),
        new Expectation('admin-port', 'curl', '-s --fail --connect-timeout 120 http://localhost:8070/ | echo $?', '0'),
        new Expectation('log-directory', 'ls', '-la /var/log | awk \'\$9 !~ /^\\.*$/{print \$1,\$3,\$4,\$9}\'', 'drwxr-xr-x nexus nexus nexus-iq-server'),
        new Expectation('audit-log', 'ls', '-la /var/log/nexus-iq-server/audit\.log | awk \'\$9 !~ /^\\.*$/{print \$1,\$3,\$4,\$9}\'', '-rw-r--r-- nexus nexus /var/log/nexus-iq-server/audit.log'),
    ])
  },
  testResults: ['**/validate-expectations-results.xml'],
  vulnerabilityScan: {
    nexusPolicyEvaluation(
      iqApplication: 'docker-nexus-iq-server',
      iqScanPatterns: [[scanPattern: "container:${env.DOCKER_IMAGE_ID}"]],
      iqStage: 'develop')
  },
  onSuccess: {
    githubStatusUpdate('success')
  },
  onFailure: {
    githubStatusUpdate('failure')
  }
)
