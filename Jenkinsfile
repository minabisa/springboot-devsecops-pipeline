pipeline {
    agent { label 'build-agent' }

    tools {
        jdk 'JDK11'
        maven 'Maven3'
    }

    environment {
        APP_NAME             = 'springboot-devsecops'
        DOCKERHUB_USERNAME   = 'minabisa90'
        DOCKER_REPOSITORY    = "${DOCKERHUB_USERNAME}/${APP_NAME}"

        IMAGE_TAG            = "${BUILD_NUMBER}"
        IMAGE_NAME           = "${DOCKER_REPOSITORY}:${IMAGE_TAG}"
        LATEST_IMAGE         = "${DOCKER_REPOSITORY}:latest"

        DOCKER_CREDENTIAL_ID = 'dockerhub'
        NVD_CREDENTIAL_ID    = 'nvd-api-key'

        SONAR_SERVER_NAME    = 'SonarQube'
        SONAR_SCANNER_NAME   = 'SonarScanner'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')

        buildDiscarder(
            logRotator(
                numToKeepStr: '10',
                artifactNumToKeepStr: '5'
            )
        )
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    echo "Repository information"
                    echo "Branch: $(git branch --show-current)"
                    echo "Commit: $(git rev-parse --short HEAD)"
                    echo "Author: $(git log -1 --pretty=format:'%an')"
                '''
            }
        }

        stage('Build, Test and Coverage') {
            steps {
                sh '''
                    echo "Java version:"
                    java -version

                    echo "Maven version:"
                    mvn -version

                    echo "Building application and running tests..."
                    mvn clean verify -B
                '''
            }

            post {
                always {
                    junit(
                        allowEmptyResults: false,
                        testResults: 'target/surefire-reports/*.xml'
                    )

                    archiveArtifacts(
                        artifacts: '''
                            target/*.jar,
                            target/site/jacoco/**/*,
                            target/surefire-reports/**/*
                        ''',
                        allowEmptyArchive: true,
                        fingerprint: true
                    )
                }
            }
        }

        stage('Verify Build Output') {
            steps {
                sh '''
                    echo "Checking generated files..."

                    test -d target/classes
                    test -f target/site/jacoco/jacoco.xml

                    JAR_FILE=$(find target \
                      -maxdepth 1 \
                      -type f \
                      -name "*.jar" \
                      ! -name "*.original" \
                      | head -n 1)

                    if [ -z "${JAR_FILE}" ]; then
                        echo "No application JAR was generated."
                        exit 1
                    fi

                    echo "Application JAR: ${JAR_FILE}"
                    ls -lh "${JAR_FILE}"
                '''
            }
        }

        stage('SCA - OWASP Dependency Check') {
            steps {
                withCredentials([
                    string(
                        credentialsId: "${NVD_CREDENTIAL_ID}",
                        variable: 'NVD_API_KEY'
                    )
                ]) {
                    sh '''
                        echo "Running OWASP Dependency-Check..."

                        mvn \
                          org.owasp:dependency-check-maven:12.2.2:check \
                          -DnvdApiKeyEnvironmentVariable=NVD_API_KEY \
                          -Dformats=HTML,JSON \
                          -DfailBuildOnCVSS=11 \
                          -B
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts(
                        artifacts: '''
                            target/dependency-check-report.html,
                            target/dependency-check-report.json
                        ''',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('SAST - SonarQube Analysis') {
            steps {
                script {
                    def sonarScannerHome = tool "${SONAR_SCANNER_NAME}"

                    withSonarQubeEnv("${SONAR_SERVER_NAME}") {
                        sh """
                            ${sonarScannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=springboot-devsecops \
                              -Dsonar.projectName=SpringBoot-DevSecOps \
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
                    echo "Building Docker image from the existing JAR..."

                    docker build \
                      --pull \
                      --tag "${IMAGE_NAME}" \
                      --tag "${LATEST_IMAGE}" \
                      .

                    docker image inspect "${IMAGE_NAME}"
                '''
            }
        }

        stage('Scan Docker Image') {
            steps {
                sh '''
                    echo "Creating Trivy reports..."

                    trivy image \
                      --format table \
                      --severity LOW,MEDIUM,HIGH,CRITICAL \
                      --output trivy-image-report.txt \
                      "${IMAGE_NAME}"

                    trivy image \
                      --format json \
                      --severity HIGH,CRITICAL \
                      --output trivy-image-report.json \
                      "${IMAGE_NAME}"

                    echo "Reporting mode enabled for the first pipeline run."

                    trivy image \
                      --exit-code 0 \
                      --ignore-unfixed \
                      --severity HIGH,CRITICAL \
                      "${IMAGE_NAME}"
                '''
            }

            post {
                always {
                    archiveArtifacts(
                        artifacts: '''
                            trivy-image-report.txt,
                            trivy-image-report.json
                        ''',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: "${DOCKER_CREDENTIAL_ID}",
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_TOKEN'
                    )
                ]) {
                    sh '''
                        set +x

                        echo "${DOCKER_TOKEN}" |
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

        stage('Verify Published Image') {
            steps {
                sh '''
                    echo "Published images:"
                    echo "${IMAGE_NAME}"
                    echo "${LATEST_IMAGE}"
                '''
            }
        }

        /*
        Enable these stages only after Kubernetes is running.

        stage('Deploy to Kubernetes') {
            steps {
                sh """
                    kubectl set image \
                      deployment/springboot-devsecops \
                      springboot-devsecops=${IMAGE_NAME} \
                      --namespace springboot-devsecops

                    kubectl rollout status \
                      deployment/springboot-devsecops \
                      --namespace springboot-devsecops \
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
        success {
            echo 'DevSecOps pipeline completed successfully.'
            echo "Published image: ${IMAGE_NAME}"
        }

        failure {
            echo 'Pipeline failed. Check the failed stage console output.'
        }

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
    }
}

