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

void configureBranchJob() {
  String projName = currentBuild.fullProjectName
  if (projName.endsWith('main')) {
    properties([
      disableConcurrentBuilds(),
      pipelineTriggers([cron('@daily')])
    ])
  }
}

String deployBranch = 'main'

configureBranchJob()
dockerizedBuildPipeline(
  deployBranch: deployBranch,
  prepare: {
    githubStatusUpdate('pending')
  },
  lint: {
    hadolint(['./Dockerfile'])
  },
  buildAndTest: {
    def expectations = load 'expectations.groovy'
    validateExpectations(expectations.containerExpectations())
  },
  testResults: ['**/validate-expectations-results.xml'],
  vulnerabilityScan: {
    nexusPolicyEvaluation(
      iqApplication: 'docker-nexus-iq-server',
      iqScanPatterns: [[scanPattern: "container:${env.DOCKER_IMAGE_ID}"]],
      iqStage: 'develop')
  },
  onUnstable: {
    if (env.BRANCH_NAME == deployBranch) {
      notifyChat(currentBuild: currentBuild, env: env, room: 'iq-builds')
    } 
  },
  onFailure: {
    if (env.BRANCH_NAME == deployBranch) {
      notifyChat(currentBuild: currentBuild, env: env, room: 'iq-builds')
    } 
  }
)
