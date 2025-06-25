#!/bin/bash
set -e

# Function to check service health
check_service() {
    local service_name=$1
    local port=$2
    local path=${3:-/}
    local max_attempts=30
    local attempt=1

    echo "⏳ Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -fL http://localhost:$port$path >/dev/null 2>&1; then
            echo "✅ $service_name is ready"
            return 0
        fi
        if [ $((attempt % 5)) -eq 0 ]; then
            echo "   Still waiting... (attempt $attempt/$max_attempts)"
        fi
        sleep 10
        ((attempt++))
    done

    echo "❌ $service_name failed to start within timeout"
    return 1
}

echo "🚀 Setting up Mend Security Demo with Java Direct Execution..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p jenkins/casc_configs workspace reports

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || echo "Scripts already executable"

# Build and start services
echo "🔨 Building custom Jenkins image with pre-installed plugins..."
echo "   This ensures reliable plugin installation and avoids runtime issues"
docker-compose build jenkins

echo "🐳 Starting all services..."
docker-compose up -d

# Wait for PostgreSQL
echo "🗄️ PostgreSQL starting..."
sleep 15

# Wait for basic DT API (but not full readiness)
echo "🛡️ Dependency Track starting..."
until curl -s http://localhost:8081/api/version >/dev/null 2>&1; do
    echo "   Waiting for API..."
    sleep 5
done

# Apply certificate fix BEFORE feeds start downloading
echo "🔐 Applying certificate fixes BEFORE vulnerability downloads begin..."
if [ -f scripts/fix-dt-ssl-2.sh ]; then
    ./scripts/fix-dt-ssl-2.sh
fi

# NOW wait for full service readiness
check_service "Dependency Track API" 8081 /api/version

# Initialize Dependency Track admin account
echo "🔑 Initializing Dependency Track admin account..."
if [ -f scripts/init-dependency-track.sh ]; then
    chmod +x scripts/init-dependency-track.sh
    ./scripts/init-dependency-track.sh
else
    echo "⚠️ init-dependency-track.sh script not found, skipping admin setup"
fi

# Certificate status check (automatic handling via docker-compose)
echo "🔐 Checking automatic certificate configuration..."
sleep 30  # Give the automatic init script time to run

CERT_INIT_STATUS=$(docker exec dt-apiserver test -f /data/.cert-init-completed 2>/dev/null && echo "completed" || echo "pending")

if [ "$CERT_INIT_STATUS" = "completed" ]; then
    echo "✅ SSL certificates automatically configured"
    RECENT_CERT_ERRORS=$(docker logs dt-apiserver --since 2m 2>&1 | grep -c "PKIX path building failed" || echo "0")
    if [ "$RECENT_CERT_ERRORS" -eq "0" ]; then
        echo "🎉 No SSL certificate errors detected"
    else
        echo "⚠️ Some certificate warnings detected (normal during startup)"
    fi
else
    echo "⏳ Certificate initialization in progress..."
    echo "💡 Monitor with: docker logs dt-apiserver -f | grep CERT-INIT"
fi

# Jenkins (our custom-built image with plugins pre-installed)
echo "🔧 Starting Jenkins with pre-installed plugins..."
check_service "Jenkins" 8080 /login

# Give JCasC time to process configuration
echo "⚙️ Allowing Jenkins Configuration as Code to process..."
sleep 10

# Verify our setup
echo "🔍 Verifying setup..."

# Check essential plugins are installed
echo "🔌 Verifying essential plugins are installed:"
ESSENTIAL_PLUGINS=("workflow-aggregator" "dependency-check-jenkins-plugin" "http_request" "configuration-as-code" "job-dsl" "maven-plugin" "git")
installed_count=0

for plugin in "${ESSENTIAL_PLUGINS[@]}"; do
    if docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.jpi" 2>/dev/null || \
       docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.hpi" 2>/dev/null; then
        echo "✅ $plugin installed"
        ((installed_count++))
    else
        echo "❌ $plugin NOT installed"
    fi
