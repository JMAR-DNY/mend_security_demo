#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo environment..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p jenkins/init.groovy.d jenkins/jobs workspace

# Start services
echo "🐳 Starting Docker services..."
docker-compose up -d

# Function to check if service is responding
check_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:$port >/dev/null 2>&1; then
            echo "✅ $service_name is ready"
            return 0
        fi
        echo "⏳ Waiting for $service_name... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    echo "❌ $service_name failed to start within timeout"
    return 1
}

# Function to check Docker container health
check_container_health() {
    local container_name=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' $container_name 2>/dev/null || echo "none")
        local running_status=$(docker inspect --format='{{.State.Running}}' $container_name 2>/dev/null || echo "false")
        
        if [ "$running_status" = "true" ]; then
            if [ "$health_status" = "healthy" ] || [ "$health_status" = "none" ]; then
                echo "✅ $container_name is ready"
                return 0
            fi
        fi
        
        echo "⏳ Waiting for $container_name... (attempt $attempt/$max_attempts) [running: $running_status, health: $health_status]"
        sleep 10
        ((attempt++))
    done
    
    echo "❌ $container_name failed to start within timeout"
    return 1
}

# Wait for PostgreSQL using container health check
echo "⏳ Waiting for PostgreSQL to start..."
check_container_health "dt-postgres"

echo "⏳ Waiting for Dependency Track API (this takes 3-5 minutes)..."
check_service "Dependency Track API" 8081

echo "⏳ Waiting for Jenkins to start and install plugins (this takes 2-3 minutes)..."
check_service "Jenkins" 8080

# Give Jenkins extra time to fully initialize plugins
echo "⏳ Allowing extra time for Jenkins plugin initialization..."
sleep 60

# Create credentials via Jenkins API
echo "🔑 Creating Jenkins credentials..."
JENKINS_URL="http://admin:admin@localhost:8080"

# Create credential
curl -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
  --data-urlencode 'json={
    "": "0",
    "credentials": {
      "scope": "GLOBAL",
      "id": "dt-api-key",
      "description": "Dependency Track API Key",
      "secret": "placeholder-api-key",
      "$class": "org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl"
    }
  }' \
  --fail --silent --show-error || echo "⚠️ Credential creation failed (may already exist)"

# Create Jenkins job via API
echo "🔧 Creating Jenkins pipeline job..."

# Read the pipeline script from our job config
PIPELINE_SCRIPT=$(cat << 'EOF'
pipeline {
    agent any
    
    environment {
        DT_API_URL = 'http://dependency-track-apiserver:8080'
        DT_API_KEY = credentials('dt-api-key')
        WEBGOAT_REPO = 'https://github.com/WebGoat/WebGoat.git'
        WEBGOAT_TAG = 'v8.1.0'
        PROJECT_NAME = 'WebGoat'
        PROJECT_VERSION = '8.1.0'
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo '🔄 Cloning WebGoat v8.1.0...'
                git branch: "${WEBGOAT_TAG}", url: "${WEBGOAT_REPO}"
            }
        }
        
        stage('Build Application') {
            steps {
                echo '🔨 Building WebGoat application...'
                sh '''
                    mvn clean compile package -DskipTests -Dmaven.javadoc.skip=true
                '''
            }
        }
        
        stage('Generate SBOM') {
            steps {
                echo '📋 Generating CycloneDX SBOM...'
                sh '''
                    mvn org.cyclonedx:cyclonedx-maven-plugin:2.7.9:makeAggregateBom \
                        -Dorg.cyclonedx.maven.projectType=application \
                        -Dorg.cyclonedx.maven.schemaVersion=1.4 \
                        -Dorg.cyclonedx.maven.outputFormat=json \
                        -Dorg.cyclonedx.maven.outputName=webgoat-bom
                '''
            }
        }
        
        stage('Upload to Dependency Track') {
            steps {
                echo '⬆️ Uploading SBOM to Dependency Track...'
                script {
                    try {
                        def uploadResponse = httpRequest(
                            httpMode: 'POST',
                            url: "${DT_API_URL}/api/v1/bom",
                            customHeaders: [[name: 'X-API-Key', value: "${DT_API_KEY}"]],
                            multipartName: 'bom',
                            uploadFile: 'target/webgoat-bom.json'
                        )
                        
                        echo "✅ SBOM upload response: ${uploadResponse.status}"
                        
                    } catch (Exception e) {
                        echo "❌ Failed to upload SBOM: ${e.getMessage()}"
                        echo "This is expected with placeholder API key"
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo '📊 Archiving artifacts...'
            archiveArtifacts artifacts: '**/webgoat-bom.json', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'target/*.war', fingerprint: true, allowEmptyArchive: true
        }
        success {
            echo '✅ Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed. Check the logs for details.'
        }
    }
}
EOF
)

# Create job configuration XML
JOB_CONFIG=$(cat << EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>WebGoat v8.1.0 Security Scan Pipeline - Automated SBOM generation and upload</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers/>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>$PIPELINE_SCRIPT</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF
)

# Create the job
curl -X POST "$JENKINS_URL/createItem?name=webgoat-security-scan" \
  -H "Content-Type: application/xml" \
  --data "$JOB_CONFIG" \
  --fail --silent --show-error || echo "⚠️ Job creation failed (may already exist)"

echo "✅ Setup complete!"
echo ""
echo "🌐 Access your services:"
echo "   Jenkins: http://localhost:8080 (admin/admin)"
echo "   Dependency Track: http://localhost:8081 (admin/admin)"
echo "   Dependency Track Frontend: http://localhost:8082"
echo ""
echo "🎬 The 'webgoat-security-scan' job should now be available in Jenkins"
echo "   You can run the demo with: make demo"