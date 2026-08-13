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

// Improvement Day experiment: an explicit pipeline that builds and validates every
// image variant in this repo.
//
// Why this exists instead of dockerizedBuildPipeline():
//   - dockerizedBuildPipeline is a "bring your own build environment" wrapper. Using it
//     to build images meant the real work hid inside the 'Prepare Build Image' stage,
//     and it was never obvious which closures ran on the agent vs inside a container.
//   - The Jenkins agents already have docker + buildx, so there is no need to run docker
//     commands inside a docker-in-docker container.
//   - One Jenkinsfile per image meant N copies of the same pipeline drifting apart.
//
// Ground rules here:
//   - EVERY step in this file runs directly on the agent, except the two shared steps
//     that intentionally run tools in throwaway containers (see 'Compliance Check' and
//     'Lint'). Those are noted at the call site.
//   - Image validation happens inside the docker build (see the `test` stage in each
//     Dockerfile) but is invoked from its own visible pipeline stage, so the tests are
//     named in the build UI instead of being a side effect of another stage.
//   - The same commands work locally; see 'Local equivalent' comments.
//   - There is deliberately no githubStatusUpdate() for the overall build result. The
//     job uses the GitHub Branch Source plugin, which reports commit status for free.
//     The call in the previous Jenkinsfile was vestigial from the old Git branch source
//     and should not be reinstated. (branchNamingCheck() and jiraIssueAndPrCheck() do
//     post their own named statuses; that is separate and still wanted.)

@Library(['private-pipeline-library', 'jenkins-shared']) _

String deployBranch = 'main'

// Per-image configuration, keyed by the IMAGE matrix axis value. Adding an image =
// adding an entry here plus the axis value below; every stage is driven off this map.
//
// 'ubi' is the plain UBI-based image built from ./Dockerfile. 'rh' is the Red Hat
// Certified Container variant -- also UBI-based, but with the certification payload
// (/licenses, /help.1, the uid_* scripts) asserted by goss.rh.yaml.
//
//   dockerfile     : which Dockerfile to build. Each one owns its own goss suite via its
//                    `test` stage, so the gossfile is NOT configured here.
//   iqApplication  : IQ application to evaluate against. Distinct per variant.
//   smokePlatform  : non-host platform to build as a smoke test, or null if the image
//                    does not support one.
//
// NOTE on smokePlatform: Dockerfile.rh and Dockerfile.alpine both hardcode an x86_64 IQ
// Server tarball with a single IQ_SERVER_SHA256 (rh: linux-x86_64, alpine:
// linux_musl-x86_64), so an arm64 build would silently produce an image containing x86_64
// binaries. Both are null until that is fixed -- an arm64 build there would pass and mean
// nothing. Only Dockerfile/Dockerfile.slim select the tarball per architecture.
//
// NOTE on slim: Dockerfile.slim is currently BYTE-IDENTICAL to Dockerfile, and has been
// for at least 9 months (every historical difference was a lag in the IQ version bump).
// It is included so the team can see the full matrix experience, but as it stands the
// slim cell builds the same image twice under a second IQ application. Whether slim is
// meant to be a distinct image is unresolved.
Map<String, Map<String, String>> variants = [
  'ubi': [
    dockerfile   : 'Dockerfile',
    iqApplication: 'docker-nexus-iq-server',
    smokePlatform: 'linux/arm64',
  ],
  'slim': [
    dockerfile   : 'Dockerfile.slim',
    iqApplication: 'docker-nexus-iq-server-slim',
    smokePlatform: 'linux/arm64',
  ],
  'rh': [
    dockerfile   : 'Dockerfile.rh',
    iqApplication: 'docker-nexus-iq-server-rh',
    smokePlatform: null,
  ],
  'alpine': [
    dockerfile   : 'Dockerfile.alpine',
    iqApplication: 'docker-nexus-iq-server-alpine',
    smokePlatform: null,
  ],
]

// Platform validated by the goss suites. Only the host platform can run the test stage
// without emulation, and the agents are amd64.
String testPlatform = 'linux/amd64'
// Where each cell's test stage exports its JUnit XML, relative to that cell's workspace.
String testResultsDir = 'build/test-results'
// On branches, only build the `builder` stage for the non-host platform. That covers the
// arch-conditional logic (IQ Server tarball + SHA256 selection) and skips compiling
// OpenSSH from source under emulation, which measured 12+ minutes and dwarfed the ~2
// minutes the rest of a cell takes.
String smokeBuildTarget = 'builder'
// A docker-container builder is required for foreign-platform builds. Named (not --use)
// so plain `docker build` keeps using the default builder and its image store.
// NOTE: it has its own cache, separate from the default builder, so nothing is shared
// with the amd64 stages.
String builderName = 'iq-image-multiarch'

