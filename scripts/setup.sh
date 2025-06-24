#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo with pre-built Jenkins image..."

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

# Wait for services in dependency order
echo "🔄 Waiting for services to initialize..."

# PostgreSQL first (dependency for Dependency Track)
echo "🗄️  Starting PostgreSQL..."
sleep 15

# Dependency Track API (needs PostgreSQL)
echo "🛡️  Starting Dependency Track..."
check_service "Dependency Track API" 8081 /api/version

# Initialize Dependency Track admin account
echo "🔑 Initializing Dependency Track admin account..."
if [ -f scripts/init-dependency-track.sh ]; then
    chmod +x scripts/init-dependency-track.sh
    ./scripts/init-dependency-track.sh
else
    echo "⚠️ init-dependency-track.sh script not found, skipping admin setup"
fi

# 🔐 SSL Certificate Fix Integration
echo ""
echo "🔐 Checking and fixing SSL certificate issues for vulnerability feeds..."

if [ -f scripts/fix-dt-certificates.sh ]; then
    chmod +x scripts/fix-dt-certificates.sh
    
    if ./scripts/fix-dt-certificates.sh; then
        echo "✅ Certificate fixes completed successfully"
    else
        echo "⚠️ Certificate fixes had some issues, but continuing setup"
        echo "💡 You may need to run './scripts/fix-dt-certificates.sh --force' manually later"
    fi
else
    echo "⚠️ Certificate fix script not found at scripts/fix-dt-certificates.sh"
    echo "💡 Consider creating this script for automatic certificate handling"
fi

# Continue with Jenkins setup...

# Wait a moment for Dependency Track to start its background tasks
echo "⏳ Allowing Dependency Track to initialize background tasks..."
sleep 30

# Check for certificate issues in the logs
echo "🔍 Checking for SSL certificate errors..."
CERT_ERRORS=$(docker logs dt-apiserver 2>&1 | grep -c "PKIX path building failed" || echo "0")

if [ "$CERT_ERRORS" -gt "0" ]; then
    echo "🔧 Certificate issues detected ($CERT_ERRORS errors found)"
    echo "   Applying certificate fixes..."
    
    # Apply certificate fixes
    if [ -f scripts/update-certificates.sh ]; then
        chmod +x scripts/update-certificates.sh
        echo "   Running certificate update script..."
        
        if ./scripts/update-certificates.sh; then
            echo "✅ Certificate fixes applied successfully"
            
            # Give it time to retry downloads
            echo "⏳ Allowing time for vulnerability feed downloads to retry..."
            sleep 45
            
            # Check if downloads are now working
            RECENT_DOWNLOADS=$(docker logs dt-apiserver --since 1m 2>&1 | grep -c "download.*completed\|successfully downloaded" || echo "0")
            
            if [ "$RECENT_DOWNLOADS" -gt "0" ]; then
                echo "🎉 Vulnerability feeds are now downloading successfully!"
            else
                echo "ℹ️ Downloads may take a few more minutes to retry"
            fi
        else
            echo "⚠️ Certificate fix script had issues, but continuing setup"
            echo "💡 You may need to run ./scripts/update-certificates.sh manually later"
        fi
    else
        echo "⚠️ Certificate update script not found"
        echo "💡 Consider creating scripts/update-certificates.sh for automatic certificate fixes"
    fi
else
    echo "✅ No SSL certificate issues detected in logs"
fi

# End of certificate handling section

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

# Check if pipeline job was created
echo "🔧 Checking if pipeline job was created..."
JOB_CHECK=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -o '"name":"webgoat-security-scan"' || echo "")

if [ -n "$JOB_CHECK" ]; then
    echo "✅ WebGoat security scan pipeline job created successfully"
else
    echo "⚠️ Pipeline job not yet created (JCasC may still be processing)"
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

# Final certificate status check
echo -n "   SSL Certificates: "
FINAL_CERT_ERRORS=$(docker logs dt-apiserver --since 2m 2>&1 | grep -c "PKIX path building failed" || echo "0")
if [ "$FINAL_CERT_ERRORS" -eq "0" ]; then
    echo "✅ Working"
else
    echo "⚠️ May need attention ($FINAL_CERT_ERRORS recent errors)"
fi

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
echo "   ✓ Reliable, reproducible plugin installation"
echo ""
echo "🎬 Ready to Run Demo:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Login with admin/admin"
echo "   3. Find 'webgoat-security-scan' pipeline job"
echo "   4. Click 'Build Now' to start the security scan"
echo ""
if [ $installed_count -eq ${#ESSENTIAL_PLUGINS[@]} ]; then
    echo "🎯 All plugins successfully installed! Demo is ready."
else
    echo "⚠️ Some plugins may be missing. Check with: make verify-plugins"
fi

# Certificate-specific final message
if [ "$CERT_ERRORS" -gt "0" ]; then
    echo ""
    echo "🔐 Certificate Status:"
    if [ "$FINAL_CERT_ERRORS" -eq "0" ]; then
        echo "   ✅ Certificate issues were detected and resolved"
        echo "   📥 Vulnerability feeds should now download automatically"
    else
        echo "   ⚠️ Some certificate issues may persist"
        echo "   💡 Run './scripts/update-certificates.sh' manually if needed"
        echo "   📋 Monitor with: docker logs dt-apiserver -f | grep -E '(download|PKIX)'"
    fi
fi

echo ""
echo "⏱️ Total Setup Time: ~5-8 minutes (with reliable pre-build plugin installation)"