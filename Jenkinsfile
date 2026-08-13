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

// Improvement Day experiment: an explicit pipeline for the primary IQ Server image.
//
// Why this exists instead of dockerizedBuildPipeline():
//   - dockerizedBuildPipeline is a "bring your own build environment" wrapper. Using it
//     to build images meant the real work hid inside the 'Prepare Build Image' stage,
//     and it was never obvious which closures ran on the agent vs inside a container.
//   - The Jenkins agents already have docker + buildx, so there is no need to run docker
//     commands inside a docker-in-docker container.
//
// Ground rules here:
//   - EVERY step in this file runs directly on the agent, except the two shared steps
//     that intentionally run tools in throwaway containers (see 'Compliance Check' and
//     'Lint'). Those are noted at the call site.
//   - Image validation happens inside the docker build (see the `test` stage in
//     ./Dockerfile) but is invoked from its own visible pipeline stage, so the tests
//     are named in the build UI instead of being a side effect of another stage.
//   - The same commands work locally; see 'Local equivalent' comments.
//   - There is deliberately no githubStatusUpdate() for the overall build result. The
//     job uses the GitHub Branch Source plugin, which reports commit status for free.
//     The call in the previous Jenkinsfile was vestigial from the old Git branch source
//     and should not be reinstated. (branchNamingCheck() and jiraIssueAndPrCheck() do
//     post their own named statuses; that is separate and still wanted.)

@Library(['private-pipeline-library', 'jenkins-shared']) _

String deployBranch = 'main'
String dockerfile = 'Dockerfile'
// Unique per build so parallel builds on the same agent cannot collide.
String imageId = "docker-nexus-iq-server:${env.BUILD_NUMBER}"
// Where the in-build test stage exports its JUnit XML.
String testResultsDir = 'build/test-results'
// Platform validated by the goss suite. Only the host platform can run the test
// stage without emulation, and the agents are amd64.
String testPlatform = 'linux/amd64'
// Non-host platforms that must at least BUILD. No goss run: booting the whole server
// under qemu is not worth it.
String smokeBuildPlatform = 'linux/arm64'
// On branches, only build the `builder` stage for arm64. That covers the sole
// arch-conditional logic -- the IQ Server tarball + SHA256 selection, where a stale
// IQ_SERVER_SHA256_AARCH otherwise surfaces at release time -- and skips compiling
// OpenSSH from source under emulation, which measured 12+ minutes in build #1 and
// dwarfed the 1m43s the rest of the pipeline takes.
String smokeBuildTarget = 'builder'
// A docker-container builder is required for foreign-platform builds. Named (not
// --use) so plain `docker build` keeps using the default builder and its image store.
// NOTE: it has its own cache, entirely separate from the default builder, so nothing
// is shared with the amd64 stages above.
String builderName = 'iq-image-multiarch'

// Mirrors jenkins-shared's configureBranchJob(): serialize builds and run daily only
// on the deploy branch. Concurrent builds on feature branches are fine, and a cron
// trigger there would be noise. Declarative options{} cannot be made conditional, so
// this is set imperatively before the pipeline block, as the previous Jenkinsfile did.
void configureBranchJob() {
  String projName = currentBuild.fullProjectName
  if (projName.endsWith('main')) {
    properties([
      disableConcurrentBuilds(),
      pipelineTriggers([cron('@daily')])
    ])
  }
}

// Builds one non-host platform. Output is discarded (type=cacheonly): a foreign-platform
// image cannot be loaded into the local image store, and we do not push from here.
//
// buildkit is pinned by digest (moby/buildkit v0.31.1): all buildkit tags are currently
// quarantined by Sonatype Firewall; this pre-quarantine cached digest is pullable.
// Revert to a tag once the quarantine is released/waived.
void buildPlatform(String builderName, String dockerfile, String platform, String target) {
  withSonatypeDockerRegistry() {
    String buildkitImage = "${sonatypeDockerRegistryId()}/moby/buildkit@sha256:" +
        '6b59b7df63a8cb9902736f9ddf7fcff8261613d3e7449b8ea8b7537fc399c03a'
    // Created if missing and deliberately NOT removed, so later builds on this agent
    // reuse it instead of re-pulling buildkit.
    sh """
      docker buildx inspect ${builderName} >/dev/null 2>&1 \
        || docker buildx create --name ${builderName} --driver-opt="image=${buildkitImage}"
    """
    String targetArg = target ? "--target ${target} " : ''
    sh """
      docker buildx build --builder ${builderName} \
        --file ${dockerfile} \
        --platform ${platform} \
        ${targetArg}--output type=cacheonly .
    """
  }
}

configureBranchJob()

