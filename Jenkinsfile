pipeline {
    agent {
        label 'docker-agent'
    }

    environment {
        AWS_REGION     = 'us-east-1'
        ACCOUNT_ID     = '905418155092'
        ECR_REPO       = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/jenkins-ecs-pipeline-app"
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        ECS_CLUSTER    = 'jenkins-ecs-pipeline-cluster'
        ECS_SERVICE    = 'jenkins-ecs-pipeline-service'
        ECS_TASK_FAMILY = 'jenkins-ecs-pipeline-task'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install & Test') {
            steps {
                dir('app') {
                    sh 'pip3 install -r requirements.txt'
                    sh 'PYTHONPATH=. python3 -m pytest tests/ -v'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                dir('app') {
                    sh "docker build -t $ECR_REPO:$IMAGE_TAG -t $ECR_REPO:latest ."
                }
            }
        }

        stage('Push to ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region $AWS_REGION | \
                    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                    docker push $ECR_REPO:$IMAGE_TAG
                    docker push $ECR_REPO:latest
                """
            }
        }

        stage('Deploy to ECS') {
            steps {
                sh """
                    aws ecs update-service \
                        --cluster $ECS_CLUSTER\
                        --service $ECS_SERVICE \
                        --force-new-deployment \
                        --region $AWS_REGION
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    echo "Deployment complete! Waiting for health checks..."
                    sleep 30
                    echo "Check your app at the ALB URL"
                """
            }
        }
    }

    post {
        success {
            echo '✅ Pipeline succeeded!'
        }
        failure {
            echo '❌ Pipeline failed!'
        }
    }
}