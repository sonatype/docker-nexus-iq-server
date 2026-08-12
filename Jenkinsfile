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
  testOutputStage: 'test-results',
  // dockerPrepareBuildImage exports the test-results stage to ./out, and
  // collectTestResults is a no-op unless testResults is set, so without this
  // goss failures would never be published and the build would stay green.
  testResults: ['out/**/*.xml'],
  // The test stage's RUN has no file inputs; without a changing build arg
  // BuildKit serves a cached pass on every rebuild. Single-quoted so $BUILD_NUMBER
  // is expanded by the shell in dockerPrepareBuildImage, not by Groovy.
  additionalBuildArguments: ['CACHEBUST=${BUILD_NUMBER}'],
  prepare: {
    githubStatusUpdate('pending')
  },
  lint: {
    hadolint(['./Dockerfile'])
  },
  buildAndTest: {
    echo "Doing nothing"
  },
  deploy: {
    // Hijacking deploy step to run the docker buildx build to make sure it is working
    withSonatypeDockerRegistry() {
      // Pinned by digest (moby/buildkit v0.31.1): all buildkit tags are currently quarantined by
      // Sonatype Firewall; this pre-quarantine cached digest is pullable. Revert to a tag once the
      // quarantine is released/waived.
      sh "docker buildx create --driver-opt=\"image=${sonatypeDockerRegistryId()}/moby/buildkit@sha256:6b59b7df63a8cb9902736f9ddf7fcff8261613d3e7449b8ea8b7537fc399c03a\" --use"
      sh "docker buildx build --platform linux/amd64,linux/arm64 " +
          "--tag ${sonatypeDockerRegistryId()}/${imageName}:${env.BUILD_NUMBER} ."
    }
  },
  skipVulnerabilityScan: true,
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