pipeline {
  agent {
    label 'ubuntu-zion'
  }

  options {
    // disableConcurrentBuilds() and the daily cron are set in configureBranchJob()
    // above, for the deploy branch only.
    buildDiscarder(logRotator(numToKeepStr: '30', daysToKeepStr: '90'))
  }

  // No environment{} block on purpose. dockerizedBuildPipeline exported
  // SONATYPE_PRIVATE_REGISTRY and passed it as a build arg, but this Dockerfile hardcodes
  // the sonatype.repo.sonatype.app/docker-all base images, so nothing consumes it.
  //
  // Registry auth: every stage that shells out to docker is wrapped in
  // withSonatypeDockerRegistry(), which injects JENKINS_DOCKER_USERNAME/PASSWORD via
  // withCredentials. It does NOT run `docker login` -- the agent's docker credential
  // helper consumes those variables. Outside the wrapper, pulls of the private base
  // images fail to authenticate. licenseCheck() and hadolint() wrap themselves.

  stages {
    stage('Compliance Check') {
      steps {
        // NOTE: mixed failure semantics in this stage, on purpose.
        //   - branchNamingCheck() and jiraIssueAndPrCheck() are INFORMATIONAL. They
        //     publish GitHub statuses, badges and build summaries but never fail the
        //     build, so a green stage does not mean they were satisfied -- check the
        //     badges. jiraIssueAndPrCheck() also self-skips on main/master/release-*.
        //   - licenseCheck() DOES fail the build: it records issues with a FAILURE
        //     quality gate at 1 finding.
        // The informational checks run first so their badges and PR/Jira links are
        // attached even when licenseCheck() fails the stage.
        branchNamingCheck()
        jiraIssueAndPrCheck()
        // Runs on the agent, but shells out to `docker run bnr/license-check`.
        licenseCheck()
      }
    }

    stage('Lint') {
      steps {
        // Runs hadolint INSIDE a hadolint container (withDockerImage), on the agent's
        // docker. Fails the build on >= 1 finding.
        hadolint(["./${dockerfile}"])
      }
    }

    stage('Build Image (amd64)') {
      steps {
        // Plain docker on the agent, default builder, so the result lands in the local
        // image store. No --target: `runtime` is the last stage in the Dockerfile and
        // therefore the default target.
        //
        // Why this is a separate build from 'Test Image' below:
        //   1. `--target test-results` resolves to FROM scratch, so it produces NO image.
        //      Scanning, pushing, and `docker inspect` all need this tagged one.
        //   2. Building with no --target is what proves `runtime` is still the default
        //      target. If someone appends a stage to the Dockerfile and the default
        //      silently becomes an export stage, this catches it -- `docker build` with
        //      no --target is also how build_and_push_images.sh builds the release image.
        //   3. Separate stages mean "build broke" and "tests failed" are distinct
        //      failures with distinct durations in the build UI.
        // Cost is near zero: the second build shares BuildKit cache with this one, so
        // only the goss-bin and test stages actually execute there.
        //
        // Local equivalent:
        //   docker build -t docker-nexus-iq-server:dev .
        withSonatypeDockerRegistry() {
          sh "docker build --file ${dockerfile} --platform ${testPlatform} --tag ${imageId} ."
        }
      }
    }

    stage('Test Image') {
      steps {
        // Validation runs inside the build graph (the `test` stage forks off
        // `runtime-base`), and the results are exported to the workspace by building the
        // `test-results` stage. Earlier stages are cache hits from 'Build Image', so
        // this only executes the test layer.
        //
        // CACHEBUST is required: the test RUN has no file inputs, so BuildKit would
        // otherwise serve a cached pass forever.
        //
        // Local equivalent:
        //   docker build --target test-results --no-cache-filter test \
        //       --output type=local,dest=build/test-results .
        // --build-arg CI=true makes the test stage exit 0 even when checks fail, so the
        // report is always exported and 'Publish Test Results' owns pass/fail. Omit it
        // locally and a failing check fails `docker build` directly instead.
        withSonatypeDockerRegistry() {
          sh """
            rm -rf ${testResultsDir}
            docker build --file ${dockerfile} \
              --target test-results \
              --platform ${testPlatform} \
              --build-arg CI=true \
              --build-arg CACHEBUST=\${BUILD_NUMBER} \
              --output type=local,dest=${testResultsDir} .
          """
        }
      }
    }

    stage('Publish Test Results') {
      steps {
        // goss writes one JUnit document per suite; a readiness-gate failure adds a
        // second file. Publish both, then fail the build on any failure.
        collectTestResults(["${testResultsDir}/**/*.xml"])
        script {
          def testResults = getTestResults(currentBuild)
          def failCount = testResults['failCount'] ?: 0
          if (failCount > 0) {
            error("Image validation failed: ${failCount} failing check(s). See the test report.")
          }
        }
      }
    }

    // Two arm64 stages, one of which runs. The stage name in the build UI tells you
    // which coverage you got, rather than hiding the difference in a build arg.
    stage('Smoke Build (arm64)') {
      when {
        not { branch 'main' }
      }
      steps {
        // Branch builds: `builder` stage only. Catches the arch-conditional tarball
        // and SHA256 selection without the emulated OpenSSH compile.
        //
        // Does NOT cover openssh-builder or the runtime stage for arm64 -- that is what
        // the full build on the deploy branch below is for.
        script {
          buildPlatform(builderName, dockerfile, smokeBuildPlatform, smokeBuildTarget)
        }
      }
    }

    stage('Full Build (arm64)') {
      when {
        branch 'main'
      }
      steps {
        // Deploy branch: the whole graph for arm64, including the emulated OpenSSH
        // compile. Slow (12+ min) but this is the only place the arm64 runtime stage
        // gets built before release.
        script {
          buildPlatform(builderName, dockerfile, smokeBuildPlatform, null)
        }
      }
    }
  }

  post {
    always {
      // Readiness log is not a test report but is the first thing you want on a failure.
      archiveArtifacts artifacts: "${testResultsDir}/readiness.log",
          allowEmptyArchive: true, fingerprint: false
    }
    cleanup {
      sh "docker image rm --force ${imageId} || true"
      deleteDir()
    }
    unstable {
      script {
        if (env.BRANCH_NAME == deployBranch) {
          notifyChat(currentBuild: currentBuild, env: env, room: 'iq-builds')
        }
      }
    }
    failure {
      script {
        if (env.BRANCH_NAME == deployBranch) {
          notifyChat(currentBuild: currentBuild, env: env, room: 'iq-builds')
        }
      }
    }
  }
}