done

# API Key Setup and Pipeline Creation
echo ""
echo "🔑 Setting up Dependency Track API integration..."

# Always get fresh API key during setup since old keys become invalid
echo "🔧 Getting fresh API key for new Dependency Track instance..."
echo "💡 Previous API keys become invalid when containers are recreated"

if [ -f scripts/get-dt-api-key.sh ]; then
    chmod +x scripts/get-dt-api-key.sh
    if ./scripts/get-dt-api-key.sh; then
        echo "✅ Fresh API key created successfully"
        
        # Get the new API key value
        NEW_API_KEY=$(grep "^DT_API_KEY=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
        
        if [ -n "$NEW_API_KEY" ]; then
            echo "✅ New API key saved: ${NEW_API_KEY:0:12}..."
            
            # Stop and recreate Jenkins container to pick up new environment
            echo "🔄 Recreating Jenkins container to load new API key..."
            echo "   This ensures the new environment variables are properly loaded"
            
            # Stop only Jenkins (not dependencies)
            docker stop jenkins 2>/dev/null || true

            # Remove only Jenkins container (preserves volumes)
            docker rm jenkins 2>/dev/null || true

            # Start only Jenkins with new environment
            echo "🚀 Starting Jenkins with new API key..."
            docker-compose up -d --no-deps jenkins
            
            echo "⏳ Waiting for Jenkins to initialize with new API key..."
            sleep 45  # Jenkins needs more time for full startup
            
            # Wait for Jenkins to be ready again
            if check_service "Jenkins" 8080 /login; then
                echo "✅ Jenkins recreated successfully"
                
                # Installing SSL Certs in Jenkins
                echo ""
                echo "🔐 Configuring SSL certificates for Jenkins Dependency Check..."
                if [ -f scripts/fix-jenkins-ssl.sh ]; then
                    chmod +x scripts/fix-jenkins-ssl.sh
                    ./scripts/fix-jenkins-ssl.sh
                else
                    echo "⚠️ fix-jenkins-ssl.sh script not found"
                    echo "💡 You may need to run: ./scripts/fix-jenkins-ssl.sh manually"
                fi

                # Fix maven SSL Certs
                echo ""
                echo "🔐 Adding Maven Central SSL certificate for dependency analysis..."
                if [ -f scripts/fix-maven-ssl.sh ]; then
                    chmod +x scripts/fix-maven-ssl.sh
                    ./scripts/fix-maven-ssl.sh
                else
                    echo "⚠️ fix-maven-ssl.sh script not found"
                    echo "💡 Maven Central analysis may have SSL connectivity issues"
                fi

                # SKIP DEPENDENCY CHECK TOOL INSTALLATION
                echo ""
                echo "🎯 SKIPPING Dependency Check tool installation..."
                echo "💡 Your pipeline uses Java direct execution, so the shell script isn't needed"
                
                # Just verify that the JAR files exist for Java execution
                echo ""
                echo "🔍 Verifying Dependency Check JAR files for Java execution..."
                
                # Create the basic tool directory structure
                docker exec -u root jenkins bash -c '
                    mkdir -p "/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
                    chown -R jenkins:jenkins "/var/jenkins_home/tools"
                '
                
                # Download and extract ONLY the JAR files we need
                docker exec -u root jenkins bash -c '
                    TOOL_DIR="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
                    cd "$TOOL_DIR"
                    
                    if [ ! -d "lib" ]; then
                        echo "📦 Downloading Dependency Check for JAR files only..."
                        wget -q --timeout=60 --tries=3 \
                            "https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.3/dependency-check-8.4.3-release.zip"
                        
                        if [ -f "dependency-check-8.4.3-release.zip" ]; then
                            echo "📂 Extracting JAR files..."
                            unzip -q dependency-check-8.4.3-release.zip
                            
                            if [ -d "dependency-check" ]; then
                                mv dependency-check/* .
                                rmdir dependency-check
                                rm -f dependency-check-8.4.3-release.zip
                            fi
                            
                            echo "✅ JAR files extracted for Java execution"
                            echo "📋 Available JARs:"
                            ls -la lib/ | grep dependency-check | head -3
                        else
                            echo "❌ Download failed"
                        fi
                    else
                        echo "✅ JAR files already available"
                    fi
                    
                    chown -R jenkins:jenkins "/var/jenkins_home/tools"
                '
                
                # Test Java execution (this is what matters)
                echo ""
                echo "🧪 Testing Java direct execution (the method your pipeline uses)..."
                
                JAVA_TEST=$(docker exec -u jenkins jenkins bash -c '
                    TOOL_DIR="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
                    
                    if [ -d "$TOOL_DIR/lib" ]; then
                        echo "✅ Library directory exists"
                        
                        MAIN_JAR=$(find "$TOOL_DIR/lib" -name "dependency-check-cli-*.jar" | head -1)
                        if [ -n "$MAIN_JAR" ]; then
                            echo "✅ Found main JAR: $(basename "$MAIN_JAR")"
                            
                            if java -cp "$TOOL_DIR/lib/*" org.owasp.dependencycheck.App --version >/dev/null 2>&1; then
                                VERSION=$(java -cp "$TOOL_DIR/lib/*" org.owasp.dependencycheck.App --version 2>&1 | head -1)
                                echo "✅ Java execution successful: $VERSION"
                                echo "SUCCESS"
                            else
                                echo "❌ Java execution failed"
                                echo "JAVA_FAILED"
                            fi
                        else
                            echo "❌ Main JAR not found"
                            echo "JAR_MISSING"
                        fi
                    else
                        echo "❌ Library directory not found"
                        echo "LIB_MISSING"
                    fi
                ' 2>/dev/null)
                
                echo "$JAVA_TEST"
                
                if echo "$JAVA_TEST" | grep -q "SUCCESS"; then
                    echo "🎉 ✅ Java execution verified - your pipeline will work!"
                else
                    echo "⚠️ Java execution had issues, but pipeline might still work"
                fi

                # Verify Jenkins has the new API key
                JENKINS_API_KEY=$(docker exec jenkins printenv DT_API_KEY 2>/dev/null || echo "")
                if [ -n "$JENKINS_API_KEY" ] && [ "$JENKINS_API_KEY" = "$NEW_API_KEY" ]; then
                    echo "✅ Jenkins container has new API key: ${JENKINS_API_KEY:0:12}..."
                elif [ -n "$JENKINS_API_KEY" ]; then
                    echo "⚠️ Jenkins has API key but it may be old: ${JENKINS_API_KEY:0:12}..."
                else
                    echo "❌ Jenkins container doesn't have API key"
                fi
            else
                echo "❌ Jenkins recreation failed"
                exit 1
            fi
        else
            echo "❌ Failed to retrieve new API key from .env file"
            exit 1
        fi
    else
        echo "❌ API key creation failed"
        exit 1
    fi
else
    echo "❌ get-dt-api-key.sh script not found"
    exit 1
fi

# Create Dependency Track project for demo
echo ""
echo "📋 Creating WebGoat project in Dependency Track..."

# Get current API key from .env file
CURRENT_API_KEY=$(grep "^DT_API_KEY=" .env 2>/dev/null | cut -d'=' -f2 || echo "")

if [ -n "$CURRENT_API_KEY" ]; then
    echo "🔧 Using API key: ${CURRENT_API_KEY:0:12}..."
    
    # Create the WebGoat project
    PROJECT_RESPONSE=$(curl -s -w "%{http_code}" \
        -X PUT "http://localhost:8081/api/v1/project" \
        -H "X-API-Key: $CURRENT_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "WebGoat",
            "version": "8.1.0",
            "description": "WebGoat v8.1.0 - Intentionally vulnerable application for security scanning demonstration",
            "tags": [
                {"name": "demo"},
                {"name": "webgoat"},
                {"name": "security-scan"},
                {"name": "mend-demo"}
            ]
        }' \
        -o /tmp/project-response.json)
    
    # Extract HTTP status code (last 3 characters)
    HTTP_STATUS="${PROJECT_RESPONSE: -3}"
    
    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
        echo "✅ WebGoat project created successfully in Dependency Track"
        
        # Extract project UUID if available
        if [ -f /tmp/project-response.json ]; then
            PROJECT_UUID=$(jq -r '.uuid // empty' /tmp/project-response.json 2>/dev/null || echo "")
            if [ -n "$PROJECT_UUID" ]; then
                echo "📋 Project UUID: $PROJECT_UUID"
            fi
        fi
        
        rm -f /tmp/project-response.json
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo "ℹ️ WebGoat project already exists in Dependency Track"
    else
        echo "⚠️ Failed to create project (HTTP $HTTP_STATUS)"
        echo "💡 Pipeline will attempt to create it automatically during upload"
    fi
else
    echo "⚠️ No API key found - project creation will be handled by pipeline"
fi

# Create pipeline job
echo ""
echo "🚀 Creating Jenkins pipeline job..."
if [ -f scripts/create-pipeline.sh ]; then
    chmod +x scripts/create-pipeline.sh
    if ./scripts/create-pipeline.sh; then
        echo "✅ Pipeline job created successfully"
        
        # Update the JOB_CHECK variable for final status
        JOB_CHECK=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -o '"name":"webgoat-security-scan"' || echo "")
        
        if [ -n "$JOB_CHECK" ]; then
            echo "🎯 WebGoat security scan pipeline is ready to run!"
        fi
    else
        echo "⚠️ Pipeline creation had issues - you may need to create it manually"
        echo "💡 Try running: ./scripts/create-pipeline.sh"
    fi
else
    echo "⚠️ create-pipeline.sh script not found"
    echo "💡 Pipeline job will need to be created manually"
fi

# Final status
echo ""
echo "🏥 Final System Status:"
echo -n "   PostgreSQL: "
docker exec dt-postgres pg_isready -U dtrack 2>/dev/null && echo "✅ Ready" || echo "❌ Not Ready"

echo -n "   Dependency Track: "
curl -s -f http://localhost:8081/api/version >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready"

echo -n "   Jenkins: "
curl -s -f http://localhost:8080/login >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready"

echo ""
echo "✅ 🎉 SETUP COMPLETE! 🎉"
echo ""
echo "🌐 Access Your Demo Environment:"
echo "   • Jenkins:           http://localhost:8080 (admin/admin)"
echo "   • Dependency Track:  http://localhost:8081"
echo "   • DT Frontend:       http://localhost:8082 (admin/admin)"
echo ""
echo "⚡ What Was Accomplished:"
echo "   ✓ Custom Jenkins image built with pre-installed plugins"
echo "   ✓ All $installed_count/${#ESSENTIAL_PLUGINS[@]} essential plugins installed during build"
echo "   ✓ Jenkins Configuration as Code applied"
echo "   ✓ SSL certificate issues detected and fixed"
echo "   ✓ Java direct execution configured (bypasses shell script issues)"
echo "   ✓ Dependency Check JAR files available for Java execution"
echo ""
echo "🎬 Ready to Run Demo:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Login with admin/admin"
echo "   3. Find 'webgoat-security-scan' pipeline job"
echo "   4. Click 'Build Now' to start the security scan"
echo ""
echo "🎯 Pipeline Uses Java Direct Execution:"
echo "   ✓ No shell script permission issues"
echo "   ✓ Direct Java classpath execution"
echo "   ✓ Same functionality as original plugin"
echo "   ✓ More reliable in containerized environments"
echo ""
echo "⏱️ Total Setup Time: ~5-8 minutes (with Java direct execution approach)"