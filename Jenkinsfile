/*
 * Copyright (c) 2017-present Sonatype, Inc. All rights reserved.
 * Includes the third-party code listed at http://links.sonatype.com/products/nexus/attributions.
 * "Sonatype" is a trademark of Sonatype, Inc.
 */
@Library('ci-pipeline-library') _
import com.sonatype.jenkins.pipeline.GitHub
import com.sonatype.jenkins.pipeline.OsTools

properties([
  parameters([
    string(defaultValue: '', description: 'New Nexus IQ Version', name: 'nexus_iq_version'),
    string(defaultValue: '', description: 'New Nexus IQ Version Sha256', name: 'nexus_iq_version_sha'),

    string(defaultValue: '', description: 'New Nexus IQ Cookbook Version', name: 'nexus_iq_cookbook_version')
  ])
])

node('ubuntu-zion') {
  def commitId, commitDate, version, imageId, branch, dockerFileLocation
  def organization = 'sonatype',
      gitHubRepository = 'docker-nexus-iq-server',
      credentialsId = 'integrations-github-api',
      imageName = 'sonatype/nexus-iq-server',
      archiveName = 'docker-nexus-iq-server',
      dockerHubRepository = 'nexus-iq-server'
  GitHub gitHub

  try {
    stage('Preparation') {
      deleteDir()
      OsTools.runSafe(this, "docker system prune -a -f")

      def checkoutDetails = checkout scm

      dockerFileLocation = "${pwd()}/Dockerfile"

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
    if (params.nexus_iq_version && params.nexus_iq_version_sha) {
      stage('Update IQ Version') {
        OsTools.runSafe(this, "git checkout ${branch}")
        def dockerFile = readFile(file: dockerFileLocation)

        def versionRegex = /(ARG IQ_SERVER_VERSION=)(\d\.\d{1,3}\.\d\-\d{2})/
        def shaRegex = /(ARG IQ_SERVER_SHA256=)([A-Fa-f0-9]{64})/

        dockerFile = dockerFile.replaceAll(versionRegex, "\$1${params.nexus_iq_version}")
        dockerFile = dockerFile.replaceAll(shaRegex, "\$1${params.nexus_iq_version_sha}")

        version = getShortVersion(params.nexus_iq_version)

        writeFile(file: dockerFileLocation, text: dockerFile)
      }
    }
    if (params.nexus_iq_cookbook_version) {
      stage('Update IQ Cookbook Version') {
        OsTools.runSafe(this, "git checkout ${branch}")
        def dockerFile = readFile(file: dockerFileLocation)

        def cookbookVersionRegex = /(ARG IQ_SERVER_COOKBOOK_VERSION=")(release-\d\.\d\.\d{8}\-\d{6}\.[a-z0-9]{7})(")/

        dockerFile = dockerFile.replaceAll(cookbookVersionRegex, "\$1${params.nexus_iq_cookbook_version}\$3")

        writeFile(file: dockerFileLocation, text: dockerFile)
      }
    }
    stage('Build') {
      gitHub.statusUpdate commitId, 'pending', 'build', 'Build is running'

      def hash = OsTools.runSafe(this, "docker build --quiet --no-cache --tag ${imageName} .")
      imageId = hash.split(':')[1]

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
        OsTools.runSafe(this, "IMAGE_ID=${imageId} rspec --backtrace spec/Dockerfile_spec.rb")
      }

      if (currentBuild.result == 'FAILURE') {
        gitHub.statusUpdate commitId, 'failure', 'test', 'Tests failed'
        return
      } else {
        gitHub.statusUpdate commitId, 'success', 'test', 'Tests succeeded'
      }
    }
    if (currentBuild.result == 'FAILURE') {
      return
    }
    if (params.nexus_iq_version && params.nexus_iq_version_sha || params.nexus_iq_cookbook_version) {
      stage('Commit IQ Version Update') {
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'integrations-github-api',
                        usernameVariable: 'GITHUB_API_USERNAME', passwordVariable: 'GITHUB_API_PASSWORD']]) {
          def commitMessage = [
            params.nexus_iq_version && params.nexus_iq_version_sha ? "Update IQ Server to ${params.nexus_iq_version}." : "",
            params.nexus_iq_cookbook_version ? "Update IQ Cookbook to ${params.nexus_iq_cookbook_version}." : "",
          ].findAll({ it }).join(' ')
          OsTools.runSafe(this, """
            git add .
            git commit -m '${commitMessage}'
            git push https://${env.GITHUB_API_USERNAME}:${env.GITHUB_API_PASSWORD}@github.com/${organization}/${gitHubRepository}.git ${branch}
          """)
        }
      }
    }
    stage('Archive') {
      dir('build/target') {
        OsTools.runSafe(this, "docker save ${imageName} | gzip > ${archiveName}.tar.gz")
        archiveArtifacts artifacts: "${archiveName}.tar.gz", onlyIfSuccessful: true
      }
    }
    if (branch != 'master') {
      return
    }
    input 'Push image and tags?'
    stage('Push image') {
      def dockerHubApiToken
      withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'docker-hub-credentials',
          usernameVariable: 'DOCKERHUB_API_USERNAME', passwordVariable: 'DOCKERHUB_API_PASSWORD']]) {
        OsTools.runSafe(this, "docker tag ${imageId} ${organization}/${dockerHubRepository}:${version}")
        OsTools.runSafe(this, "docker tag ${imageId} ${organization}/${dockerHubRepository}:latest")
        OsTools.runSafe(this, """
          docker login --username ${env.DOCKERHUB_API_USERNAME} --password ${env.DOCKERHUB_API_PASSWORD}
        """)
        OsTools.runSafe(this, "docker push ${organization}/${dockerHubRepository}")

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
