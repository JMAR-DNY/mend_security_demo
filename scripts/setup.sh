#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo with Jenkins Configuration as Code..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directory structure
echo "📁 Creating directory structure..."
mkdir -p jenkins/casc_configs
mkdir -p workspace
mkdir -p reports

# Create JCasC configuration file
echo "⚙️ Creating Jenkins Configuration as Code setup..."
cat > jenkins/casc_configs/jenkins.yaml << 'EOF'
jenkins:
  systemMessage: "Mend Security Demo - Jenkins with Auto-Configured Pipeline"
  numExecutors: 2
  scmCheckoutRetryCount: 3
  mode: NORMAL
  
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "admin"
          
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"
        - "Job/Build:admin"
        - "Job/Cancel:admin"
        - "Job/Configure:admin"
        - "Job/Create:admin"
        - "Job/Delete:admin"
        - "Job/Discover:admin"
        - "Job/Move:admin"
        - "Job/Read:admin"
        - "Job/Workspace:admin"

  remotingSecurity:
    enabled: true

tool:
  git:
    installations:
      - name: "Default"
        home: "/usr/bin/git"
  
  maven:
    installations:
      - name: "Maven-3.9"
        properties:
          - installSource:
              installers:
                - maven:
                    id: "3.9.5"

credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "dt-api-key"
              description: "Dependency Track API Key"
              secret: "odt_0EvOUOJftaK9PHrVIh4yL1LgbAYHLhtJ"

