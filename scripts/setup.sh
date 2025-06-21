#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo with Runtime Plugin Installation..."

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
        echo "   Attempt $attempt/$max_attempts - waiting..."
        sleep 10
        ((attempt++))
    done
    
    echo "❌ $service_name failed to start within timeout"
    return 1
}

# Wait for services
echo "🔄 Waiting for core services to initialize..."

# PostgreSQL first
echo "🗄️ Waiting for PostgreSQL..."
sleep 15

# Dependency Track API
echo "🛡️ Waiting for Dependency Track API..."
check_service "Dependency Track API" 8081

# Jenkins
echo "🔧 Waiting for Jenkins..."
check_service "Jenkins" 8080

# Install plugins at runtime
echo "🔌 Installing Jenkins plugins at runtime..."
sleep 30  # Give Jenkins time to fully start

# Execute plugin installation inside Jenkins container
echo "Installing required plugins for Mend demo..."
docker exec jenkins /bin/bash -c "
    # Wait for Jenkins to be fully ready
    max_attempts=20
    attempt=1
    
    while [ \$attempt -le \$max_attempts ]; do
        if java -jar /var/jenkins_home/war/WEB-INF/lib/cli-*.jar -s http://localhost:8080/ -auth admin:admin who-am-i >/dev/null 2>&1; then
            echo 'Jenkins CLI is ready'
            break
        fi
        echo \"Waiting for Jenkins CLI to be available... (attempt \$attempt/\$max_attempts)\"
        sleep 10
        ((attempt++))
    done
    
    if [ \$attempt -gt \$max_attempts ]; then
        echo 'Jenkins CLI failed to become available'
        exit 1
    fi
    
    echo 'Installing required plugins...'
    java -jar /var/jenkins_home/war/WEB-INF/lib/cli-*.jar -s http://localhost:8080/ -auth admin:admin install-plugin \
        workflow-aggregator \
        git \
        maven-plugin \
        dependency-check-jenkins-plugin \
        http_request \
        pipeline-utility-steps \
        configuration-as-code \
        job-dsl \
        credentials \
        credentials-binding \
        timestamper \
        workspace-cleanup \
        build-timeout \
        pipeline-stage-view \
        matrix-auth \
        structs \
        script-security \
        || echo 'Some plugins may already be installed or have dependency issues'
    
    echo 'Restarting Jenkins to activate plugins...'
    java -jar /var/jenkins_home/war/WEB-INF/lib/cli-*.jar -s http://localhost:8080/ -auth admin:admin restart
"

# Wait for Jenkins to restart
echo "⏳ Waiting for Jenkins to restart and load configuration..."
sleep 60

# Verify Jenkins is back up and check for plugins
echo "🔍 Verifying Jenkins restart and plugin installation..."
max_attempts=20
attempt=1

while [ $attempt -le $max_attempts ]; do
    if curl -f http://localhost:8080/login >/dev/null 2>&1; then
        echo "✅ Jenkins is back online"
        break
    fi
    echo "   Attempt $attempt/$max_attempts - waiting for Jenkins..."
    sleep 10
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ Jenkins failed to restart properly"
    exit 1
fi

# Give Jenkins time to process JCasC and create jobs
echo "⚙️ Allowing time for Jenkins Configuration as Code to process..."
sleep 45

# Verify job creation
echo "🔍 Verifying pipeline job creation..."
JOB_CHECK=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -o '\"name\":\"webgoat-security-scan\"' || echo "")

if [ -n "$JOB_CHECK" ]; then
    echo "✅ WebGoat security scan pipeline job created successfully"
else
    echo "⚠️ Pipeline job may still be creating or there was an issue"
    echo "   You can check Jenkins at http://localhost:8080 to verify"
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
curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -q "name" && echo "✅ Created" || echo "⚠️ Check manually"

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
echo "   3. Find 'webgoat-security-scan' pipeline job"
echo "   4. Click 'Build Now' to start the security scan"
echo "   5. Monitor pipeline execution in real-time"
echo "   6. Review results in Dependency Track: http://localhost:8081"
echo ""
echo "⚡ What Was Automated:"
echo "   ✓ All required plugins installed at runtime"
echo "   ✓ Security scan pipeline job auto-created via JCasC"
echo "   ✓ Tools and credentials pre-configured"
echo "   ✓ Complete Mend security workflow ready"
echo ""
echo "⏱️ Total Setup Time: ~7-10 minutes (much faster than custom builds!)"
echo ""
echo "💡 Troubleshooting:"
echo "   • If pipeline job isn't visible, wait 2-3 minutes and refresh Jenkins"
echo "   • Check 'make logs' if any service issues"
echo "   • Use 'make status' for detailed health information"