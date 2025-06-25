#!/bin/bash
set -e

echo "🔧 Installing OWASP Dependency Check tool..."

# Check if Jenkins is running
if ! docker ps | grep -q "jenkins"; then
    echo "❌ Jenkins container is not running"
    exit 1
fi

# Install the tool
docker exec -u root jenkins bash -c '
    set -e  # Exit on any error
    
    echo "📦 Installing required tools (wget and unzip)..."
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y wget unzip >/dev/null 2>&1
    
    echo "📂 Creating tool directory..."
    TOOL_DIR="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
    mkdir -p "$TOOL_DIR"
    cd "$TOOL_DIR"

    # Cleanup any existing installation
    echo "🧹 Cleaning any existing installation..."
    rm -rf * .* 2>/dev/null || true

    echo "⬇️ Downloading Dependency Check v8.4.3..."
    
    echo "⬇️ Downloading Dependency Check v8.4.3..."
    wget -q --timeout=30 --tries=3 https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.3/dependency-check-8.4.3-release.zip
    
    echo "🔍 Verifying download..."
    if [ ! -f dependency-check-8.4.3-release.zip ] || [ ! -s dependency-check-8.4.3-release.zip ]; then
        echo "❌ Download failed or file is empty"
        exit 1
    fi
    
    echo "📦 Extracting archive..."
    unzip -q dependency-check-8.4.3-release.zip
    
    echo "🔧 Setting up tool structure..."
    if [ -d dependency-check ]; then
        mv dependency-check/* . 2>/dev/null || true
        rmdir dependency-check 2>/dev/null || true
        rm -f dependency-check-8.4.3-release.zip
    else
        echo "❌ Expected dependency-check directory not found after extraction"
        echo "📁 Contents after extraction:"
        ls -la
        exit 1
    fi
    
    echo "🔐 Setting permissions..."
    chmod +x bin/dependency-check.sh
    chmod +x bin/*.sh  # Make sure all shell scripts are executable
    find . -name "*.sh" -exec chmod +x {} \;  # Belt and suspenders approach

    # ADD THIS: Double-check permissions specifically for the main script
    echo "🔍 Verifying permissions on main executable..."
    ls -la bin/dependency-check.sh
    chmod 755 bin/dependency-check.sh  # Explicit permission setting
    chown jenkins:jenkins bin/dependency-check.sh

    echo "🔍 Verifying executable exists..."
    if [ ! -f bin/dependency-check.sh ]; then
        echo "❌ dependency-check.sh not found"
        echo "📁 Contents:"
        find . -name "*dependency*" -o -name "*.sh" | head -10
        exit 1
    fi
    
    echo "👤 Setting ownership..."
    chown -R jenkins:jenkins /var/jenkins_home/tools
    
    echo "✅ Installation complete"
'

# Verify installation
echo "🔍 Performing final verification..."
if docker exec jenkins test -f "/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh"; then
    echo "✅ Dependency Check tool successfully installed"
    
    # Test that it's executable and working
    echo "🧪 Testing tool execution..."
    if docker exec -u jenkins jenkins /var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh --version >/dev/null 2>&1; then
        echo "✅ Tool is executable and working properly"
        
        # Show version for confirmation
        VERSION=$(docker exec -u jenkins jenkins /var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh --version 2>&1 | grep -o "version [0-9.]*" || echo "version unknown")
        echo "📋 Installed Dependency Check $VERSION"
    else
        echo "⚠️ Tool installed but may have execution issues"
        echo "🔍 Checking tool permissions and structure:"
        docker exec jenkins ls -la /var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/
    fi
else
    echo "❌ Tool installation verification failed"
    echo "🔍 Debugging information:"
    echo "📁 Checking what was created in tools directory:"
    docker exec jenkins find /var/jenkins_home/tools -name "*dependency*" -o -name "*.sh" 2>/dev/null | head -10 || echo "No files found"
    exit 1
fi

echo ""
echo "🎉 ✅ DEPENDENCY CHECK INSTALLATION SUCCESSFUL! ✅"
echo "🎯 Tool is ready for use in Jenkins pipelines"