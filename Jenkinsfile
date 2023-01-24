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
  try {
    stage('Preparation') {
      deleteDir()
      OsTools.runSafe(this, "docker system prune -a -f")
    }

      stage('Sign image') {
        def dockerHubApiToken
        OsTools.runSafe(this, "mkdir -p '${env.WORKSPACE_TMP}/.dockerConfig'")
        OsTools.runSafe(this, "cp -n '${env.HOME}/.docker/config.json' '${env.WORKSPACE_TMP}/.dockerConfig' || true")
        withEnv(["DOCKER_CONFIG=${env.WORKSPACE_TMP}/.dockerConfig", 'DOCKER_CONTENT_TRUST=1']) {
          withCredentials([
              file(credentialsId: 'nexus-iq-server-repository-key', variable: 'NEXUS_IQ_SERVER_REPOSITORY_KEY'),
              file(credentialsId: 'sonatype-pub', variable: 'SONATYPE_PUB'),
              file(credentialsId: 'sonatype-key', variable: 'SONATYPE_KEY'),
              [$class: 'UsernamePasswordMultiBinding', credentialsId: 'docker-hub-credentials',
               usernameVariable: 'DOCKERHUB_API_USERNAME', passwordVariable: 'DOCKERHUB_API_PASSWORD']
          ]) {
            OsTools.runSafe(this, """
              docker login --username ${env.DOCKERHUB_API_USERNAME} --password ${env.DOCKERHUB_API_PASSWORD}
             """)

            // load the repository key..
            OsTools.runSafe(this, 'docker trust key load $NEXUS_IQ_SERVER_REPOSITORY_KEY')

            // load the signers private key
            OsTools.runSafe(this, 'docker trust key load $SONATYPE_KEY')

            // add signer - for this you need signers public key and repository keys password
            withCredentials([string(credentialsId: 'nexus-iq-server_dct_reg_pw', variable: 'DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE')]) {
              OsTools.runSafe(this, 'docker trust signer add sonatype ${organization}/${dockerHubRepository} --key $SONATYPE_PUB')
            }

            // build the image locally
            OsTools.runSafe(this, 'docker pull sonatype/nexus-iq-server:latest')
            OsTools.runSafe(this, 'docker tag sonatype/nexus-iq-server:latest sonatype/nexus-iq-server:latest-test')

            // sign pushes so careful..
            // password needed here is the password for signers private key
            withCredentials([string(credentialsId: 'sonatype-password', variable: 'DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE')]) {
              OsTools.runSafe(this, 'docker trust sign sonatype/nexus-iq-server:latest-test')
            }
          }
        }
      }
  } finally {
    OsTools.runSafe(this, "docker logout")
    OsTools.runSafe(this, "docker system prune -a -f")
  }
}
