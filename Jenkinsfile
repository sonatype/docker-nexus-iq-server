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

dockerizedBuildPipeline(
  prepare: {
    githubStatusUpdate('pending')
  },
  buildAndTest: {
    // TODO add tests
  },
  archiveArtifacts: '*',
  //testResults: ['**/validate-expectations-results.xml'],
  skipVulnerabilityScan: true,
  /* lint: {
    hadolint(['Dockerfile'])
  }, */
  /* vulnerabilityScan: {
    nexusPolicyEvaluation(
      iqApplication: 'docker-nexus-iq-server',
      iqScanPatterns: [[scanPattern: "container:${env.DOCKER_IMAGE_ID}"]],
      iqStage: 'develop')
  }, */
  onSuccess: {
    githubStatusUpdate('success')
  },
  onFailure: {
    githubStatusUpdate('failure')
  }
)