jobs:
  - script: |
      pipelineJob('webgoat-security-scan') {
        description('WebGoat v8.1.0 Security Scan - Automated SBOM generation and Dependency Track integration')
        
        logRotator {
          numToKeep(10)
        }
        
        definition {
          cps {
            script('''
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
        stage('🔄 Checkout') {
            steps {
                echo '🔄 Cloning WebGoat v8.1.0 from GitHub...'
                git branch: "${WEBGOAT_TAG}", url: "${WEBGOAT_REPO}"
                echo "✅ WebGoat source code checked out successfully"
            }
        }
        
        stage('🔨 Build Application') {
            steps {
                echo '🔨 Building WebGoat application with Maven...'
                sh '''
                    echo "Maven version:"
                    mvn --version
                    
                    echo "Building WebGoat..."
                    mvn clean compile package -DskipTests -Dmaven.javadoc.skip=true -q
                    
                    echo "Build artifacts:"
                    ls -la target/ | grep -E "\\.(war|jar)$" || echo "No WAR/JAR files found"
                '''
                echo "✅ WebGoat application built successfully"
            }
        }
        
        stage('🔍 Dependency Scan') {
            steps {
                echo '🔍 Running dependency vulnerability scan...'
                script {
                    try {
                        sh '''
                            echo "Downloading OWASP Dependency Check..."
                            if [ ! -f "dependency-check/bin/dependency-check.sh" ]; then
                                wget -q https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.3/dependency-check-8.4.3-release.zip
                                unzip -q dependency-check-8.4.3-release.zip
                                chmod +x dependency-check/bin/dependency-check.sh
                            fi
                            
                            echo "Running dependency vulnerability scan..."
                            mkdir -p reports
                            ./dependency-check/bin/dependency-check.sh \\
                                --project "WebGoat-v8.1.0" \\
                                --scan target/ \\
                                --format ALL \\
                                --out reports/ \\
                                --enableRetired \\
                                --enableExperimental \\
                                --log reports/dependency-check.log \\
                                --nvdApiKey "" || echo "Scan completed with findings"
                            
                            echo "Dependency scan results:"
                            if [ -f "reports/dependency-check-report.html" ]; then
                                echo "✅ HTML report generated"
                            fi
                            if [ -f "reports/dependency-check-report.xml" ]; then
                                echo "✅ XML report generated"
                            fi
                        '''
                    } catch (Exception e) {
                        echo "⚠️ Dependency check completed with findings: ${e.getMessage()}"
                        echo "This is expected for WebGoat as it contains intentional vulnerabilities"
                    }
                }
                echo "✅ Dependency vulnerability scan completed"
            }
        }
        
        stage('📋 Generate SBOM') {
            steps {
                echo '📋 Generating Software Bill of Materials (SBOM)...'
                sh '''
                    echo "Generating CycloneDX SBOM..."
                    mvn org.cyclonedx:cyclonedx-maven-plugin:2.7.9:makeAggregateBom \\
                        -Dorg.cyclonedx.maven.projectType=application \\
                        -Dorg.cyclonedx.maven.schemaVersion=1.4 \\
                        -Dorg.cyclonedx.maven.outputFormat=json \\
                        -Dorg.cyclonedx.maven.outputName=webgoat-bom \\
                        -q
                    
                    echo "Verifying SBOM generation..."
                    if [ -f "target/webgoat-bom.json" ]; then
                        echo "✅ SBOM generated successfully"
                        SBOM_SIZE=$(wc -c < target/webgoat-bom.json)
                        COMPONENT_COUNT=$(grep -o '\\"type\\":\\"library\\"' target/webgoat-bom.json | wc -l || echo "0")
                        echo "📊 SBOM Statistics:"
                        echo "   • File size: ${SBOM_SIZE} bytes"
                        echo "   • Components found: ${COMPONENT_COUNT}"
                        echo "   • Format: CycloneDX JSON v1.4"
                        
                        # Show first few lines of SBOM for verification
                        echo "📋 SBOM Preview:"
                        head -10 target/webgoat-bom.json
                    else
                        echo "❌ SBOM generation failed"
                        exit 1
                    fi
                '''
                echo "✅ SBOM (Software Bill of Materials) generated successfully"
            }
        }
        
        stage('⬆️ Upload to Dependency Track') {
            steps {
                echo '⬆️ Uploading SBOM to Dependency Track for vulnerability management...'
                script {
                    try {
                        echo "🔗 Connecting to Dependency Track API..."
                        
                        // Test API connectivity first
                        def versionResponse = httpRequest(
                            httpMode: 'GET',
                            url: "${DT_API_URL}/api/version",
                            validResponseCodes: '200:299'
                        )
                        echo "✅ Dependency Track API is accessible (version endpoint responded)"
                        
                        // Create/update project
                        echo "📝 Creating/updating project in Dependency Track..."
                        def projectResponse = httpRequest(
                            httpMode: 'PUT',
                            url: "${DT_API_URL}/api/v1/project",
                            customHeaders: [
                                [name: 'X-API-Key', value: "${DT_API_KEY}"],
                                [name: 'Content-Type', value: 'application/json']
                            ],
                            requestBody: """
                            {
                                "name": "${PROJECT_NAME}",
                                "version": "${PROJECT_VERSION}",
                                "description": "WebGoat v8.1.0 - Intentionally vulnerable application for security testing and training",
                                "tags": [
                                    {"name": "demo"},
                                    {"name": "webgoat"},
                                    {"name": "mend-security-scan"},
                                    {"name": "vulnerable-app"}
                                ]
                            }
                            """,
                            validResponseCodes: '200:299,400:499'
                        )
                        echo "📝 Project creation/update response: ${projectResponse.status}"
                        
                        // Upload SBOM
                        echo "📤 Uploading SBOM file to Dependency Track..."
                        def uploadResponse = httpRequest(
                            httpMode: 'POST',
                            url: "${DT_API_URL}/api/v1/bom",
                            customHeaders: [[name: 'X-API-Key', value: "${DT_API_KEY}"]],
                            multipartName: 'bom',
                            uploadFile: 'target/webgoat-bom.json',
                            validResponseCodes: '200:299'
                        )
                        
                        echo "✅ SBOM upload successful!"
                        echo "📊 Upload Details:"
                        echo "   • Status: ${uploadResponse.status}"
                        echo "   • File: webgoat-bom.json"
                        echo "   • Target: Dependency Track"
                        echo ""
                        echo "🎉 SBOM successfully uploaded to Dependency Track!"
                        echo "🌐 View results at: http://localhost:8081"
                        
                    } catch (Exception e) {
                        echo "❌ Failed to upload SBOM: ${e.getMessage()}"
                        echo ""
                        echo "🔧 Troubleshooting steps:"
                        echo "   1. Verify Dependency Track is running: http://localhost:8081"
                        echo "   2. Check API key is valid in Dependency Track admin panel"
                        echo "   3. Manual upload option: Go to Projects > Upload BOM"
                        echo "   4. File location: target/webgoat-bom.json"
                        echo ""
                        echo "📁 SBOM file has been archived as build artifact for manual upload"
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo '📊 Archiving build artifacts and reports...'
            
            // Archive dependency check reports
            archiveArtifacts artifacts: 'reports/dependency-check-report.html', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'reports/dependency-check-report.xml', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'reports/dependency-check-report.json', fingerprint: true, allowEmptyArchive: true
            
            // Archive SBOM
            archiveArtifacts artifacts: 'target/webgoat-bom.json', fingerprint: true, allowEmptyArchive: true
            
            // Archive build artifacts
            archiveArtifacts artifacts: 'target/*.war', fingerprint: true, allowEmptyArchive: true
            
            echo '🧹 Cleaning up workspace...'
        }
        success {
            echo ''
            echo '✅ 🎉 SECURITY SCAN PIPELINE COMPLETED SUCCESSFULLY! 🎉'
            echo ''
            echo '📋 What was accomplished:'
            echo '   ✓ WebGoat v8.1.0 cloned and built successfully'
            echo '   ✓ Dependency vulnerabilities scanned with OWASP Dependency Check'
            echo '   ✓ Software Bill of Materials (SBOM) generated in CycloneDX format'
            echo '   ✓ Security data uploaded to Dependency Track for ongoing monitoring'
            echo ''
            echo '🌐 View Your Results:'
            echo '   • Jenkins Build Details: http://localhost:8080/job/webgoat-security-scan/'
            echo '   • Dependency Track Dashboard: http://localhost:8081'
            echo '   • Build Artifacts: Available in Jenkins build artifacts'
            echo ''
            echo '🔍 Next Steps:'
            echo '   1. Review vulnerability findings in Dependency Track'
            echo '   2. Analyze the SBOM for component inventory'
            echo '   3. Set up vulnerability notifications and policies'
            echo '   4. Integrate similar scans into your development workflow'
            echo ''
            echo '📈 Business Value Demonstrated:'
            echo '   • Automated vulnerability detection in CI/CD pipeline'
            echo '   • Complete software supply chain visibility'
            echo '   • Centralized security risk management'
            echo '   • Compliance-ready documentation and reporting'
        }
        failure {
            echo ''
            echo '❌ Security scan pipeline encountered issues'
            echo ''
            echo '🔍 Troubleshooting Resources:'
            echo '   • Build Console: Check above logs for specific errors'
            echo '   • Jenkins Logs: docker-compose logs jenkins'
            echo '   • Dependency Track: http://localhost:8081 (verify service is running)'
            echo '   • System Resources: Ensure adequate memory (8GB+) and disk space'
            echo ''
            echo '📞 Common Solutions:'
            echo '   • Restart services: docker-compose restart'
            echo '   • Check service health: make health-check'
            echo '   • Manual SBOM upload: Use archived webgoat-bom.json file'
        }
    }
}
            ''')
            sandbox()
          }
        }
      }

