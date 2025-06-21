#!/bin/bash
set -e

echo "🔧 Installing Jenkins plugins for Mend Security Demo..."

# Wait for Jenkins to be fully accessible
echo "⏳ Waiting for Jenkins to be fully ready..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    if curl -f http://localhost:8080/login >/dev/null 2>&1; then
        echo "✅ Jenkins is accessible"
        break
    fi
    echo "   Attempt $attempt/$max_attempts - waiting for Jenkins..."
    sleep 10
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ Jenkins failed to become accessible"
    exit 1
fi

# Additional wait for Jenkins to be fully initialized
echo "⏳ Allowing Jenkins to fully initialize..."
sleep 30

# Install plugins using Jenkins CLI
echo "📦 Installing required plugins..."

# List of essential plugins for the Mend demo
PLUGINS=(
    "workflow-aggregator"
    "git"
    "maven-plugin" 
    "dependency-check-jenkins-plugin"
    "http_request"
    "pipeline-utility-steps"
    "configuration-as-code"
    "job-dsl"
    "credentials"
    "credentials-binding"
    "timestamper"
    "workspace-cleanup"
    "build-timeout"
    "pipeline-stage-view"
    "matrix-auth"
    "structs"
    "script-security"
)

# Install each plugin
for plugin in "${PLUGINS[@]}"; do
    echo "Installing $plugin..."
    java -jar /var/jenkins_home/war/WEB-INF/lib/cli-*.jar \
        -s http://localhost:8080/ \
        -auth admin:admin \
        install-plugin "$plugin" || echo "  ⚠️ $plugin may already be installed or have issues"
done

echo "✅ Plugin installation completed"

# Restart Jenkins to activate plugins
echo "🔄 Restarting Jenkins to activate plugins..."
java -jar /var/jenkins_home/war/WEB-INF/lib/cli-*.jar \
    -s http://localhost:8080/ \
    -auth admin:admin \
    restart

echo "✅ Jenkins restart initiated"
echo "⏳ Please wait 60-90 seconds for Jenkins to come back online"