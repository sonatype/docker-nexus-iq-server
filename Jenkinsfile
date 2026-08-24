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

// Builds and validates every IQ Server image variant. Everything runs on the agent;
// licenseCheck() and hadolint() run their tools in throwaway containers on the agent's
// docker. Image validation runs inside the docker build -- see the `test` stage in each
// Dockerfile and the goss*.yaml suites.
//
// No githubStatusUpdate() for the build result on purpose: the job uses the GitHub Branch
// Source plugin, which reports commit status itself.

@Library(['private-pipeline-library', 'jenkins-shared']) _

String deployBranch = 'main'

// Adding an image = one entry here plus its IMAGE axis value below.
//   dockerfile    : the product Dockerfile, untouched by validation.
//   gossfile      : which goss suite Dockerfile.test runs against the built image.
//   iqApplication : IQ application to evaluate against.
//   smokePlatform : non-host platform to build as a smoke test, or null.
//
// smokePlatform is null for rh and alpine because both hardcode an x86_64 tarball with a
// single IQ_SERVER_SHA256, so an arm64 build would pass while producing an image full of
// x86_64 binaries. ubi and hardened select the tarball per architecture (TARGETARCH-driven),
// so both build arm64 correctly.
//
// Dockerfile.slim is deliberately absent: it is byte-identical to Dockerfile, and the slim
// image is published by its own release lane. See CLM-46980.
Map<String, Map<String, String>> variants = [
  'ubi': [
    dockerfile   : 'Dockerfile',
    gossfile     : 'goss.yaml',
    iqApplication: 'docker-nexus-iq-server',
    smokePlatform: 'linux/arm64',
  ],
  'rh': [
    dockerfile   : 'Dockerfile.rh',
    gossfile     : 'goss.rh.yaml',
    iqApplication: 'docker-nexus-iq-server-rh',
    smokePlatform: null,
  ],
  'alpine': [
    dockerfile   : 'Dockerfile.alpine',
    gossfile     : 'goss.alpine.yaml',
    iqApplication: 'docker-nexus-iq-server-alpine',
    smokePlatform: null,
  ],
  // Red Hat Hardened Images (Hummingbird), CLM-46302. Distroless-style runtime staged into
  // /rootfs and copied into hi/core-runtime:latest. Multi-arch via TARGETARCH-driven tarball
  // selection, so arm64 is safe.
  'hardened': [
    dockerfile   : 'Dockerfile.hardened',
    gossfile     : 'goss.hardened.yaml',
    iqApplication: 'docker-nexus-iq-server-hardened',
    smokePlatform: 'linux/arm64',
  ],
]

// Only the host platform can run the test stage without emulation.
String testPlatform = 'linux/amd64'
String testResultsDir = 'build/test-results'
// Branch builds stop at `builder` for the non-host platform: that covers the
// arch-conditional tarball/SHA256 selection and skips compiling OpenSSH under emulation,
// which takes 12+ minutes. main gets the full build.
String smokeBuildTarget = 'builder'
String builderName = 'iq-image-multiarch'

// Mirrors jenkins-shared's configureBranchJob(). Declarative options{} cannot be
// conditional, so this is set imperatively.
void configureBranchJob() {
  String projName = currentBuild.fullProjectName
  if (projName.endsWith('main')) {
    properties([
      disableConcurrentBuilds(),
      pipelineTriggers([cron('@daily')])
    ])
  }
}

String imageTag(String variant) {
  return "docker-nexus-iq-server-${variant}:${env.BUILD_NUMBER}"
}

