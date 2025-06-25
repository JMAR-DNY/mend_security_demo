#!/bin/bash
set -e

echo "🔧 Rebuilding OWASP Dependency Check Script"
echo "============================================"

# Check if Jenkins is running
if ! docker ps | grep -q "jenkins"; then
    echo "❌ Jenkins container is not running"
    exit 1
fi

echo "✅ Jenkins container is running"
echo ""

echo "🔍 Analyzing the corrupted script..."

docker exec jenkins bash -c '
    EXEC_PATH="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh"
    
    echo "📋 Current script analysis:"
    if [ -f "$EXEC_PATH" ]; then
        echo "File size: $(wc -c < "$EXEC_PATH") bytes"
        echo "File type: $(file "$EXEC_PATH")"
        echo "First line: $(head -1 "$EXEC_PATH")"
        echo "Last line: $(tail -1 "$EXEC_PATH")"
        echo ""
        echo "Hex dump of first 100 bytes:"
        hexdump -C "$EXEC_PATH" | head -5
    fi
'

echo ""
echo "🔄 Creating a completely new working script..."

docker exec -u root jenkins bash -c '
    set -e
    
    TOOL_DIR="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
    EXEC_PATH="$TOOL_DIR/bin/dependency-check.sh"
    
    echo "📁 Tool directory: $TOOL_DIR"
    
    # Backup the corrupted script
    if [ -f "$EXEC_PATH" ]; then
        cp "$EXEC_PATH" "$EXEC_PATH.corrupted-backup"
        echo "✅ Corrupted script backed up"
    fi
    
    echo "📝 Creating new dependency-check.sh script..."
    
    # Create a completely new script that mimics the original functionality
    cat > "$EXEC_PATH" << '\''EOF'\''
#!/bin/bash

#
# OWASP Dependency-Check
# Command Line Tool
# Rebuilt version to fix execution issues
#

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

# Set up Java classpath
CLASSPATH="$APP_DIR/lib/*"

# Check if Java is available
if ! command -v java >/dev/null 2>&1; then
    echo "Error: Java is not available in PATH"
    echo "Please ensure Java 8 or later is installed and in your PATH"
    exit 1
fi

# Check if the main JAR exists
MAIN_JAR="$APP_DIR/lib/dependency-check-cli-8.4.3.jar"
if [ ! -f "$MAIN_JAR" ]; then
    echo "Error: Main JAR not found at $MAIN_JAR"
    echo "Available JARs:"
    ls -la "$APP_DIR/lib/" | grep dependency-check
    exit 1
fi

# Set Java options for better performance and compatibility
JAVA_OPTS="${JAVA_OPTS:-} -Xmx4g"
JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=UTF-8"
JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"

# Execute the dependency check
exec java $JAVA_OPTS -cp "$CLASSPATH" org.owasp.dependencycheck.App "$@"
EOF

    echo "✅ New script created"
    
    # Set proper permissions and ownership
    chmod 755 "$EXEC_PATH"
    chown jenkins:jenkins "$EXEC_PATH"
    
    echo "🔐 Permissions set: $(ls -la "$EXEC_PATH")"
    
    # Verify the script content
    echo ""
    echo "📋 New script content (first 10 lines):"
    head -10 "$EXEC_PATH"
    
    echo ""
    echo "🔍 File verification:"
    echo "File type: $(file "$EXEC_PATH")"
    echo "Executable test: $(test -x "$EXEC_PATH" && echo "✅ YES" || echo "❌ NO")"
'

echo ""
echo "🧪 Testing the rebuilt script..."

TEST_RESULT=$(docker exec -u jenkins jenkins bash -c '
    EXEC_PATH="/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check/bin/dependency-check.sh"
    
    echo "🔍 Testing as jenkins user:"
    echo "User: $(whoami)"
    echo "User ID: $(id)"
    echo ""
    
    if [ -f "$EXEC_PATH" ]; then
        echo "✅ Script exists"
        echo "📋 Permissions: $(ls -la "$EXEC_PATH")"
        
        if [ -x "$EXEC_PATH" ]; then
            echo "✅ Script is executable"
            
            echo "🧪 Testing script execution..."
            if "$EXEC_PATH" --version 2>&1; then
                echo ""
                echo "✅ SCRIPT EXECUTION SUCCESSFUL!"
                echo "SUCCESS"
            else
                echo ""
                echo "❌ Script execution failed"
                echo "Error details:"
                "$EXEC_PATH" --version 2>&1 | head -5
                echo "EXEC_FAILED"
            fi
        else
            echo "❌ Script not executable"
            echo "PERMISSION_FAILED"
        fi
    else
        echo "❌ Script not found"
        echo "FILE_MISSING"
    fi
' 2>/dev/null)

echo "$TEST_RESULT"

# Determine success and provide next steps
if echo "$TEST_RESULT" | grep -q "SUCCESS"; then
    echo ""
    echo "🎉 ✅ DEPENDENCY CHECK SCRIPT REBUILD SUCCESSFUL! ✅"
    echo ""
    echo "🎯 What was fixed:"
    echo "   • Completely rebuilt the corrupted script"
    echo "   • Added proper shebang and error handling"
    echo "   • Set correct Java classpath and options"
    echo "   • Applied proper permissions (755 jenkins:jenkins)"
    echo ""
    echo "🚀 Your Jenkins pipeline should now work!"
    echo ""
    echo "💡 You can now:"
    echo "   1. Use the original dependencyCheck(...) plugin step, OR"
    echo "   2. Use the shell execution method from the previous suggestion"
    echo ""
    echo "✅ Both approaches should work now that the script is properly rebuilt"
    
elif echo "$TEST_RESULT" | grep -q "EXEC_FAILED"; then
    echo ""
    echo "⚠️ Script rebuilt but execution still fails"
    echo ""
    echo "🔧 This might be a Java or classpath issue. Add this to your pipeline:"
    echo ""
    echo "sh ''''"
    echo "    # Set Java environment"
    echo "    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
    echo "    export PATH=\$JAVA_HOME/bin:\$PATH"
    echo "    "
    echo "    # Execute with explicit classpath"
    echo "    TOOL_DIR=\"/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check\""
    echo "    java -cp \"\$TOOL_DIR/lib/*\" org.owasp.dependencycheck.App --scan . --format ALL --enableRetired --out ."
    echo "''''"
    
else
    echo ""
    echo "❌ Script rebuild had issues"
    echo ""
    echo "🔧 Alternative: Use Java directly in your pipeline:"
    echo ""
    echo "sh ''''"
    echo "    TOOL_DIR=\"/var/jenkins_home/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check\""
    echo "    java -Xmx4g -cp \"\$TOOL_DIR/lib/*\" org.owasp.dependencycheck.App \\"
    echo "        --scan . \\"
    echo "        --format ALL \\"
    echo "        --enableRetired \\"
    echo "        --out ."
    echo "''''"
fi

echo ""
echo "🔍 Manual verification commands:"
echo "   • Test script: docker exec -u jenkins jenkins /var/jenkins_home/tools/.../dependency-check/bin/dependency-check.sh --version"
echo "   • Test Java: docker exec -u jenkins jenkins java -cp \"/var/jenkins_home/tools/.../dependency-check/lib/*\" org.owasp.dependencycheck.App --version"
echo "   • Check files: docker exec jenkins ls -la /var/jenkins_home/tools/.../dependency-check/lib/ | grep dependency-check"