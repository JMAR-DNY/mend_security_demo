#!/bin/bash
set -e

echo "🎯 Validating Mend Security Demo Readiness..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

validation_passed=true

# Function to check and report
check_requirement() {
    local description="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "   $description: "
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        if [ -n "$expected" ]; then
            echo "      Expected: $expected"
        fi
        validation_passed=false
        return 1
    fi
}

echo ""
echo "🔍 DEMO READINESS VALIDATION"
echo "================================"

echo ""
echo "📦 Container Health:"
check_requirement "PostgreSQL container running" "docker exec dt-postgres pg_isready -U dtrack"
check_requirement "Dependency Track API responding" "curl -f http://localhost:8081/api/version"
check_requirement "Jenkins web interface accessible" "curl -f http://localhost:8080/login"
check_requirement "Dependency Track frontend accessible" "curl -f http://localhost:8082"

echo ""
echo "🔌 Jenkins Plugin Verification:"
check_requirement "Pipeline plugin installed" "docker exec jenkins test -f /var/jenkins_home/plugins/workflow-aggregator.jpi"
check_requirement "OWASP Dependency Check plugin" "docker exec jenkins test -f /var/jenkins_home/plugins/dependency-check-jenkins-plugin.jpi"
check_requirement "HTTP Request plugin" "docker exec jenkins test -f /var/jenkins_home/plugins/http_request.jpi"
check_requirement "Configuration as Code plugin" "docker exec jenkins test -f /var/jenkins_home/plugins/configuration-as-code.jpi"
check_requirement "Job DSL plugin" "docker exec jenkins test -f /var/jenkins_home/plugins/job-dsl.jpi"
check_requirement "Maven plugin" "docker exec jenkins test -f /var/jenkins_home/plugins/maven-plugin.jpi"
check_requirement "Git plugin" "docker exec jenkins test -f /var/jenkins_home/plugins/git.jpi"

echo ""
echo "🏗️ Jenkins Configuration:"
check_requirement "Jenkins admin user accessible" "curl -s -u admin:admin http://localhost:8080/whoAmI/api/json | grep -q admin"
check_requirement "WebGoat pipeline job exists" "curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json | grep -q webgoat-security-scan"
check_requirement "Maven tool configured" "curl -s -u admin:admin http://localhost:8080/configureTools/ | grep -q Maven"

echo ""
echo "🔑 Credentials and API Configuration:"
check_requirement "Dependency Track API key configured" "curl -s -u admin:admin http://localhost:8080/credentials/ | grep -q dt-api-key"
check_requirement "Dependency Track API responding to key" "curl -s -H 'X-API-Key: odt_0EvOUOJftaK9PHrVIh4yL1LgbAYHLhtJ' http://localhost:8081/api/v1/team | grep -q uuid"

echo ""
echo "🌐 Network Connectivity:"
check_requirement "Jenkins can reach Dependency Track" "docker exec jenkins curl -f http://dependency-track-apiserver:8080/api/version"
check_requirement "GitHub.com accessible from Jenkins" "docker exec jenkins curl -f https://github.com"

echo ""
echo "💾 Volume and Data Persistence:"
check_requirement "Jenkins data volume mounted" "docker exec jenkins test -d /var/jenkins_home"
check_requirement "Dependency Track data volume mounted" "docker exec dt-apiserver test -d /data"
check_requirement "PostgreSQL data persisted" "docker exec dt-postgres test -d /var/lib/postgresql/data"

echo ""
echo "================================"

if $validation_passed; then
    echo -e "${GREEN}🎉 ✅ DEMO VALIDATION PASSED! ✅ 🎉${NC}"
    echo ""
    echo "🚀 Your Mend Security Demo is ready for execution!"
    echo ""
    echo "📋 Demo Execution Checklist:"
    echo "   1. Open Jenkins: http://localhost:8080 (admin/admin)"
    echo "   2. Navigate to 'webgoat-security-scan' pipeline"
    echo "   3. Click 'Build Now'"
    echo "   4. Monitor the 5-stage pipeline execution"
    echo "   5. Review results in Dependency Track: http://localhost:8081"
    echo ""
    echo "⏱️ Expected pipeline runtime: 3-5 minutes"
    echo ""
    echo "🎯 Key demonstration points:"
    echo "   • Automated CI/CD security integration"
    echo "   • SBOM generation and management"
    echo "   • Centralized vulnerability tracking"
    echo "   • Industry-standard tooling (OWASP)"
    echo ""
    exit 0
else
    echo -e "${RED}❌ DEMO VALIDATION FAILED ❌${NC}"
    echo ""
    echo "🔧 Issues detected that need resolution before demo:"
    echo ""
    echo "💡 Recommended fixes:"
    echo "   1. Check service logs: make logs"
    echo "   2. Restart services: make restart"
    echo "   3. Verify plugin installation: make verify-plugins"
    echo "   4. Wait additional time for initialization"
    echo "   5. For clean start: make clean && make setup"
    echo ""
    echo "⏰ If recently started, allow 2-3 more minutes for full initialization"
    echo ""
    exit 1
fi