/*
 * Copyright (c) 2011-present Sonatype, Inc. All rights reserved.
 * Includes the third-party code listed at http://links.sonatype.com/products/clm/attributions.
 * "Sonatype" is a trademark of Sonatype, Inc.
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
        sh "docker buildx create --driver-opt=\"image=${sonatypeDockerRegistryId()}/moby/buildkit\" --use"
        // Build single platform for testing, cache for multi-platform deploy
        sh "docker buildx build --platform linux/amd64 " +
            "--cache-to type=local,dest=${env.WORKSPACE}/.buildx-cache " +
            "--load " +
            "--secret id=maven-settings,src=${env.WORKSPACE}/.m2/settings.xml " +
            "--tag ${productionImage} ."
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
    // Push the cached multi-platform build to the registry
    withSonatypeDockerRegistry() {
      configFileProvider([configFile(fileId: 'private-settings.xml', targetLocation: "${env.WORKSPACE}/.m2/settings.xml")]) {
        sh "docker buildx create --driver-opt=\"image=${sonatypeDockerRegistryId()}/moby/buildkit\" --use"
        sh "docker buildx build --platform linux/amd64,linux/arm64 " +
            "--cache-from type=local,src=${env.WORKSPACE}/.buildx-cache " +
            "--secret id=maven-settings,src=${env.WORKSPACE}/.m2/settings.xml " +
            "--tag ${sonatypeDockerRegistryId()}/${imageName}:${env.BUILD_NUMBER} " +
            "--push ."
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
