#!/bin/bash

echo "🏥 Performing comprehensive health check..."

# Service definitions
declare -A services
services["PostgreSQL"]="dt-postgres:5432"
services["Dependency Track API"]="localhost:8081"
services["Dependency Track Frontend"]="localhost:8082"
services["Jenkins"]="localhost:8080"

all_healthy=true

echo ""
echo "🔍 Checking core services..."

# Check each service
for service_name in "${!services[@]}"; do
    IFS=':' read -r host port <<< "${services[$service_name]}"
    
    if [[ $host == "dt-postgres" ]]; then
        # Special check for PostgreSQL using docker exec
        if docker exec dt-postgres pg_isready -U dtrack >/dev/null 2>&1; then
            echo "✅ $service_name is healthy"
        else
            echo "❌ $service_name is not responding"
            all_healthy=false
        fi
    else
        # HTTP check for web services
        if curl -f http://$host:$port >/dev/null 2>&1; then
            echo "✅ $service_name is healthy"
        else
            echo "❌ $service_name is not responding"
            all_healthy=false
        fi
    fi
done

echo ""
echo "🔧 Checking Jenkins-specific functionality..."

# Check if Jenkins pipeline job exists
JOB_CHECK=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -o '"name":"webgoat-security-scan"' || echo "")

if [ -n "$JOB_CHECK" ]; then
    echo "✅ WebGoat security scan pipeline job exists"
else
    echo "❌ WebGoat security scan pipeline job not found"
    all_healthy=false
fi

# Check essential Jenkins plugins
echo ""
echo "🔌 Checking essential Jenkins plugins..."

ESSENTIAL_PLUGINS=(
    "workflow-aggregator"
    "dependency-check-jenkins-plugin" 
    "http_request"
    "configuration-as-code"
    "job-dsl"
    "maven-plugin"
    "git"
)

plugin_issues=false

for plugin in "${ESSENTIAL_PLUGINS[@]}"; do
    if docker exec jenkins test -f "/var/jenkins_home/plugins/${plugin}.jpi" 2>/dev/null; then
        echo "✅ $plugin plugin installed"
    else
        echo "❌ $plugin plugin missing"
        plugin_issues=true
        all_healthy=false
    fi
done

# Check Dependency Track API accessibility
echo ""
echo "🛡️ Checking Dependency Track API..."

DT_VERSION=$(curl -s http://localhost:8081/api/version 2>/dev/null || echo "")
if [[ $DT_VERSION == *"version"* ]]; then
    echo "✅ Dependency Track API is responding"
    # Extract version if possible
    VERSION_NUM=$(echo $DT_VERSION | grep -o '"version":"[^"]*' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    echo "   Version: $VERSION_NUM"
else
    echo "❌ Dependency Track API not responding properly"
    all_healthy=false
fi

# Check API key configuration
API_KEY_CHECK=$(curl -s -H "X-API-Key: odt_0EvOUOJftaK9PHrVIh4yL1LgbAYHLhtJ" http://localhost:8081/api/v1/team 2>/dev/null || echo "")
if [[ $API_KEY_CHECK == *"uuid"* ]]; then
    echo "✅ Dependency Track API key is working"
else
    echo "⚠️ Dependency Track API key may need configuration"
fi

echo ""
echo "📊 Container Status Summary:"
docker-compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"

echo ""

# Final health assessment
if $all_healthy; then
    echo "🎉 ✅ ALL SYSTEMS HEALTHY! ✅"
    echo ""
    echo "🚀 Ready for demo execution:"
    echo "   1. Go to Jenkins: http://localhost:8080 (admin/admin)"
    echo "   2. Run 'webgoat-security-scan' pipeline job"
    echo "   3. Monitor results in Dependency Track: http://localhost:8081"
    exit 0
else
    echo "⚠️ ❌ SOME ISSUES DETECTED ❌"
    echo ""
    echo "🔧 Recommended actions:"
    
    if $plugin_issues; then
        echo "   • Plugin issues detected - try: make restart"
        echo "   • Check plugin installation: make verify-plugins"
    fi
    
    echo "   • Check detailed logs: make logs"
    echo "   • Restart services: make restart"
    echo "   • For fresh start: make clean && make setup"
    echo ""
    echo "💡 Common fixes:"
    echo "   • Wait 2-3 more minutes for full initialization"
    echo "   • Ensure sufficient RAM (8GB+ recommended)"
    echo "   • Check Docker resources allocation"
    exit 1
fi