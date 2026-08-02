pipeline {
    agent { label 'build-agent' }

    tools {
        jdk 'JDK11'
        maven 'Maven3'
    }

    environment {
        APP_NAME           = 'springboot-devsecops'
        DOCKERHUB_USERNAME = 'minabisa90'
        DOCKERHUB_REPO     = "${DOCKERHUB_USERNAME}/${APP_NAME}"

        // Jenkins credential IDs
        DOCKERHUB_CREDS    = 'dockerhub'

        // Must match Manage Jenkins → System → SonarQube Servers
        SONARQUBE_SERVER   = 'SonarQube'

        // Must match Manage Jenkins → Tools
        SONAR_SCANNER      = 'SonarScanner'

        IMAGE_TAG          = "${BUILD_NUMBER}"
        IMAGE_NAME         = "${DOCKERHUB_REPO}:${IMAGE_TAG}"
        LATEST_IMAGE       = "${DOCKERHUB_REPO}:latest"
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 45, unit: 'MINUTES')
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    echo "Branch: ${BRANCH_NAME:-unknown}"
                    echo "Commit: $(git rev-parse --short HEAD)"
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    mvn --version
                    mvn clean compile -B
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    mvn test -B
                '''
            }

            post {
                always {
                    junit allowEmptyResults: true,
                          testResults: 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Code Coverage') {
            steps {
                sh '''
                    mvn jacoco:report -B
                    test -f target/site/jacoco/index.html
                '''
            }

            post {
                always {
                    archiveArtifacts(
                        artifacts: 'target/site/jacoco/**/*',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('Package') {
            steps {
                sh '''
                    mvn package -DskipTests -B
                    ls -lh target/*.jar
                '''
            }

            post {
                success {
                    archiveArtifacts(
                        artifacts: 'target/*.jar',
                        fingerprint: true
                    )
                }
            }
        }

        stage('SCA - OWASP Dependency Check') {
            steps {
                sh '''
                    mvn org.owasp:dependency-check-maven:check \
                      -Dformat=ALL \
                      -DfailBuildOnCVSS=9 \
                      -B
                '''
            }

            post {
                always {
                    archiveArtifacts(
                        artifacts: 'target/dependency-check-report.*',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('SAST - SonarQube') {
            steps {
                script {
                    def scannerHome = tool "${SONAR_SCANNER}"

                    withSonarQubeEnv("${SONARQUBE_SERVER}") {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=springboot-devsecops \
                              -Dsonar.projectName=springboot-devsecops \
                              -Dsonar.projectVersion=${BUILD_NUMBER} \
                              -Dsonar.sources=src/main/java \
                              -Dsonar.tests=src/test/java \
                              -Dsonar.java.binaries=target/classes \
                              -Dsonar.java.test.binaries=target/test-classes \
                              -Dsonar.junit.reportPaths=target/surefire-reports \
                              -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                        """
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                      --pull \
                      -t "${IMAGE_NAME}" \
                      -t "${LATEST_IMAGE}" \
                      .
                '''
            }
        }

        stage('Scan Docker Image') {
            steps {
                sh '''
                    trivy image \
                      --exit-code 0 \
                      --severity LOW,MEDIUM \
                      --format table \
                      "${IMAGE_NAME}"

                    trivy image \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --format table \
                      --output trivy-image-report.txt \
                      "${IMAGE_NAME}"
                '''
            }

            post {
                always {
                    archiveArtifacts(
                        artifacts: 'trivy-image-report.txt',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: "${DOCKERHUB_CREDS}",
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_TOKEN'
                    )
                ]) {
                    sh '''
                        echo "${DOCKER_TOKEN}" | \
                          docker login \
                          --username "${DOCKER_USER}" \
                          --password-stdin

                        docker push "${IMAGE_NAME}"
                        docker push "${LATEST_IMAGE}"

                        docker logout
                    '''
                }
            }
        }

        /*
        stage('Deploy to Kubernetes') {
            steps {
                sh """
                    sed -i \
                      's|minabisa90/springboot-devsecops:.*|${IMAGE_NAME}|' \
                      kubernetes/deployment.yaml

                    kubectl apply -f kubernetes/namespace.yaml
                    kubectl apply -f kubernetes/deployment.yaml
                    kubectl apply -f kubernetes/service.yaml

                    kubectl rollout status \
                      deployment/springboot-devsecops \
                      -n springboot-devsecops \
                      --timeout=180s
                """
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    chmod +x kubernetes/smoke-test.sh
                    ./kubernetes/smoke-test.sh
                '''
            }
        }
        */
    }

    post {
        always {
            sh '''
                docker logout >/dev/null 2>&1 || true
                docker image rm "${IMAGE_NAME}" >/dev/null 2>&1 || true
                docker image rm "${LATEST_IMAGE}" >/dev/null 2>&1 || true
            '''

            cleanWs(
                deleteDirs: true,
                notFailBuild: true
            )
        }

        success {
            echo "Pipeline completed successfully."
            echo "Docker image: ${IMAGE_NAME}"
        }

        failure {
            echo 'Pipeline failed. Review the failed stage logs.'
        }
    }
}