// Mirrors jenkins-shared's configureBranchJob(): serialize builds and run daily only on
// the deploy branch. Concurrent builds on feature branches are fine, and a cron trigger
// there would be noise. Declarative options{} cannot be made conditional, so this is set
// imperatively before the pipeline block, as the previous Jenkinsfile did.
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
  // SONATYPE_PRIVATE_REGISTRY and passed it as a build arg, but these Dockerfiles
  // hardcode the sonatype.repo.sonatype.app/docker-all base images, so nothing
  // consumes it.
  //
  // Registry auth: every stage that shells out to docker is wrapped in
  // withSonatypeDockerRegistry(), which injects JENKINS_DOCKER_USERNAME/PASSWORD via
  // withCredentials. It does NOT run `docker login` -- the agent's docker credential
  // helper consumes those variables. Outside the wrapper, pulls of the private base
  // images fail to authenticate. licenseCheck() and hadolint() wrap themselves.

  stages {
    // Repo-wide, so it runs once rather than once per image variant.
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

    // One matrix cell per image variant. Cells run in PARALLEL.
    //
    // Each cell declares its own agent, which is what makes that safe: a cell gets its
    // own workspace, so the variants cannot fight over ./build/test-results, image tags,
    // or `deleteDir()`. Without a per-cell agent, all cells would run concurrently in
    // the SHARED top-level workspace.
    //
    // Cost of that choice: cells may land on different agents, so they do not share a
    // BuildKit cache, and each cell re-checks-out the repo. Both acceptable here since
    // the variants have different base images anyway.
    //
    // Deliberately NOT failFast: if the default image fails validation we still want the
    // rh result in the same build.
    stage('Images') {
      matrix {
        agent {
          label 'ubuntu-zion'
        }

        axes {
          axis {
            name 'IMAGE'
            values 'ubi', 'slim', 'rh', 'alpine'
          }
        }

        stages {
          stage('Lint') {
            steps {
              script {
                // Runs hadolint INSIDE a hadolint container (withDockerImage), on the
                // agent's docker. Fails the build on >= 1 finding.
                hadolint(["./${variants[env.IMAGE].dockerfile}"])
              }
            }
          }

          stage('Build Image') {
            steps {
              // Plain docker on the agent, default builder, so the result lands in the
              // local image store. No --target: `runtime` is the last stage in every
              // Dockerfile and therefore the default target.
              //
              // Why this is a separate build from 'Test Image' below:
              //   1. `--target test-results` resolves to FROM scratch, so it produces NO
              //      image. The vulnerability scan needs this tagged one.
              //   2. Building with no --target is what proves `runtime` is still the
              //      default target. If someone appends a stage to a Dockerfile and the
              //      default silently becomes an export stage, this catches it --
              //      `docker build` with no --target is also how build_and_push_images.sh
              //      builds the release image.
              //   3. Separate stages mean "build broke" and "tests failed" are distinct
              //      failures with distinct durations in the build UI.
              // Cost is near zero: the second build shares BuildKit cache with this one,
              // so only the goss-bin and test stages actually execute there.
              //
              // Local equivalent:
              //   docker build -t docker-nexus-iq-server:dev .
              script {
                withSonatypeDockerRegistry() {
                  sh "docker build --file ${variants[env.IMAGE].dockerfile} " +
                      "--platform ${testPlatform} --tag ${imageTag(env.IMAGE)} ."
                }
              }
            }
          }

          stage('Test Image') {
            steps {
              // Validation runs inside the build graph (each Dockerfile's `test` stage
              // forks off `runtime-base`), and the results are exported to this cell's
              // workspace by building the `test-results` stage. Earlier stages are cache
              // hits from 'Build Image', so this only executes the test layer.
              //
              // CACHEBUST is required: the test RUN has no file inputs, so BuildKit would
              // otherwise serve a cached pass forever.
              //
              // --build-arg CI=true makes the test stage exit 0 even when checks fail, so
              // the report is always exported and the JUnit results own pass/fail. Omit
              // it locally and a failing check fails `docker build` directly instead.
              //
              // Local equivalent:
              //   docker build --target test-results --no-cache-filter test \
              //       --output type=local,dest=build/test-results .
              script {
                withSonatypeDockerRegistry() {
                  sh """
                    rm -rf ${testResultsDir}
                    docker build --file ${variants[env.IMAGE].dockerfile} \
                      --target test-results \
                      --platform ${testPlatform} \
                      --build-arg CI=true \
                      --build-arg CACHEBUST=\${BUILD_NUMBER} \
                      --output type=local,dest=${testResultsDir} .
                  """
                }
                // goss always names its suite "goss", so without this both cells would
                // publish identically-named suites containing identically-named test
                // cases, and the JUnit plugin would merge them into one indistinguishable
                // report. Prefix the suite with the variant instead.
                sh """
                  for f in ${testResultsDir}/*.xml; do
                    [ -e "\$f" ] || continue
                    sed -i 's|<testsuite name="goss|<testsuite name="goss-${env.IMAGE}|' "\$f"
                  done
                """
                // Publishes this cell's results. The build-wide gate runs after the
                // matrix -- see 'Verify Test Results'.
                collectTestResults(["${testResultsDir}/**/*.xml"])
              }
            }
          }

          stage('Vulnerability Scan') {
            steps {
              // Scans the image built by 'Build Image' in this cell.
              //
              // Goes through jenkins-shared's vulnerabilityScan() rather than calling
              // nexusPolicyEvaluation() directly. That wrapper is NOT boilerplate: it
              // supplies the container scanner's license
              // (NEXUS_CONTAINER_SCANNING_LICENSE), the scanner image, and both Docker
              // Hub and sonatype.repo registry credentials via runEvaluation(). Calling
              // nexusPolicyEvaluation() bare would run unlicensed and without registry
              // auth. It passes the stage name into the closure.
              //
              // iqStage: 'build' on the deploy branch, 'develop' elsewhere -- matches the
              // previous Jenkinsfiles so branch builds use the develop policy.
              //
              // unstableBuildOnScanningWarnings: false is deliberate (CLM-44294): IQ
              // policy WARNINGS must not mark the build unstable. FAILURES still fail it.
              script {
                String iqStage = env.BRANCH_NAME == deployBranch ? 'build' : 'develop'
                String iqApplication = variants[env.IMAGE].iqApplication
                String scanTarget = imageTag(env.IMAGE)
                vulnerabilityScan({ String theStage ->
                  nexusPolicyEvaluation(
                      iqApplication: iqApplication,
                      iqScanPatterns: [[scanPattern: "container:${scanTarget}"]],
                      iqStage: theStage,
                      unstableBuildOnScanningWarnings: false)
                }, iqStage)
              }
            }
          }

          // Two non-host-platform stages, at most one of which runs, and neither runs for
          // a variant with smokePlatform == null. The stage name in the build UI tells
          // you which coverage you got rather than hiding it in a build arg.
          stage('Smoke Build') {
            when {
              allOf {
                not { branch 'main' }
                expression { variants[env.IMAGE].smokePlatform != null }
              }
            }
            steps {
              // Branch builds: `builder` stage only. Catches the arch-conditional tarball
              // and SHA256 selection without the emulated OpenSSH compile. Does NOT cover
              // openssh-builder or the runtime stage -- that is the full build below.
              script {
                buildPlatform(builderName, variants[env.IMAGE].dockerfile,
                    variants[env.IMAGE].smokePlatform, smokeBuildTarget)
              }
            }
          }

          stage('Full Build') {
            when {
              allOf {
                branch 'main'
                expression { variants[env.IMAGE].smokePlatform != null }
              }
            }
            steps {
              // Deploy branch: the whole graph, including the emulated OpenSSH compile.
              // Slow (12+ min) but this is the only place the non-host runtime stage gets
              // built before release.
              script {
                buildPlatform(builderName, variants[env.IMAGE].dockerfile,
                    variants[env.IMAGE].smokePlatform, null)
              }
            }
          }
        }

        post {
          always {
            // Per-cell, because the files live in this cell's workspace. The readiness
            // log is not a test report but is the first thing you want on a failure.
            archiveArtifacts artifacts: "${testResultsDir}/readiness.log",
                allowEmptyArchive: true, fingerprint: false
          }
          cleanup {
            script {
              sh "docker image rm --force ${imageTag(env.IMAGE)} || true"
            }
            deleteDir()
          }
        }
      }
    }

    // Build-wide gate, after every cell has published. getTestResults(currentBuild)
    // reads the build's aggregated test results, so it deliberately runs ONCE here
    // rather than inside a cell: inside a cell it would also see the other variant's
    // failures and report them against the wrong image.
    stage('Verify Test Results') {
      steps {
        script {
          def testResults = getTestResults(currentBuild)
          def failCount = testResults['failCount'] ?: 0
          if (failCount > 0) {
            error("Image validation failed: ${failCount} failing check(s) across all " +
                'variants. See the test report.')
          }
        }
      }
    }
  }

  post {
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
    cleanup {
      deleteDir()
    }
  }
}

// Local image tag for one variant. Keyed on BUILD_NUMBER so concurrent branch builds
// cannot collide on the same agent.
String imageTag(String variant) {
  return "docker-nexus-iq-server-${variant}:${env.BUILD_NUMBER}"
}
