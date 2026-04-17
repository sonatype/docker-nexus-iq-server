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
String productionImage = 'iq-server-under-test'

configureBranchJob()
dockerizedBuildPipeline(
  buildImageId: 'sonatype.repo.sonatype.app/docker-all/docker:latest',
  dockerArgs: '-v /var/run/docker.sock:/var/run/docker.sock -u root:root',
  deployBranch: deployBranch,
  deployCondition: { return true }, // always run the deploy stage
  prepare: {
    githubStatusUpdate('pending')
  },
  lint: {
    hadolint(['./Dockerfile'])
  },
  buildAndTest: {
    withSonatypeDockerRegistry() {
      sh 'echo $JENKINS_DOCKER_PASSWORD | docker login -u $JENKINS_DOCKER_USERNAME --password-stdin sonatype.repo.sonatype.app'
      configFileProvider([configFile(fileId: 'private-settings.xml', targetLocation: "${env.WORKSPACE}/.m2/settings.xml")]) {
        sh "DOCKER_BUILDKIT=1 docker build --secret id=maven-settings,src=${env.WORKSPACE}/.m2/settings.xml --tag ${productionImage} ."
      }
    }
    def containerName = 'iq-server-test'
    try {
      sh "docker run -d --name ${containerName} -e JAVA_OPTS='-Dtest.java.opts=works' ${productionImage}"
      // localcheck hits /ping (always 200 when admin port is ready).
      // Extra sleep lets the server finish writing log files before expectations run.
      sh """for i in \$(seq 1 60); do
        docker exec ${containerName} localcheck --port 8071 2>/dev/null && break
        sleep 5
      done
      sleep 10"""
      def expectations = load 'expectations.groovy'
      validateExpectations(expectations.containerExpectations(containerName))
    } finally {
      sh "docker logs ${containerName} || true"
      sh "docker rm -f ${containerName} || true"
    }
  },
  deploy: {
    // Run a multi-platform buildx build to verify cross-platform compatibility
    withSonatypeDockerRegistry() {
      configFileProvider([configFile(fileId: 'private-settings.xml', targetLocation: "${env.WORKSPACE}/.m2/settings.xml")]) {
        sh "docker buildx create --driver-opt=\"image=${sonatypeDockerRegistryId()}/moby/buildkit\" --use"
        sh "docker buildx build --platform linux/amd64,linux/arm64 " +
            "--secret id=maven-settings,src=${env.WORKSPACE}/.m2/settings.xml " +
            "--tag ${sonatypeDockerRegistryId()}/${imageName}:${env.BUILD_NUMBER} ."
      }
    }
  },
  vulnerabilityScan: {
    def theStage = env.BRANCH_NAME == deployBranch ? 'build' : 'develop'
    nexusPolicyEvaluation(
      iqApplication: 'docker-nexus-iq-server',
      iqScanPatterns: [[scanPattern: "container:${productionImage}"]],
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
