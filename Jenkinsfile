/*
 * Copyright (c) 2017-present Sonatype, Inc. All rights reserved.
 * Includes the third-party code listed at http://links.sonatype.com/products/nexus/attributions.
 * "Sonatype" is a trademark of Sonatype, Inc.
 */
@Library(['private-pipeline-library', 'jenkins-shared']) _
import com.sonatype.jenkins.pipeline.GitHub
import com.sonatype.jenkins.pipeline.OsTools

node('ubuntu-zion') {
  def commitId, commitDate, version, imageId, slimImageId, branch, dockerFileLocations, nexusIqVersion, nexusIqSha
  def organization = 'sonatype',
      gitHubRepository = 'docker-nexus-iq-server',
      credentialsId = 'sonaype-ci-github-access-token',
      imageName = 'sonatype/nexus-iq-server',
      archiveName = 'docker-nexus-iq-server',
      iqApplicationId = 'docker-nexus-iq-server',
      dockerHubRepository = 'nexus-iq-server',
      tarName = 'docker-nexus-iq-server.tar'
  GitHub gitHub

  try {
    if (env.releaseBuild_NAME) {
      stage('Init IQ Version & Sha') {
        nexusIqVersion = getVersionFromBuildName(env.releaseBuild_NAME)
        nexusIqSha = readBuildArtifact('insight/insight-brain/release', env.releaseBuild_NUMBER,
          "artifacts/nexus-iq-server-${nexusIqVersion}-bundle.tar.gz.sha256")
      }
    }
    stage('Preparation') {
      deleteDir()
      OsTools.runSafe(this, "docker system prune -a -f")

      def checkoutDetails = checkout scm

      dockerFileLocations = [
        "${pwd()}/Dockerfile",
        "${pwd()}/Dockerfile.slim",
        "${pwd()}/Dockerfile.rh",
      ]

      branch = checkoutDetails.GIT_BRANCH == 'origin/master' ? 'master' : checkoutDetails.GIT_BRANCH
      commitId = checkoutDetails.GIT_COMMIT
      commitDate = OsTools.runSafe(this, "git show -s --format=%cd --date=format:%Y%m%d-%H%M%S ${commitId}")

      OsTools.runSafe(this, 'git config --global user.email sonatype-ci@sonatype.com')
      OsTools.runSafe(this, 'git config --global user.name Sonatype CI')

      version = readVersion()

      def apiToken
      withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: credentialsId,
                        usernameVariable: 'GITHUB_API_USERNAME', passwordVariable: 'GITHUB_API_PASSWORD']]) {
        apiToken = env.GITHUB_API_PASSWORD
      }
      gitHub = new GitHub(this, "${organization}/${gitHubRepository}", apiToken)
    }
    if ((env.releaseBuild_NAME) && branch == 'master') {
      stage('Update IQ Version') {
        OsTools.runSafe(this, "git checkout ${branch}")
        dockerFileLocations.each { updateServerVersion(it, nexusIqVersion, nexusIqSha) }
        version = getShortVersion(nexusIqVersion)
      }
    }
    stage('Build') {
      gitHub.statusUpdate commitId, 'pending', 'build', 'Build is running'

      imageId = buildImage('Dockerfile', imageName)

      slimImageId = buildImage('Dockerfile.slim', "${imageName}-slim")

      if (currentBuild.result == 'FAILURE') {
        gitHub.statusUpdate commitId, 'failure', 'build', 'Build failed'
        return
      } else {
        gitHub.statusUpdate commitId, 'success', 'build', 'Build succeeded'
      }
    }
    stage('Test') {
      gitHub.statusUpdate commitId, 'pending', 'test', 'Tests are running'

      def gemInstallDirectory = getGemInstallDirectory()
      withEnv(["PATH+GEMS=${gemInstallDirectory}/bin"]) {
        OsTools.runSafe(this, "gem install --user-install rspec")
        OsTools.runSafe(this, "gem install --user-install serverspec")
        OsTools.runSafe(this, "gem install --user-install docker-api")
        OsTools.runSafe(this, "IMAGE_ID=${imageId} rspec --backtrace --format documentation spec/Dockerfile_spec.rb")
        OsTools.runSafe(this, "IMAGE_ID=${slimImageId} rspec --backtrace --format documentation spec/Dockerfile_spec.rb")
      }

      if (currentBuild.result == 'FAILURE') {
        gitHub.statusUpdate commitId, 'failure', 'test', 'Tests failed'
        return
      } else {
        gitHub.statusUpdate commitId, 'success', 'test', 'Tests succeeded'
      }
    }
    stage('Evaluate') {
      //decide which stage we are creating
      def theStage = branch == 'master' ? (env.releaseBuild_NAME ? 'release' : 'build') : 'develop'

      runEvaluation({ stage ->
        nexusPolicyEvaluation(
          iqStage: stage,
          iqApplication: iqApplicationId,
          iqScanPatterns: [
            [scanPattern: "container:${imageName}"],
            [scanPattern: "container:${imageName}-slim"],
          ],
          failBuildOnNetworkError: true)
      }, theStage)
    }

    if (currentBuild.result == 'FAILURE') {
      return
    }
    if ((env.releaseBuild_NAME) && branch == 'master') {
      stage('Commit IQ Version Update') {
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: credentialsId,
                        usernameVariable: 'GITHUB_API_USERNAME', passwordVariable: 'GITHUB_API_PASSWORD']]) {
          def commitMessage = [
            nexusIqVersion && nexusIqSha ? "Update IQ Server to ${nexusIqVersion}." : "",
          ].findAll({ it }).join(' ')
          OsTools.runSafe(this, """
            git add .
            git diff --exit-code --cached || git commit -m '${commitMessage}'
            git push https://${env.GITHUB_API_USERNAME}:${env.GITHUB_API_PASSWORD}@github.com/${organization}/${gitHubRepository}.git ${branch}
          """)
        }
      }
    }
    stage('Archive') {
      dir('build/target') {
        OsTools.runSafe(this, "docker save ${imageName} | gzip > ${archiveName}.tar.gz")
        archiveArtifacts artifacts: "${archiveName}.tar.gz", onlyIfSuccessful: true

        OsTools.runSafe(this, "docker save ${imageName}-slim | gzip > ${archiveName}-slim.tar.gz")
        archiveArtifacts artifacts: "${archiveName}-slim.tar.gz", onlyIfSuccessful: true
      }
    }

    if ((env.releaseBuild_NAME) && branch == 'master') {
      stage('Push image') {
        def dockerHubApiToken
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'docker-hub-credentials',
            usernameVariable: 'DOCKERHUB_API_USERNAME', passwordVariable: 'DOCKERHUB_API_PASSWORD']]) {
          OsTools.runSafe(this, "docker tag ${imageId} ${organization}/${dockerHubRepository}:${version}")
          OsTools.runSafe(this, "docker tag ${imageId} ${organization}/${dockerHubRepository}:latest")
          OsTools.runSafe(this, "docker tag ${slimImageId} ${organization}/${dockerHubRepository}:${version}-slim")
          OsTools.runSafe(this, "docker tag ${slimImageId} ${organization}/${dockerHubRepository}:latest-slim")
          OsTools.runSafe(this, """
            docker login --username ${env.DOCKERHUB_API_USERNAME} --password ${env.DOCKERHUB_API_PASSWORD}
          """)
          OsTools.runSafe(this, "docker push --all-tags ${organization}/${dockerHubRepository}")

          response = OsTools.runSafe(this, """
            curl -X POST https://hub.docker.com/v2/users/login/ \
              -H 'cache-control: no-cache' -H 'content-type: application/json' \
              -d '{ "username": "${env.DOCKERHUB_API_USERNAME}", "password": "${env.DOCKERHUB_API_PASSWORD}" }'
          """)
          token = readJSON text: response
          dockerHubApiToken = token.token

          def readme = readFile file: 'README.md', encoding: 'UTF-8'
          readme = readme.replaceAll("(?s)<!--.*?-->", "")
          readme = readme.replace("\"", "\\\"")
          readme = readme.replace("\n", "\\n")
          readme = readme.replace("\\\$", "\\\\\$")
          response = httpRequest customHeaders: [[name: 'authorization', value: "JWT ${dockerHubApiToken}"]],
              acceptType: 'APPLICATION_JSON', contentType: 'APPLICATION_JSON', httpMode: 'PATCH',
              requestBody: "{ \"full_description\": \"${readme}\" }",
              url: "https://hub.docker.com/v2/repositories/${organization}/${dockerHubRepository}/"
        }
      }
      stage('Push tags') {
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: credentialsId,
                          usernameVariable: 'GITHUB_API_USERNAME', passwordVariable: 'GITHUB_API_PASSWORD']]) {
          OsTools.runSafe(this, "git tag ${version}")
          OsTools.runSafe(this, """
            git push \
            https://${env.GITHUB_API_USERNAME}:${env.GITHUB_API_PASSWORD}@github.com/${organization}/${gitHubRepository}.git \
              ${version}
          """)
        }
        OsTools.runSafe(this, "git tag -d ${version}")
      }
    }
  } finally {
    OsTools.runSafe(this, "docker logout")
    OsTools.runSafe(this, "docker system prune -a -f")
    OsTools.runSafe(this, 'git clean -f && git reset --hard origin/master')
  }
}

