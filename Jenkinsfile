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
        SONAR_JDK_NAME       = 'JDK21'

        MAVEN_OPTS           = '-Xms256m -Xmx2g -XX:+UseG1GC'
    }

    options {
        skipDefaultCheckout(true)
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 90, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    echo "Commit: $(git rev-parse --short HEAD)"
                    echo "Author: $(git log -1 --pretty=format:'%an')"
                    echo "Message: $(git log -1 --pretty=format:'%s')"
                '''
            }
        }

        stage('Build, Test and Coverage') {
            steps {
                sh '''
                    java -version
                    mvn -version
                    free -h
                    mvn clean verify -B
                '''
            }

            post {
                always {
                    junit allowEmptyResults: false,
                          testResults: 'target/surefire-reports/*.xml'

                    archiveArtifacts artifacts: 'target/surefire-reports/**/*,target/site/jacoco/**/*',
                                     allowEmptyArchive: true
                }
            }
        }

        stage('Verify Build Output') {
            steps {
                sh '''
                    test -d target/classes
                    test -d target/test-classes
                    test -f target/site/jacoco/jacoco.xml

                    JAR_FILE=$(find target -maxdepth 1 -type f -name "*.jar" ! -name "*.original" | head -n 1)

                    if [ -z "${JAR_FILE}" ]; then
                        echo "Application JAR was not generated."
                        exit 1
                    fi

                    ls -lh "${JAR_FILE}"
                '''
            }

            post {
                success {
                    archiveArtifacts artifacts: 'target/*.jar',
                                     fingerprint: true,
                                     allowEmptyArchive: false
                }
            }
        }

        stage('SCA - OWASP Dependency Check') {
            steps {
                withCredentials([
                    string(credentialsId: "${NVD_CREDENTIAL_ID}", variable: 'NVD_API_KEY')
                ]) {
                    sh '''
                        free -h

                        mvn org.owasp:dependency-check-maven:12.2.2:check                           -DnvdApiKeyEnvironmentVariable=NVD_API_KEY                           -Dformats=HTML,JSON                           -DfailBuildOnCVSS=11                           -B
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts artifacts: 'target/dependency-check-report.html,target/dependency-check-report.json',
                                     allowEmptyArchive: true
                }
            }
        }

        stage('SAST - SonarQube Analysis') {
    steps {
        withSonarQubeEnv('SonarQube') {
            withEnv([
                'JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64',
                'PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                'SONAR_SCANNER_HOME=/opt/sonar-scanner'
            ]) {
                sh '''
                    echo "Java used by SonarScanner:"
                    java -version

                    echo "SonarScanner version:"
                    "${SONAR_SCANNER_HOME}/bin/sonar-scanner" --version

                    "${SONAR_SCANNER_HOME}/bin/sonar-scanner" \
                      -Dsonar.projectKey=springboot-devsecops \
                      -Dsonar.projectName=SpringBoot-DevSecOps \
                      -Dsonar.projectVersion="${BUILD_NUMBER}" \
                      -Dsonar.sources=src/main/java \
                      -Dsonar.tests=src/test/java \
                      -Dsonar.java.binaries=target/classes \
                      -Dsonar.java.test.binaries=target/test-classes \
                      -Dsonar.java.source=8 \
                      -Dsonar.junit.reportPaths=target/surefire-reports \
                      -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                '''
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
                    docker build                       --pull                       --tag "${IMAGE_NAME}"                       --tag "${LATEST_IMAGE}"                       .

                    docker image inspect "${IMAGE_NAME}" >/dev/null
                '''
            }
        }

        stage('Scan Docker Image') {
            steps {
                sh '''
                    trivy image                       --format table                       --severity LOW,MEDIUM,HIGH,CRITICAL                       --output trivy-image-report.txt                       "${IMAGE_NAME}"

                    trivy image                       --format json                       --severity HIGH,CRITICAL                       --output trivy-image-report.json                       "${IMAGE_NAME}"

                    trivy image                       --exit-code 0                       --ignore-unfixed                       --severity HIGH,CRITICAL                       "${IMAGE_NAME}"
                '''
            }

            post {
                always {
                    archiveArtifacts artifacts: 'trivy-image-report.txt,trivy-image-report.json',
                                     allowEmptyArchive: true
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

                        echo "${DOCKER_TOKEN}" | docker login                           --username "${DOCKER_USER}"                           --password-stdin

                        docker push "${IMAGE_NAME}"
                        docker push "${LATEST_IMAGE}"

                        docker logout
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully."
            echo "Published Docker image: ${IMAGE_NAME}"
        }

        failure {
            echo "Pipeline failed. Review the failed stage logs."
        }

        always {
            sh '''
                docker logout >/dev/null 2>&1 || true
                docker image rm "${IMAGE_NAME}" >/dev/null 2>&1 || true
                docker image rm "${LATEST_IMAGE}" >/dev/null 2>&1 || true
            '''

            cleanWs deleteDirs: true, notFailBuild: true
        }
    }
}