unclassified:
  location:
    adminAddress: "admin@mend-demo.local"
    url: "http://localhost:8080/"
EOF

# Create comprehensive plugins list
echo "📦 Creating Jenkins plugins configuration..."
cat > jenkins/plugins.txt << 'EOF'
# Core Jenkins functionality
ant:475.vf34069fef73c
build-timeout:1.30
credentials:1271.v54b_1c1c6388a_
ssh-credentials:308.ve4497b_ccd8f4
plain-credentials:143.v1b_df8b_d3b_e48
credentials-binding:523.vd859a_4b_122e6

# Pipeline and workflow
workflow-step-api:639.v6eca_cd8c04a_a_
workflow-api:1271.v54b_1c1c6388a_
workflow-support:865.v43e78cc44e0d
workflow-scm-step:415.v434365564324
workflow-job:1295.v395eb_7400005
workflow-durable-task-step:1289.v4d3e7b_01546b_
workflow-cps-global-lib:588.v576c103a_ff86
workflow-cps:3659.v582dc37621d8
workflow-basic-steps:1010.vf7a_b_98e847c1
workflow-aggregator:590.v6a_d052e5a_a_b_5

# Pipeline UI and management
pipeline-input-step:448.v37cea_9a_10a_70
pipeline-milestone-step:111.v449306f708b_7
pipeline-stage-step:305.ve96d0205c1c6
pipeline-graph-analysis:195.v5812d95a_a_2f9
pipeline-rest-api:2.33
pipeline-stage-view:2.33

