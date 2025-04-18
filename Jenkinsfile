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
String imageName = 'sonatype/nexus-iq-server'

configureBranchJob()
dockerizedBuildPipeline(
  deployBranch: deployBranch,
  deployCondition: { return true }, // always run the deploy stage
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
  deploy: {
    // Hijacking deploy step to run the docker buildx build to make sure it is working
    withSonatypeDockerRegistry() {
      sh "docker buildx create --driver-opt=\"image=${sonatypeDockerRegistryId()}/moby/buildkit\" --use"
      sh "docker buildx build --platform linux/amd64,linux/arm64 " +
          "--tag ${sonatypeDockerRegistryId()}/${imageName}:${env.BUILD_NUMBER} ."
    }
  },
  vulnerabilityScan: {
    def theStage = env.BRANCH_NAME == deployBranch ? 'build' : 'develop'
    nexusPolicyEvaluation(
      iqApplication: 'docker-nexus-iq-server',
      iqScanPatterns: [[scanPattern: "container:${env.DOCKER_IMAGE_ID}"]],
      iqStage: theStage)
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

