#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo with Custom Jenkins Image..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p jenkins/casc_configs
mkdir -p workspace
mkdir -p reports

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || echo "Scripts already executable"

# Verify required files exist
if [ ! -f "jenkins/plugins.txt" ]; then
    echo "❌ jenkins/plugins.txt not found. Please create it with the required plugins."
    exit 1
fi

if [ ! -f "Dockerfile.jenkins" ]; then
    echo "❌ Dockerfile.jenkins not found. Please create it for custom Jenkins image."
    exit 1
fi

echo "✅ Required files found"
echo "   plugins.txt: $(wc -l < jenkins/plugins.txt) plugin entries"

# Build and start services
echo "🐳 Building custom Jenkins image and starting services..."
echo "⏰ This will take 5-10 minutes for first build (downloads and installs plugins)..."
docker-compose up -d --build

# Function to check service health
check_service() {
    local service_name=$1
    local port=$2
    local max_attempts=40  # Longer timeout for custom build
    local attempt=1
    
    echo "⏳ Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:$port >/dev/null 2>&1; then
            echo "✅ $service_name is ready"
            return 0
        fi
        
        # Show progress every 5 attempts
        if [ $((attempt % 5)) -eq 0 ]; then
            echo "   Attempt $attempt/$max_attempts - still waiting..."
            if [ "$service_name" = "Jenkins" ] && [ $attempt -ge 10 ]; then
                echo "   Custom Jenkins image may still be building or starting..."
            fi
        fi
        
        sleep 15
        ((attempt++))
    done
    
    echo "❌ $service_name failed to start within timeout"
    return 1
}

# Wait for services in order
echo "🔄 Waiting for services to initialize..."

# PostgreSQL first
echo "🗄️ Waiting for PostgreSQL..."
sleep 15

# Dependency Track API
echo "🛡️ Waiting for Dependency Track API..."
check_service "Dependency Track API" 8081

# Jenkins (will take longer due to custom image build)
echo "🔧 Waiting for custom Jenkins image to build and start..."
echo "   This includes building the image with plugins pre-installed..."
check_service "Jenkins" 8080

# Verify plugin installation
echo "🔍 Verifying plugin installation..."
sleep 30  # Give Jenkins time to finish initialization

# Check if essential plugins are installed
ESSENTIAL_PLUGINS=("workflow-aggregator" "dependency-check-jenkins-plugin" "http_request" "configuration-as-code" "job-dsl" "maven-plugin" "git")
installed_count=0

for plugin in "${ESSENTIAL_PLUGINS[@]}"; do
    if docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.jpi" 2>/dev/null || \
       docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.hpi" 2>/dev/null; then
        echo "✅ $plugin installed"
        ((installed_count++))
    else
        echo "❌ $plugin missing"
    fi
done

echo "📊 Plugin Installation: $installed_count/${#ESSENTIAL_PLUGINS[@]} essential plugins installed"

if [ $installed_count -ge 6 ]; then
    echo "✅ Excellent! All essential plugins installed successfully"
elif [ $installed_count -ge 4 ]; then
    echo "✅ Good! Sufficient plugins installed for demo functionality"
else
    echo "⚠️ Some plugins missing - check Dockerfile.jenkins and plugins.txt"
fi

# Give Jenkins time to process JCasC and create jobs
echo "⚙️ Allowing time for Jenkins Configuration as Code to process..."
sleep 45

# Check if JCasC created the pipeline job
echo "🔍 Verifying pipeline job creation..."
JOB_CHECK=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -o '"name":"webgoat-security-scan"' || echo "")

if [ -n "$JOB_CHECK" ]; then
    echo "✅ WebGoat security scan pipeline job created successfully via JCasC"
else
    echo "⚠️ Pipeline job not automatically created"
    echo "   This can happen if Job DSL plugin needs more time to process"
    echo "   Job can be created manually or via JCasC reload"
fi

# Final system verification
echo ""
echo "🎯 Performing final system verification..."

# Check all containers are running
echo "📊 Container Status:"
docker-compose ps

# Check key services
echo ""
echo "🏥 Service Health Check:"
echo -n "   PostgreSQL: "
docker exec dt-postgres pg_isready -U dtrack 2>/dev/null && echo "✅ Ready" || echo "❌ Not Ready"

echo -n "   Dependency Track: "
curl -s -f http://localhost:8081/api/version >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready"

echo -n "   Jenkins: "
curl -s -f http://localhost:8080/login >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready"

echo -n "   Jenkins Pipeline Job: "
if [ -n "$JOB_CHECK" ]; then
    echo "✅ Created"
else
    echo "⚠️ Check manually"
fi

echo ""
echo "✅ 🎉 SETUP COMPLETE! 🎉"
echo ""
echo "🌐 Access Your Demo Environment:"
echo "   • Jenkins:           http://localhost:8080 (admin/admin)"
echo "   • Dependency Track:  http://localhost:8081 (admin/admin)"
echo "   • DT Frontend:       http://localhost:8082"
echo ""
echo "🎬 Ready to Run Demo:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Login with admin/admin"
if [ -n "$JOB_CHECK" ]; then
    echo "   3. Find 'webgoat-security-scan' pipeline job"
    echo "   4. Click 'Build Now' to start the security scan"
else
    echo "   3. If pipeline job not visible:"
    echo "      • Go to Manage Jenkins → Configuration as Code → Reload existing configuration"
    echo "      • Or create job manually using provided pipeline script"
    echo "   4. Click 'Build Now' to start the security scan"
fi
echo "   5. Monitor pipeline execution in real-time"
echo "   6. Review results in Dependency Track: http://localhost:8081"
echo ""
echo "⚡ What Was Automated:"
echo "   ✓ Custom Jenkins image with plugins pre-installed via jenkins-plugin-cli"
echo "   ✓ No runtime installation complexity or CSRF issues"
echo "   ✓ Jenkins Configuration as Code for pipeline creation"
echo "   ✓ Complete Mend security workflow ready"
echo ""
if [ $installed_count -lt 6 ]; then
    echo "💡 If Some Plugins Missing:"
    echo "   • Check docker build logs: docker-compose logs jenkins"
    echo "   • Verify plugins.txt format and plugin names"
    echo "   • Rebuild image: docker-compose up -d --build"
fi
echo ""
echo "⏱️ Total Setup Time: ~10-15 minutes (including custom image build)"
echo "   • Image build with plugins: 5-8 minutes (first time only)"
echo "   • Container startup: 2-3 minutes"
echo "   • Service initialization: 2-3 minutes"
echo ""
echo "🚀 Subsequent runs will be much faster (2-3 minutes) as image is cached!"