def readVersion() {
  def content = readFile 'Dockerfile'
  for (line in content.split('\n')) {
    if (line.startsWith('ARG IQ_SERVER_VERSION=')) {
      return getShortVersion(line.substring(22))
    }
  }
  error 'Could not determine version.'
}

String buildImage(String dockerFile, String imageName) {
  OsTools.runSafe(this, "docker build --quiet --no-cache -f ${dockerFile} --tag ${imageName} .")
    .split(':')[1]
}

def getShortVersion(version) {
  return version.split('-')[0]
}

def getGemInstallDirectory() {
  def content = OsTools.runSafe(this, "gem env")
  for (line in content.split('\n')) {
    if (line.startsWith('  - USER INSTALLATION DIRECTORY: ')) {
      return line.substring(33)
    }
  }
  error 'Could not determine user gem install directory.'
}

def updateServerVersion(dockerFileLocation, iqVersion, iqSha) {
  def dockerFile = readFile(file: dockerFileLocation)

  def metaShortVersionRegex = /(release=")(\d\.\d{1,3}\.\d)(" \\)/

  def versionRegex = /(ARG IQ_SERVER_VERSION=)(\d\.\d{1,3}\.\d\-\d{2})/
  def shaRegex = /(ARG IQ_SERVER_SHA256=)([A-Fa-f0-9]{64})/

  dockerFile = dockerFile.replaceAll(metaShortVersionRegex,
      "\$1${iqVersion.substring(0, iqVersion.indexOf('-'))}\$3")
  dockerFile = dockerFile.replaceAll(versionRegex, "\$1${iqVersion}")
  dockerFile = dockerFile.replaceAll(shaRegex, "\$1${iqSha}")

  writeFile(file: dockerFileLocation, text: dockerFile)
}
