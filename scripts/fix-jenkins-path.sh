#!/bin/bash
set -e

echo "🎯 Final Dependency Check Fix - Testing as Correct User"
echo "======================================================"

# Check if Jenkins is running
if ! docker ps | grep -q "jenkins"; then
    echo "❌ Jenkins container is not running"
    exit 1
fi

echo "✅ Jenkins container is running"
echo ""

echo "🔧 Testing execution as both root and jenkins users..."

# Test as jenkins user specifically
TEST_RESULT=$(docker exec jenkins bash -c '
    TOOL_PATH="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
    EXEC_PATH="$TOOL_PATH/bin/dependency-check.sh"
    
    echo "=== Testing as ROOT USER ==="
    echo "Current user: $(whoami)"
    echo "User ID: $(id)"
    
    if [ -f "$EXEC_PATH" ]; then
        echo "✅ Script exists"
        echo "📋 Permissions: $(ls -la "$EXEC_PATH")"
        
        if [ -x "$EXEC_PATH" ]; then
            echo "✅ Root can execute the script"
            if "$EXEC_PATH" --version >/dev/null 2>&1; then
                echo "✅ ROOT EXECUTION SUCCESSFUL"
                VERSION=$("$EXEC_PATH" --version 2>&1 | head -1)
                echo "Version: $VERSION"
            else
                echo "❌ Root execution failed"
                "$EXEC_PATH" --version 2>&1 | head -3
            fi
        else
            echo "❌ Root cannot execute"
        fi
    fi
    
    echo ""
    echo "=== Testing as JENKINS USER ==="
    
    # Switch to jenkins user for the real test
    su - jenkins -c "
        EXEC_PATH=\"$EXEC_PATH\"
        echo \"Current user: \$(whoami)\"
        echo \"User ID: \$(id)\"
        
        if [ -f \"\$EXEC_PATH\" ]; then
            echo \"✅ Script exists for jenkins user\"
            echo \"📋 Permissions from jenkins perspective: \$(ls -la \"\$EXEC_PATH\")\"
            
            if [ -x \"\$EXEC_PATH\" ]; then
                echo \"✅ Jenkins user can execute the script\"
                if \"\$EXEC_PATH\" --version >/dev/null 2>&1; then
                    echo \"✅ JENKINS EXECUTION SUCCESSFUL\"
                    VERSION=\$(\"\$EXEC_PATH\" --version 2>&1 | head -1)
                    echo \"Version: \$VERSION\"
                    echo \"SUCCESS_JENKINS\"
                else
                    echo \"❌ Jenkins execution failed\"
                    \"\$EXEC_PATH\" --version 2>&1 | head -3
                    echo \"EXEC_FAILED_JENKINS\"
                fi
            else
                echo \"❌ Jenkins user cannot execute\"
                echo \"PERMISSION_DENIED_JENKINS\"
            fi
        else
            echo \"❌ Script not found for jenkins user\"
            echo \"FILE_NOT_FOUND_JENKINS\"
        fi
    "
' 2>/dev/null)

echo "$TEST_RESULT"

# Analyze results and provide solution
if echo "$TEST_RESULT" | grep -q "SUCCESS_JENKINS"; then
    echo ""
    echo "🎉 ✅ DEPENDENCY CHECK IS WORKING FOR JENKINS USER! ✅"
    echo ""
    echo "🎯 The issue was just the test context. Your Jenkins pipeline should work now!"
    echo ""
    echo "🚀 Try running your Jenkins pipeline:"
    echo "   1. Go to Jenkins: http://localhost:8080"
    echo "   2. Run your 'webgoat-security-scan' pipeline job" 
    echo "   3. The dependencyCheck step should now work"
    echo ""
    echo "✅ No pipeline changes needed - the tool is working correctly!"
    
elif echo "$TEST_RESULT" | grep -q "EXEC_FAILED_JENKINS"; then
    echo ""
    echo "⚠️ Script is executable by jenkins user but execution fails"
    echo ""
    echo "🔧 This might be a Java classpath or environment issue."
    echo "Add this to your Jenkins pipeline as a workaround:"
    echo ""
    echo "stage('Dependency Check Scan') {"
    echo "    steps {"
    echo "        sh ''''"
    echo "            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
    echo "            export PATH=\$JAVA_HOME/bin:\$PATH"
    echo "            /var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh \\"
    echo "                --scan \$PWD --format ALL --enableRetired --out \$PWD"
    echo "        ''''"
    echo "    }"
    echo "}"
    
elif echo "$TEST_RESULT" | grep -q "PERMISSION_DENIED_JENKINS"; then
    echo ""
    echo "❌ Jenkins user still cannot execute the script"
    echo ""
    echo "🔧 Apply this fix and then test your pipeline:"
    
    docker exec -u root jenkins bash -c '
        EXEC_PATH="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh"
        
        echo "🔧 Applying maximum permissions for compatibility..."
        chmod 777 "$EXEC_PATH"
        chown jenkins:jenkins "$EXEC_PATH"
        
        echo "📋 New permissions:"
        ls -la "$EXEC_PATH"
    '
    
    echo ""
    echo "✅ Maximum permissions applied. Try your pipeline now."
    
else
    echo ""
    echo "❌ Unexpected test results"
    echo ""
    echo "🔧 Use this pipeline workaround that bypasses the plugin:"
    echo ""
    echo "stage('Dependency Check Scan') {"
    echo "    steps {"
    echo "        sh ''''"
    echo "            TOOL_PATH=\"/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check\""
    echo "            chmod +x \"\$TOOL_PATH/bin/dependency-check.sh\""
    echo "            \"\$TOOL_PATH/bin/dependency-check.sh\" --scan \$PWD --format ALL --enableRetired --out \$PWD"
    echo "        ''''"
    echo "    }"
    echo "}"
fi

echo ""
echo "💡 Quick verification commands:"
echo "   • Test as jenkins: docker exec -u jenkins jenkins /var/jenkins_home/tools/.../dependency-check/bin/dependency-check.sh --version"
echo "   • Check permissions: docker exec jenkins ls -la /var/jenkins_home/tools/.../dependency-check/bin/"
echo "   • View Java env: docker exec -u jenkins jenkins java -version"