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
        OsTools.runSafe(this, "mkdir -p '${env.WORKSPACE_TMP}/.dockerConfigkt'")
        OsTools.runSafe(this, "cp -n '${env.HOME}/.docker/config.json' '${env.WORKSPACE_TMP}/.dockerConfigkt' || true")
        withEnv(["DOCKER_CONFIG=${env.WORKSPACE_TMP}/.dockerConfigkt", 'DOCKER_CONTENT_TRUST=0']) {
          withCredentials([
              string(credentialsId: '0fe2ec-password', variable: '0fe2ec-password'),
              file(credentialsId: '0fe2ec', variable: 'FE2EC_KEY'),
              file(credentialsId: 'sonatype-pub', variable: 'SONATYPE_PUB'),
              file(credentialsId: 'sonatype-key', variable: 'SONATYPE_KEY'),
              string(credentialsId: 'nexus-iq-server_dct_reg_pw', variable: 'FIXMELATER'),
              string(credentialsId: 'sonatype_docker_root_pw', variable: 'SONATYPE_PASSWORD'),
              file(credentialsId: 'nexus-iq-server_dct_gun_key', variable: 'DELEGATION_KEY'),
              file(credentialsId: 'sonatype_docker_root_public_key', variable: 'PUBLIC_KEY'),
              [$class: 'UsernamePasswordMultiBinding', credentialsId: 'docker-hub-credentials',
               usernameVariable: 'DOCKERHUB_API_USERNAME', passwordVariable: 'DOCKERHUB_API_PASSWORD']
          ]) {
            OsTools.runSafe(this, "find $DOCKER_CONFIG")

            OsTools.runSafe(this, """
            docker login --username ${env.DOCKERHUB_API_USERNAME} --password ${env.DOCKERHUB_API_PASSWORD}
            """)

            OsTools.runSafe(this, "docker pull sonatype/sign-me:3")

            // withEnv(['DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=helloworld']) {
              OsTools.runSafe(this, 'docker trust key load $FE2EC_KEY')
            //}

            // OsTools.runSafe(this, "docker trust inspect sonatype/sign-me")
            OsTools.runSafe(this, "find $DOCKER_CONFIG")

            withEnv(['DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=helloworld']) {
              OsTools.runSafe(this, 'docker trust signer add sonatype docker.io/sonatype/sign-me --key $SONATYPE_PUB')
            }

            withEnv(['DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$SONATYPE_PASSWORD']) {
              OsTools.runSafe(this, 'docker trust key load $SONATYPE_KEY')
            }

            OsTools.runSafe(this, 'docker trust sign docker.io/sonatype/sign-me:3')


            // OsTools.runSafe(this, 'docker trust key load $PUBLIC_KEY --name sonatype')

            // Sign the images
            // OsTools.runSafe(this, "docker trust sign --local sonatype/sign-me:3")
          }
        }
      }
  } finally {
    OsTools.runSafe(this, "docker logout")
    OsTools.runSafe(this, "docker system prune -a -f")
  }
}
