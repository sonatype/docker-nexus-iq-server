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
        withEnv(["DOCKER_CONFIG=${env.WORKSPACE_TMP}/.dockerConfig", 'DOCKER_CONTENT_TRUST=0']) {
          withCredentials([
              string(credentialsId: '0fe2ec-password', variable: '0fe2ec-password'),
              file(credentialsId: '0fe2ec', variable: '0fe2ec'),
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

            OsTools.runSafe(this, """
            export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=helloworld
            """)

            OsTools.runSafe(this, """
            docker trust key load $0fe2ec
            """)

             OsTools.runSafe(this, 'docker trust signer add sonatype docker.io/sonatype/sign-me --key $PUBLIC_KEY')
            // OsTools.runSafe(this, 'docker trust key load $PUBLIC_KEY --name sonatype')

            OsTools.runSafe(this, "docker pull sonatype/sign-me:3")

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