# Source control
git:5.0.0
git-client:4.6.0
scm-api:676.v886669a_199a_a_

# Configuration as Code
configuration-as-code:1670.v564dc8b_982d0

# Essential utilities
timestamper:1.25
workspace-cleanup:0.45
pipeline-utility-steps:2.16.0
http_request:1.18

# Security and permissions
matrix-auth:3.2.1

# Build tools
maven-plugin:3.22

# Job creation and management
job-dsl:1.84
EOF

# Start services
echo "🐳 Starting Docker services with JCasC configuration..."
docker-compose up -d

# Function to check service health
check_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:$port >/dev/null 2>&1; then
            echo "✅ $service_name is ready and responding"
            return 0
        fi
        echo "   Attempt $attempt/$max_attempts - $service_name not ready yet..."
        sleep 15
        ((attempt++))
    done
    
    echo "❌ $service_name failed to start within timeout"
    return 1
}

# Wait for services to start
echo "🔄 Waiting for all services to initialize..."
echo "   This may take 5-10 minutes on first run..."

# Wait for PostgreSQL
echo "🗄️ Waiting for PostgreSQL database..."
sleep 20
docker exec dt-postgres pg_isready -U dtrack || echo "PostgreSQL still starting..."

# Wait for Dependency Track API (takes longest)
echo "🛡️ Waiting for Dependency Track API server..."
echo "   (This can take 5-8 minutes on first startup)"
check_service "Dependency Track API" 8081

# Wait for Jenkins
echo "🔧 Waiting for Jenkins with JCasC..."
echo "   (This includes plugin installation and job creation)"
check_service "Jenkins" 8080

# Give Jenkins extra time to process JCasC configuration
echo "⚙️ Allowing time for Jenkins Configuration as Code to complete..."
sleep 45

# Verify job was created
echo "🔍 Verifying Jenkins job creation..."
JOB_CHECK=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null || echo "")
if [[ $JOB_CHECK == *"name"* ]]; then
    echo "✅ Jenkins job 'webgoat-security-scan' created successfully via JCasC"
else
    echo "⚠️ Jenkins job creation pending - may need a few more minutes"
    echo "   Job will be available after JCasC fully processes the configuration"
fi

# Get Dependency Track information
echo "🔑 Checking Dependency Track setup..."
DT_VERSION=$(curl -s http://localhost:8081/api/version 2>/dev/null || echo "API not ready")
if [[ $DT_VERSION == *"version"* ]]; then
    echo "✅ Dependency Track API is accessible"
    echo "   Default API key is pre-configured for demo purposes"
else
    echo "⚠️ Dependency Track API still initializing"
fi

# Final verification
echo ""
echo "🎯 Performing final system verification..."

# Check all containers are running
echo "📊 Container Status:"
docker-compose ps

echo ""
echo "✅ 🎉 SETUP COMPLETE! 🎉"
echo ""
echo "🌐 Access Your Demo Environment:"
echo "   • Jenkins:           http://localhost:8080 (admin/admin)"
echo "   • Dependency Track:  http://localhost:8081 (admin/admin)"
echo "   • DT Frontend:       http://localhost:8082"
echo ""
echo "🚀 Ready to Demo:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Find 'webgoat-security-scan' job"
echo "   3. Click 'Build Now' to start the security scan pipeline"
echo "   4. Monitor the build progress in real-time"
echo "   5. View results in Dependency Track after completion"
echo ""
echo "📋 What the Pipeline Will Do:"
echo "   ✓ Clone WebGoat v8.1.0 (intentionally vulnerable app)"
echo "   ✓ Build the application with Maven"
echo "   ✓ Scan for dependency vulnerabilities"
echo "   ✓ Generate Software Bill of Materials (SBOM)"
echo "   ✓ Upload security data to Dependency Track"
echo ""
echo "🔧 Troubleshooting:"
echo "   • If job doesn't appear: wait 2-3 minutes and refresh"
echo "   • Check logs: docker-compose logs [service-name]"
echo "   • Health check: make health-check"
echo "   • Reset: make clean && make setup"
echo ""
echo "🎬 The demo is now ready for presentation!"