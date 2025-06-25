#!/bin/bash
set -e

echo "🔧 Installing OWASP Dependency Check tool with enhanced permission handling..."

# Check if Jenkins is running
if ! docker ps | grep -q "jenkins"; then
    echo "❌ Jenkins container is not running"
    echo "💡 Start it with: make start"
    exit 1
fi

echo "🔍 Jenkins container is running, proceeding with installation..."

# Enhanced installation with comprehensive permission fixing
docker exec -u root jenkins bash -c '
    set -e  # Exit on any error
    
    echo "📦 Installing system dependencies..."
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y wget unzip xmlstarlet >/dev/null 2>&1
    
    echo "📂 Setting up tool directory with proper ownership..."
    TOOL_DIR="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
    
    # Ensure the tools directory structure exists with correct ownership
    mkdir -p "/var/jenkins_home/tools"
    mkdir -p "/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation"
    mkdir -p "$TOOL_DIR"
    
    # Set ownership before we start
    chown -R jenkins:jenkins "/var/jenkins_home/tools"
    
    cd "$TOOL_DIR"

    # Cleanup any existing installation
    echo "🧹 Cleaning any existing installation..."
    rm -rf ./* 2>/dev/null || true

    echo "⬇️ Downloading Dependency Check v8.4.3..."
    wget -q --timeout=30 --tries=3 \
        "https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.3/dependency-check-8.4.3-release.zip"
    
    echo "🔍 Verifying download..."
    if [ ! -f dependency-check-8.4.3-release.zip ] || [ ! -s dependency-check-8.4.3-release.zip ]; then
        echo "❌ Download failed or file is empty"
        ls -la
        exit 1
    fi
    
    echo "📦 Extracting archive..."
    unzip -q dependency-check-8.4.3-release.zip
    
    echo "🔧 Setting up tool structure..."
    if [ -d dependency-check ]; then
        # Move contents up to the tool directory
        mv dependency-check/* . 2>/dev/null || true
        rmdir dependency-check 2>/dev/null || true
        rm -f dependency-check-8.4.3-release.zip
    else
        echo "❌ Expected dependency-check directory not found after extraction"
        echo "📁 Contents after extraction:"
        ls -la
        exit 1
    fi
    
    echo "🔐 Setting comprehensive permissions..."
    
    # Make ALL shell scripts executable
    find . -name "*.sh" -exec chmod 755 {} \;
    
    # Specifically ensure the main script is executable
    if [ -f "bin/dependency-check.sh" ]; then
        chmod 755 bin/dependency-check.sh
        echo "✅ Main script permissions set: $(ls -la bin/dependency-check.sh)"
    else
        echo "❌ Main script not found!"
        echo "📁 Available files in bin/:"
        ls -la bin/ || echo "No bin directory found"
        exit 1
    fi
    
    # Make all files in bin executable (belt and suspenders)
    if [ -d "bin" ]; then
        chmod 755 bin/*
        echo "✅ All bin files made executable"
    fi
    
    # Set directory permissions
    find . -type d -exec chmod 755 {} \;
    
    # Set file permissions for everything else
    find . -type f ! -name "*.sh" -exec chmod 644 {} \;
    
    echo "👤 Setting final ownership..."
    chown -R jenkins:jenkins "/var/jenkins_home/tools"
    
    echo "🔍 Final verification of main executable..."
    ls -la bin/dependency-check.sh
    
    # Test file permissions and ownership
    echo "📋 Permission and ownership summary:"
    echo "   Owner: $(stat -c \"%U:%G\" bin/dependency-check.sh)"
    echo "   Permissions: $(stat -c \"%a\" bin/dependency-check.sh)"
    echo "   Executable test: $(test -x bin/dependency-check.sh && echo \"✅ YES\" || echo \"❌ NO\")"
    
    echo "✅ Installation complete with enhanced permissions"
'

echo ""
echo "🔍 Performing comprehensive verification..."

# Verify the file exists
if ! docker exec jenkins test -f "/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh"; then
    echo "❌ Main executable not found after installation"
    exit 1
fi

# Check permissions from Jenkins user perspective
echo "🧪 Testing from Jenkins user perspective..."
JENKINS_TEST=$(docker exec -u jenkins jenkins bash -c '
    EXEC_PATH="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh"
    
    echo "📋 File status from jenkins user:"
    ls -la "$EXEC_PATH"
    
    echo "🔍 Permission check:"
    if [ -x "$EXEC_PATH" ]; then
        echo "✅ File is executable by jenkins user"
    else
        echo "❌ File is NOT executable by jenkins user"
        exit 1
    fi
    
    echo "🧪 Version test:"
    if "$EXEC_PATH" --version >/dev/null 2>&1; then
        echo "✅ Tool executes successfully"
        "$EXEC_PATH" --version 2>&1 | head -1
    else
        echo "❌ Tool execution failed"
        exit 1
    fi
' 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "$JENKINS_TEST"
    echo ""
    echo "🎉 ✅ DEPENDENCY CHECK INSTALLATION SUCCESSFUL! ✅"
    echo ""
    echo "🎯 Installation Summary:"
    echo "   • Tool installed: OWASP Dependency Check v8.4.3"
    echo "   • Location: /var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
    echo "   • Permissions: 755 (executable by jenkins user)"
    echo "   • Ownership: jenkins:jenkins"
    echo "   • Status: Ready for pipeline use"
    echo ""
    echo "🚀 The tool is now ready for use in Jenkins pipelines!"
    echo "💡 Pipeline jobs will automatically find and use this installation"
else
    echo ""
    echo "❌ Installation verification failed"
    echo ""
    echo "🔧 Debugging information:"
    
    # Get detailed debugging info
    docker exec jenkins bash -c '
        TOOL_PATH="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
        
        echo "📁 Tool directory contents:"
        ls -la "$TOOL_PATH" 2>/dev/null | head -10
        
        echo ""
        echo "📁 Bin directory contents:"
        ls -la "$TOOL_PATH/bin/" 2>/dev/null | head -10
        
        echo ""
        echo "🔍 File system check:"
        find "$TOOL_PATH" -name "*dependency*" -o -name "*.sh" 2>/dev/null | head -10
    ' 2>/dev/null || echo "Could not retrieve debugging information"
    
    exit 1
fi

echo ""
echo "🎯 Next Steps:"
echo "   1. The tool is installed and ready"
echo "   2. Run your Jenkins pipeline to test it"
echo "   3. The pipeline should now execute without permission errors"
echo ""
echo "💡 If you still see permission errors:"
echo "   • Check Jenkins logs for other issues"
echo "   • Verify the pipeline is using the correct tool installation name"
echo "   • Restart Jenkins: make restart"