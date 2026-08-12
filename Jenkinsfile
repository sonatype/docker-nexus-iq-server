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
  buildImageId: 'sonatype.repo.sonatype.app/docker-all/docker:latest',
  dockerArgs: '-v /var/run/docker.sock:/var/run/docker.sock',
  deployBranch: deployBranch,
  prepare: {
    githubStatusUpdate('pending')
  },
  lint: {
    hadolint(['./Dockerfile'])
  },
  buildAndTest: {
    withSonatypeDockerRegistry() {
      sh 'echo $JENKINS_DOCKER_PASSWORD | docker login -u $JENKINS_DOCKER_USERNAME --password-stdin sonatype.repo.sonatype.app'
      // buildkit tags quarantined by Sonatype Firewall — pin to pre-quarantine digest until waived.
      sh "docker buildx create --driver-opt=\"image=${sonatypeDockerRegistryId()}/moby/buildkit@sha256:6b59b7df63a8cb9902736f9ddf7fcff8261613d3e7449b8ea8b7537fc399c03a\" --use"
      sh "docker buildx build --platform linux/amd64 " +
          "-f Dockerfile " +
          "--cache-to type=local,dest=${env.WORKSPACE}/.buildx-cache " +
          "--load " +
          "--tag troy-test-image ."
    }
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