// Builds one non-host platform and DISCARDS the result (--output type=cacheonly). Nothing in
// this pipeline is ever pushed, and a foreign-platform image cannot be loaded into the local
// image store anyway. Publishing happens only in the release lanes:
//   build_and_push_images.sh    -> Docker Hub, multi-arch manifest (Jenkinsfile[.slim].release)
//   build_and_push_rh_image.sh  -> Red Hat ISV registry + preflight cert scan
//   Jenkinsfile.alpine.release  -> Docker Hub, :<version>-alpine / :latest-alpine
//
// buildkit is pinned by digest (v0.31.1) because all buildkit tags are quarantined by
// Sonatype Firewall; this pre-quarantine digest is pullable. Revert to a tag once waived.
void buildPlatform(String builderName, String dockerfile, String platform, String target) {
  withSonatypeDockerRegistry() {
    String buildkitImage = "${sonatypeDockerRegistryId()}/moby/buildkit@sha256:" +
        '6b59b7df63a8cb9902736f9ddf7fcff8261613d3e7449b8ea8b7537fc399c03a'
    // Created if missing and not removed, so later builds on this agent reuse it.
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
    // disableConcurrentBuilds() and the cron are set in configureBranchJob(), main only.
    buildDiscarder(logRotator(numToKeepStr: '30', daysToKeepStr: '90'))
  }

  // Every docker call must be inside withSonatypeDockerRegistry(): it injects the
  // credentials that the agent's docker credential helper consumes. It does not run
  // `docker login`. licenseCheck() and hadolint() wrap themselves.

  stages {
    // Repo-wide, so it runs once rather than per image.
    stage('Compliance Check') {
      steps {
        // branchNamingCheck() and jiraIssueAndPrCheck() are informational and never fail
        // the build, so a green stage does not mean they passed -- check the badges.
        // licenseCheck() does fail the build. Informational ones run first so their
        // badges survive a licenseCheck() failure.
        branchNamingCheck()
        jiraIssueAndPrCheck()
        licenseCheck()
        // Dockerfile.test is shared by every image, so it is linted once here rather than
        // in each matrix cell, which would report one finding four times.
        hadolint(['./Dockerfile.test'])
      }
    }

    // Cells run in parallel. The per-cell agent is required: without it they would share
    // the top-level workspace and fight over build/test-results, image tags and
    // deleteDir(). Not failFast -- one image failing should not hide the others.
    stage('Images') {
      matrix {
        agent {
          label 'ubuntu-zion'
        }

        axes {
          axis {
            name 'IMAGE'
            values 'ubi', 'rh', 'alpine', 'hardened'
          }
        }

        stages {
          stage('Lint') {
            steps {
              script {
                hadolint(["./${variants[env.IMAGE].dockerfile}"])
              }
            }
          }

          // Builds the product image unmodified; validation happens in 'Test Image'
          // against this tag, so the product Dockerfiles carry no test stages.
          stage('Build Image') {
            steps {
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
              script {
                // One shared Dockerfile.test, applied to the image built above.
                // CI=true makes it exit 0 on failure so the report is always exported;
                // the JUnit results own pass/fail. CACHEBUST is required because the
                // test RUN has no file inputs, so BuildKit would serve a cached pass.
                withSonatypeDockerRegistry() {
                  sh """
                    rm -rf ${testResultsDir}
                    docker build --file Dockerfile.test \
                      --target test-results \
                      --platform ${testPlatform} \
                      --build-arg BASE_IMAGE=${imageTag(env.IMAGE)} \
                      --build-arg GOSSFILE=${variants[env.IMAGE].gossfile} \
                      --build-arg CI=true \
                      --build-arg CACHEBUST=\${BUILD_NUMBER} \
                      --output type=local,dest=${testResultsDir} .
                  """
                }
                // goss always names its suite "goss"; without this the cells publish
                // identically-named suites of identically-named cases and the JUnit
                // plugin merges them.
                sh """
                  for f in ${testResultsDir}/*.xml; do
                    [ -e "\$f" ] || continue
                    sed -i 's|<testsuite name="goss|<testsuite name="goss-${env.IMAGE}|' "\$f"
                  done
                """
                collectTestResults(["${testResultsDir}/**/*.xml"])
              }
            }
          }

          stage('Vulnerability Scan') {
            steps {
              script {
                // vulnerabilityScan() rather than a bare nexusPolicyEvaluation(): its
                // runEvaluation() supplies the container scanner licence and the Docker
                // Hub + sonatype.repo credentials, and passes the stage into the closure.
                // unstableBuildOnScanningWarnings: false is deliberate (CLM-44294).
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

          // At most one of these runs, and neither runs when smokePlatform is null.
          stage('Smoke Build') {
            when {
              allOf {
                not { branch 'main' }
                expression { variants[env.IMAGE].smokePlatform != null }
              }
            }
            steps {
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
              script {
                buildPlatform(builderName, variants[env.IMAGE].dockerfile,
                    variants[env.IMAGE].smokePlatform, null)
              }
            }
          }
        }

        post {
          always {
            // Per-cell: the file lives in this cell's workspace.
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

    // Runs once, outside the matrix: getTestResults(currentBuild) is build-wide, so per
    // cell it would see the other variants' failures and blame the wrong image.
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
