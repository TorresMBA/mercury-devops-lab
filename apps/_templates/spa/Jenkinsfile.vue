// Plantilla CI para Vue (proyecto creado con create-vue o Vite). Copiar a la raíz del repo como "Jenkinsfile" y ajustar APP y DIST_DIR.
pipeline {
  agent none

  options {
    timestamps()
    // Un push nuevo cancela el build anterior de este job, aunque esté esperando en "Aprobar prod"
    disableConcurrentBuilds(abortPrevious: true)
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    APP = 'mi-vue'     // nombre de imagen y contenedor: minúsculas y guiones
    DIST_DIR = 'dist'  // carpeta con index.html tras el build (dist con Vite y con Vue CLI)
    TAG = "${BUILD_NUMBER}"
    CI = 'true'        // los tests se ejecutan una vez, sin quedarse en modo observador
  }

  stages {
    stage('CI') {
      // 'node' es la versión por defecto. Para fijar otra: 'node-20', 'node-22' o 'node-24'.
      // La imagen de la app se empaqueta con la misma versión que el agente.
      agent { label 'node' }
      options {
        // Un build colgado no debe ocupar un cupo de agente indefinidamente
        timeout(time: 45, unit: 'MINUTES')
      }
      environment {
        REGISTRY = credentials('registry')
      }
      stages {
        stage('Build y test') {
          steps {
            sh '''
              npm ci
              npm run build
              npm run test:unit --if-present  # create-vue llama así a los tests de Vitest
            '''
          }
        }

        stage('SonarQube') {
          steps {
            withSonarQubeEnv('sonarqube') {
              sh 'mercury-ci sonar "$APP" "-Dsonar.exclusions=node_modules/**,dist/**"'
            }
          }
        }

        // La espera del quality gate no consume recursos: los escáneres corren mientras tanto
        stage('Análisis') {
          failFast true
          parallel {
            stage('Quality gate') {
              steps {
                timeout(time: 10, unit: 'MINUTES') {
                  waitForQualityGate abortPipeline: true
                }
              }
            }

            stage('Seguridad') {
              steps {
                sh '''
                  mercury-ci semgrep
                  mercury-ci trivy-fs
                '''
              }
            }
          }
        }

        stage('Imagen') {
          steps {
            sh '''
              mercury-ci login
              mercury-ci package spa "$DIST_DIR" "$APP" "$TAG"
              mercury-ci trivy-image "$(mercury-ci image-ref "$APP" "$TAG")"
            '''
          }
        }

        stage('Deploy dev') {
          steps {
            sh 'mercury-ci deploy "$APP" dev "$TAG"'
          }
        }
      }
      post {
        always {
          // El agente es efímero: sin esto el informe de Semgrep se pierde
          archiveArtifacts artifacts: 'semgrep.json', allowEmptyArchive: true
        }
      }
    }

    // Sin agente: la espera no ocupa RAM ni un cupo de agente
    stage('Aprobar prod') {
      steps {
        timeout(time: 1, unit: 'DAYS') {
          input message: "¿Promover ${APP}:${TAG} a prod?"
        }
      }
    }

    stage('Deploy prod') {
      agent { label 'base' }
      environment {
        REGISTRY = credentials('registry')
      }
      options {
        skipDefaultCheckout()
        timeout(time: 10, unit: 'MINUTES')
      }
      steps {
        sh '''
          mercury-ci login
          mercury-ci deploy "$APP" prod "$TAG"
        '''
      }
    }
  }
}
