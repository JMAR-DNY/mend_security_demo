#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo with runtime plugin installation..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p jenkins/casc_configs jenkins/init.groovy.d workspace reports

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || echo "Scripts already executable"

# Start services
echo "🐳 Starting Docker services..."
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

# Wait for services
echo "🔄 Waiting for services to initialize..."

# PostgreSQL first
echo "🗄️ Starting PostgreSQL..."
sleep 20

# Dependency Track API
echo "🛡️ Starting Dependency Track..."
check_service "Dependency Track API" 8081

# Jenkins
echo "🔧 Starting Jenkins (plugins will install at runtime)..."
check_service "Jenkins" 8080

# Wait for plugin installation
echo "🔌 Waiting for Jenkins plugins to install (this takes 3-5 minutes)..."
echo "   Jenkins will restart automatically after plugin installation"
sleep 60

# Check if Jenkins restarted after plugin installation
echo "🔄 Checking if Jenkins is restarting after plugin installation..."
JENKINS_READY=false
for i in {1..20}; do
    if curl -f http://localhost:8080/login >/dev/null 2>&1; then
        JENKINS_READY=true
        break
    fi
    echo "   Waiting for Jenkins restart... (${i}/20)"
    sleep 15
done

if [ "$JENKINS_READY" = true ]; then
    echo "✅ Jenkins is ready after plugin installation"
else
    echo "⚠️ Jenkins may still be installing plugins"
fi

# Give JCasC time to create jobs
echo "⚙️ Allowing time for Jenkins Configuration as Code..."
sleep 30

# Verify plugin installation
echo "🔍 Verifying essential plugins..."
ESSENTIAL_PLUGINS=("workflow-aggregator" "dependency-check-jenkins-plugin" "http_request" "configuration-as-code" "job-dsl" "maven-plugin" "git")
installed_count=0

for plugin in "${ESSENTIAL_PLUGINS[@]}"; do
    if docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.jpi" 2>/dev/null || \
       docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.hpi" 2>/dev/null; then
        echo "✅ $plugin installed"
        ((installed_count++))
    else
        echo "⏳ $plugin pending installation"
    fi
done

echo "📊 Plugin Status: $installed_count/${#ESSENTIAL_PLUGINS[@]} essential plugins verified"

# Final status check
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
echo "   • Dependency Track:  http://localhost:8081 (admin/admin)"
echo "   • DT Frontend:       http://localhost:8082"
echo ""
echo "⚡ What Was Automated:"
echo "   ✓ Runtime plugin installation (no SSL issues)"
echo "   ✓ Jenkins Configuration as Code"
echo "   ✓ Automatic job creation via JCasC"
echo "   ✓ Complete security scanning workflow"
echo ""
echo "🎬 Ready to Run Demo:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Login with admin/admin"
echo "   3. Find 'webgoat-security-scan' pipeline job"
echo "   4. Click 'Build Now' to start the security scan"
echo ""
if [ $installed_count -lt ${#ESSENTIAL_PLUGINS[@]} ]; then
    echo "💡 Note: Some plugins may still be installing"
    echo "   • Wait 2-3 more minutes for full installation"
    echo "   • Check status: make verify-plugins"
    echo "   • Jenkins may restart automatically when ready"
fi
echo ""
echo "⏱️ Total Setup Time: ~7-10 minutes (with runtime plugin installation)"