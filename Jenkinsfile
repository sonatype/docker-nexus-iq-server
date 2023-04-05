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
@Library(['private-pipeline-library', 'jenkins-shared@test-expectations', 'iq-pipeline-library']) _

import com.sonatype.jenkins.shared.Expectation

dockerizedBuildPipeline(
  lint: {
    hadolint(['Dockerfile'])
  },
  buildAndTest: {
    validateExpectations([
          new Expectation('javaVersion', 'java', '-version', 'openjdk version "1.8.0_362"'),
          new Expectation('userGroups', 'id', '', 'uid=1000(nexus) gid=1000(nexus) groups=1000(nexus)'),
          new Expectation('homeDirectory', 'pwd', '', '/opt/sonatype/nexus-iq-server'),
          new Expectation('installDirectory', 'test', '-d /var/log/nexus-iq-server/ && echo \"directory exists\"', 'directory exists'),
          new Expectation('configFile', 'ls', '/etc/nexus-iq-server', 'config.yml')
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
    buildNotifications(currentBuild, env)
  },
  onFailure: {
    buildNotifications(currentBuild, env)
  }
)
