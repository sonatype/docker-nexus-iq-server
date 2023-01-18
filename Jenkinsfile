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
import com.sonatype.jenkins.pipeline.GitHub
import com.sonatype.jenkins.pipeline.OsTools

node('ubuntu-zion-legacy') {
  def commitId, commitDate, version, branch, dockerFileLocations, nexusIqVersion, nexusIqSha
  def imageId, slimImageId, redHatImageId
  def organization = 'sonatype',
      gitHubRepository = 'docker-nexus-iq-server',
      credentialsId = 'sonaype-ci-github-access-token',
      imageName = 'sonatype/nexus-iq-server',
      archiveName = 'docker-nexus-iq-server',
      iqApplicationId = 'docker-nexus-iq-server',
      dockerHubRepository = 'nexus-iq-server',
      tarName = 'docker-nexus-iq-server.tar'

  try {
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

      version = '1.40.0'
    }

      stage('Sign image') {
        def dockerHubApiToken
        OsTools.runSafe(this, "mkdir -p '${env.WORKSPACE_TMP}/.dockerConfig'")
        OsTools.runSafe(this, "cp -n '${env.HOME}/.docker/config.json' '${env.WORKSPACE_TMP}/.dockerConfig' || true")
        withEnv(["DOCKER_CONFIG=${env.WORKSPACE_TMP}/.dockerConfig", 'DOCKER_CONTENT_TRUST=1']) {
          withCredentials([
              string(credentialsId: 'nexus-iq-server_dct_reg_pw', variable: 'DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE'),
              string(credentialsId: 'sonatype_docker_root_pw', variable: 'DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE'),
              file(credentialsId: 'nexus-iq-server_dct_gun_key', variable: 'DELEGATION_KEY'),
              file(credentialsId: 'sonatype_docker_root_public_key', variable: 'PUBLIC_KEY'),
              [$class: 'UsernamePasswordMultiBinding', credentialsId: 'docker-hub-credentials',
               usernameVariable: 'DOCKERHUB_API_USERNAME', passwordVariable: 'DOCKERHUB_API_PASSWORD']
          ]) {


            OsTools.runSafe(this, """
            docker login --username ${env.DOCKERHUB_API_USERNAME} --password ${env.DOCKERHUB_API_PASSWORD}
            """)

            // Add delegation private key
            OsTools.runSafe(this, 'docker trust key load $DELEGATION_KEY --name sonatype')

            // Add delegation public key

            // Sign the images
            OsTools.runSafe(this, "docker trust sign sonatype/nexus-iq-server:1.40.0")

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
      }
  } finally {
    OsTools.runSafe(this, "docker logout")
    OsTools.runSafe(this, "docker system prune -a -f")
    OsTools.runSafe(this, 'git clean -f && git reset --hard origin/master')
  }
}
