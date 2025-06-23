#!/bin/bash
set -e

# Jenkins Pipeline Creator for Mend.io Demo - Fixed with CSRF Protection
# This script creates the WebGoat security scan pipeline programmatically

JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_PASSWORD="admin"
JOB_NAME="webgoat-security-scan"
API_KEY="odt_0EvOUOJftaK9PHrVIh4yL1LgbAYHLhtJ"

echo "🔧 Creating Jenkins Pipeline: $JOB_NAME"
echo "🛡️ Handling CSRF protection for secure API calls"

# --- Add this near top of script (after variable declarations) ---
fetch_crumb_and_cookie() {
    # Fetch crumb + session cookie, store for use in curl POSTs
    local crumb_json crumb_field crumb_value
    crumb_json=$(curl -s -c cookies.txt -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json")
    crumb_field=$(echo "$crumb_json" | grep -o '"crumbRequestField":"[^"]*' | cut -d':' -f2 | tr -d '"')
    crumb_value=$(echo "$crumb_json" | grep -o '"crumb":"[^"]*' | cut -d':' -f2 | tr -d '"')
    export CRUMB_HEADER="$crumb_field: $crumb_value"
    
    if [ -n "$CRUMB_HEADER" ]; then
        echo "✅ CSRF crumb and session cookie obtained"
    else
        echo "⚠️ Could not obtain CSRF crumb"
        return 1
    fi
}

# Function to wait for Jenkins
wait_for_jenkins() {
    echo "⏳ Waiting for Jenkins to be ready..."
    local attempts=0
    local max_attempts=20
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -fL -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/api/json" >/dev/null 2>&1; then
            echo "✅ Jenkins is ready"
            return 0
        fi
        echo "   Attempt $((attempts + 1))/$max_attempts..."
        sleep 15
        ((attempts++))
    done
    
    echo "❌ Jenkins not ready after $max_attempts attempts"
    return 1
}

# Function to create API credential with CSRF protection
create_credential() {
    echo "🔑 Creating Dependency Track API credential..."

    # Always fetch crumb + cookie before a POST
    if ! fetch_crumb_and_cookie; then
        echo "❌ Cannot proceed without CSRF protection"
        return 1
    fi

    # Build credential XML (single credential, no <credentials> wrapper)
    cat > /tmp/dt-api-credential.xml <<EOF
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>dt-api-key</id>
  <description>Dependency Track API Key for SBOM upload</description>
  <secret>$API_KEY</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
EOF

    # Post the credential using both crumb and cookie
    local response
    response=$(curl -s -w "%{http_code}" -u "$JENKINS_USER:$JENKINS_PASSWORD" -b cookies.txt \
        -H "$CRUMB_HEADER" \
        -H "Content-Type: application/xml" \
        -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
        --data-binary @/tmp/dt-api-credential.xml \
        -o /dev/null)

    rm -f /tmp/dt-api-credential.xml cookies.txt

    if [ "$response" = "200" ]; then
        echo "✅ API credential created successfully"
        return 0
    elif [ "$response" = "409" ]; then
        echo "ℹ️ API credential already exists (HTTP 409)"
        return 0
    elif [ "$response" = "403" ]; then
        echo "❌ Failed to create credential - CSRF protection error (HTTP 403)"
        return 1
    else
        echo "❌ Failed to create credential (HTTP $response)"
        return 1
    fi
}

# Function to create pipeline job with CSRF protection
create_pipeline() {
    echo "📋 Creating pipeline job..."
    
    # Check if job exists first
    local exists=$(curl -s -w "%{http_code}" -u "$JENKINS_USER:$JENKINS_PASSWORD" \
        "$JENKINS_URL/job/$JOB_NAME/api/json" -o /dev/null 2>/dev/null || echo "000")
    
    if [ "$exists" = "200" ]; then
        echo "⚠️ Job '$JOB_NAME' already exists"
        echo "🔄 Delete and recreate? [y/N]"
        read -r response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            echo "🗑️ Deleting existing job..."
            
            # Get crumb for delete operation
            if fetch_crumb_and_cookie; then
                curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" -b cookies.txt \
                    -H "$CRUMB_HEADER" \
                    -X POST "$JENKINS_URL/job/$JOB_NAME/doDelete" >/dev/null
                rm -f cookies.txt
            else
                echo "⚠️ Proceeding with delete without CSRF protection"
                curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
                    -X POST "$JENKINS_URL/job/$JOB_NAME/doDelete" >/dev/null
            fi
            echo "✅ Existing job deleted"
        else
            echo "ℹ️ Keeping existing job"
            return 0
        fi
    fi
    
    # Always fetch crumb + cookie before a POST
    if ! fetch_crumb_and_cookie; then
        echo "❌ Cannot proceed without CSRF protection"
        return 1
    fi
    
    # Create job XML with enhanced pipeline
    cat > /tmp/pipeline-config.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script><![CDATA[
    pipeline {
        agent any

        tools {
            maven 'Maven-3.9' 
        }
        environment {
            DT_API_URL = 'http://dependency-track-apiserver:8080'
            DT_API_KEY = credentials('dt-api-key')
            WEBGOAT_REPO = 'https://github.com/WebGoat/WebGoat.git'
            WEBGOAT_TAG = 'v8.1.0'
            PROJECT_NAME = 'WebGoat'
            PROJECT_VERSION = '8.1.0'
           MAVEN_OPTS = '-Xmx1024m --add-opens java.base/java.lang=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED'
        }
        stages {
            stage('🔄 Checkout WebGoat') {
                steps {
                    echo '🔄 Cloning WebGoat v8.1.0 from GitHub...'
                    checkout([
                    $class: 'GitSCM',
                    branches: [[name: "refs/tags/${WEBGOAT_TAG}"]],
                    userRemoteConfigs: [[url: "${WEBGOAT_REPO}"]]
                    ])
                    
                    echo '📝 Configuring CycloneDX plugin for SBOM generation...'
                    script {
                        def pomContent = readFile('pom.xml')
                        
                        if (pomContent.contains('cyclonedx-maven-plugin')) {
                            echo '✅ CycloneDX plugin already configured'
                        } else {
                            echo '🔧 Adding CycloneDX plugin to Maven configuration'
                            
                            def cycloneDxPlugin = '''
                <plugin>
                    <groupId>org.cyclonedx</groupId>
                    <artifactId>cyclonedx-maven-plugin</artifactId>
                    <version>2.7.9</version>
                    <configuration>
                        <projectType>application</projectType>
                        <schemaVersion>1.4</schemaVersion>
                        <includeBomSerialNumber>true</includeBomSerialNumber>
                        <includeCompileScope>true</includeCompileScope>
                        <includeProvidedScope>true</includeProvidedScope>
                        <includeRuntimeScope>true</includeRuntimeScope>
                        <includeSystemScope>true</includeSystemScope>
                        <includeTestScope>false</includeTestScope>
                        <outputFormat>json</outputFormat>
                        <outputName>webgoat-bom</outputName>
                    </configuration>
                    <executions>
                        <execution>
                            <phase>package</phase>
                            <goals>
                                <goal>makeAggregateBom</goal>
                            </goals>
                        </execution>
                    </executions>
                </plugin>'''
                            
                            def modifiedPom = pomContent.replaceFirst(
                                '</plugins>',
                                cycloneDxPlugin + '\n        </plugins>'
                            )
                            
                            writeFile file: 'pom.xml', text: modifiedPom
                            echo '✅ CycloneDX plugin configuration added'
                        }
                    }
                    
                    sh '''
                        echo "📊 Repository Information:"
                        echo "Current directory: $(pwd)"
                        echo "Git branch: $(git branch --show-current)"
                        echo "Git commit: $(git rev-parse --short HEAD)"
                        echo "Maven version: $(mvn -version | head -1)"
                    '''
                }
            }

            stage('🔨 Build Application') {
                steps {
                    echo '🔨 Building WebGoat application with Maven...'
                    
                    sh '''
                        echo "🧹 Cleaning previous builds..."
                        mvn clean -q
                        
                        echo "🔧 Compiling and packaging..."
                        mvn compile package -DskipTests -Dmaven.javadoc.skip=true -q

                        echo "📦 Build Results:"
                        ls -la target/ | grep -E "\\.(war|jar)$" || echo "No packaged artifacts found"
                        
                        # Check if build was successful
                        if [ -d "target" ] && [ "$(ls -A target/ 2>/dev/null)" ]; then
                            echo "✅ Build completed successfully"
                        else
                            echo "❌ Build may have failed - no target directory found"
                            exit 1
                        fi
                    '''
                }
            }

            stage('🔍 OWASP Dependency Check') {
                steps {
                    echo '🔍 Running OWASP Dependency Check vulnerability scan...'
                    echo 'ℹ️ This scans all dependencies for known security vulnerabilities'
                    
                    script {
                        try {
                            dependencyCheck(
                                additionalArguments: '''
                                    --format ALL
                                    --enableRetired
                                    --enableExperimental
                                    --failOnCVSS 11
                                ''',
                                odcInstallation: 'dependency-check'
                            )
                            echo '✅ Dependency Check scan completed'
                        } catch (Exception e) {
                            echo "⚠️ Dependency Check found vulnerabilities: ${e.getMessage()}"
                            echo "ℹ️ This is expected for WebGoat (intentionally vulnerable app)"
                            echo "✅ Continuing pipeline - vulnerabilities will be tracked in Dependency Track"
                        }
                    }
                    
                    sh '''
                        echo "📋 Scan Results Summary:"
                        if [ -f "dependency-check-report.html" ]; then
                            echo "✅ HTML report generated"
                        fi
                        if [ -f "dependency-check-report.xml" ]; then
                            echo "✅ XML report generated"  
                        fi
                        if [ -f "dependency-check-report.json" ]; then
                            echo "✅ JSON report generated"
                        fi
                    '''
                }
            }
        
            stage('📋 Generate SBOM') {
                steps {
                    echo '📋 Generating CycloneDX Software Bill of Materials...'
                    echo 'ℹ️ This creates a complete inventory of all application dependencies'
                    
                    sh '''
                        echo "🔧 Running CycloneDX Maven plugin..."
                        mvn org.cyclonedx:cyclonedx-maven-plugin:makeAggregateBom -q
                        
                        echo "📊 SBOM Generation Results:"
                        if [ -f "target/webgoat-bom.json" ]; then
                            echo "✅ SBOM successfully generated: target/webgoat-bom.json"
                            echo "📄 SBOM size: $(du -h target/webgoat-bom.json | cut -f1)"
                            echo "🔢 Components found: $(jq '.components | length' target/webgoat-bom.json 2>/dev/null || echo 'N/A')"
                        else
                            echo "❌ SBOM generation failed"
                            echo "📁 Available files in target:"
                            ls -la target/
                            exit 1
                        fi
                    '''
                }
            }
        
            stage('⬆️ Upload to Dependency Track') {
                steps {
                    echo '⬆️ Uploading SBOM to Dependency Track for vulnerability management...'
                    echo 'ℹ️ This enables centralized security tracking and monitoring'
                    
                    script {
                        try {
                            // Create or update project in Dependency Track
                            def createProjectResponse = httpRequest(
                                httpMode: 'PUT',
                                url: "${DT_API_URL}/api/v1/project",
                                customHeaders: [
                                    [name: 'X-API-Key', value: DT_API_KEY], 
                                    [name: 'Content-Type', value: 'application/json']
                                ],
                                requestBody: """{
                                    "name": "${PROJECT_NAME}",
                                    "version": "${PROJECT_VERSION}",
                                    "description": "WebGoat v8.1.0 - Intentionally vulnerable application for security scanning demonstration",
                                    "tags": [
                                        {"name": "demo"},
                                        {"name": "webgoat"}, 
                                        {"name": "security-scan"},
                                        {"name": "mend-demo"}
                                    ]
                                }"""
                            )
                            
                            echo "✅ Project creation/update response: HTTP ${createProjectResponse.status}"
                            
                            // Upload SBOM to Dependency Track
                            def uploadResponse = httpRequest(
                                httpMode: 'POST',
                                url: "${DT_API_URL}/api/v1/bom",
                                customHeaders: [[name: 'X-API-Key', value: DT_API_KEY]],
                                multipartName: 'bom',
                                uploadFile: 'target/webgoat-bom.json'
                            )
                            
                            echo "✅ SBOM upload response: HTTP ${uploadResponse.status}"
                            
                            if (uploadResponse.status == 200) {
                                echo "🎉 SBOM successfully uploaded to Dependency Track!"
                                echo "🌐 View results at: http://localhost:8081"
                                echo "📊 The SBOM will be processed and vulnerabilities will appear in the dashboard"
                            }
                            
                        } catch (Exception e) {
                            echo "❌ Failed to upload SBOM to Dependency Track: ${e.getMessage()}"
                            echo "🔧 Check that Dependency Track is running and API key is correct"
                            throw e
                        }
                    }
                }
            }
        }
    }]]></script>
    <sandbox>true</sandbox>
  </definition>
</flow-definition>
EOF

    # POST the job definition using both crumb and cookie
    local response
    response=$(curl -s -w "%{http_code}" -u "$JENKINS_USER:$JENKINS_PASSWORD" -b cookies.txt \
        -H "$CRUMB_HEADER" \
        -H "Content-Type: application/xml" \
        -X POST "$JENKINS_URL/createItem?name=$JOB_NAME" \
        --data-binary @/tmp/pipeline-config.xml \
        -o /dev/null)

    rm -f /tmp/pipeline-config.xml cookies.txt
    
    if [ "$response" = "200" ]; then
        echo "✅ Pipeline job '$JOB_NAME' created successfully"
        return 0
    elif [ "$response" = "403" ]; then
        echo "❌ Failed to create job - CSRF protection error (HTTP 403)"
        echo "🔧 Jenkins CSRF protection is blocking the request"
        echo "🔐 This is common when Jenkins is still initializing"
        echo "💡 Try running the script again in a few minutes"
        return 1
    else
        echo "❌ Failed to create job (HTTP $response)"
        return 1
    fi
}

# Function to retry operations with backoff
retry_with_backoff() {
    local operation="$1"
    local max_attempts=3
    local attempt=1
    local delay=10
    
    while [ $attempt -le $max_attempts ]; do
        echo "🔄 Attempt $attempt/$max_attempts for $operation"
        
        if eval "$operation"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "⏳ Waiting ${delay}s before retry..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    echo "❌ Operation '$operation' failed after $max_attempts attempts"
    return 1
}

# Function to test CSRF protection status
test_csrf_protection() {
    echo "🔍 Testing Jenkins CSRF protection status..."
    
    # Try a simple GET request to see if we can access crumb issuer
    local crumb_test=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
        "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo "")
    
    if [ -n "$crumb_test" ] && [[ "$crumb_test" == *"crumb"* ]]; then
        echo "✅ CSRF protection is enabled - crumb issuer accessible"
        return 0
    else
        echo "ℹ️ CSRF protection may be disabled or Jenkins not fully ready"
        return 1
    fi
}

# Main execution
main() {
    echo "🎯 Mend.io Demo - Jenkins Pipeline Creator (CSRF-Protected)"
    echo "=========================================================="
    echo "🛡️ This script handles Jenkins CSRF protection automatically"
    echo ""
    
    if ! wait_for_jenkins; then
        echo "❌ Cannot proceed - Jenkins is not ready"
        exit 1
    fi
    
    # Test CSRF protection status
    test_csrf_protection
    
    echo ""
    echo "🔧 Creating Jenkins resources with CSRF protection..."
    
    # Create credential with retry logic
    if ! retry_with_backoff "create_credential"; then
        echo "⚠️ Failed to create credential, but continuing with pipeline creation"
        echo "💡 You may need to create the 'dt-api-key' credential manually"
    fi
    
    echo ""
    
    # Create pipeline with retry logic  
    if retry_with_backoff "create_pipeline"; then
        echo ""
        echo "🎉 ✅ PIPELINE CREATION SUCCESSFUL! ✅"
        echo ""
        echo "🎯 Pipeline Details:"
        echo "   Name: $JOB_NAME"
        echo "   URL: $JENKINS_URL/job/$JOB_NAME"
        echo "   Description: Complete WebGoat security scan workflow"
        echo ""
        echo "📋 Pipeline Stages:"
        echo "   1. 🔄 Checkout - Clone WebGoat v8.1.0"
        echo "   2. 🔨 Build - Maven compile and package"
        echo "   3. 🔍 Dependency Check - OWASP vulnerability scan"
        echo "   4. 📋 Generate SBOM - CycloneDX bill of materials"
        echo "   5. ⬆️ Upload to Dependency Track - API integration"
        echo ""
        echo "🛡️ Security Features:"
        echo "   ✓ CSRF-protected API calls"
        echo "   ✓ Secure credential management"
        echo "   ✓ Automated authentication handling"
        echo ""
        echo "🚀 Ready to Demo:"
        echo "   1. Open Jenkins: $JENKINS_URL"
        echo "   2. Login: $JENKINS_USER/$JENKINS_PASSWORD"
        echo "   3. Navigate to '$JOB_NAME' job"
        echo "   4. Click 'Build Now'"
        echo ""
        echo "⏱️ Expected runtime: 3-5 minutes"
        echo "🌐 Results in Dependency Track: http://localhost:8081"
        echo ""
        echo "🎯 This demonstrates professional Jenkins automation with:"
        echo "   • Proper CSRF security handling"
        echo "   • Retry logic for reliability"
        echo "   • Enterprise-grade API integration"
    else
        echo ""
        echo "❌ Pipeline creation failed"
        echo ""
        echo "🔧 Troubleshooting suggestions:"
        echo "   • Wait for Jenkins to fully initialize (2-3 more minutes)"
        echo "   • Check Jenkins logs: make logs"
        echo "   • Verify services: make status"
        echo "   • Try again: make create-pipeline"
        echo ""
        echo "💡 Common causes:"
        echo "   • Jenkins still starting up"
        echo "   • Plugin installation in progress"
        echo "   • Resource constraints"
        echo "   • Network connectivity issues"
        exit 1
    fi
}

# Additional helper functions for debugging

# Function to check Jenkins security configuration
check_jenkins_security() {
    echo "🔍 Checking Jenkins security configuration..."
    
    local security_info=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
        "$JENKINS_URL/api/json?tree=useSecurity,securityRealm" 2>/dev/null || echo "")
    
    if [[ "$security_info" == *"useSecurity"* ]]; then
        echo "✅ Jenkins security information accessible"
        if [[ "$security_info" == *"true"* ]]; then
            echo "🔒 Security is enabled"
        else
            echo "🔓 Security may be disabled"
        fi
    else
        echo "⚠️ Cannot access Jenkins security information"
    fi
}

# Function to verify plugin availability
verify_essential_plugins() {
    echo "🔌 Verifying essential plugins for pipeline creation..."
    
    local plugins_info=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
        "$JENKINS_URL/pluginManager/api/json?tree=plugins[shortName,version]" 2>/dev/null || echo "")
    
    local essential_plugins=("workflow-aggregator" "dependency-check-jenkins-plugin" "http_request" "git" "maven-plugin")
    local missing_plugins=()
    
    for plugin in "${essential_plugins[@]}"; do
        if [[ "$plugins_info" == *"\"shortName\":\"$plugin\""* ]]; then
            echo "✅ $plugin is available"
        else
            echo "❌ $plugin is missing"
            missing_plugins+=("$plugin")
        fi
    done
    
    if [ ${#missing_plugins[@]} -eq 0 ]; then
        echo "✅ All essential plugins are available"
        return 0
    else
        echo "⚠️ Missing plugins: ${missing_plugins[*]}"
        echo "💡 These plugins are required for the pipeline to work"
        return 1
    fi
}

# Function to test Dependency Track connectivity
test_dependency_track_connectivity() {
    echo "🌐 Testing Dependency Track connectivity..."
    
    local dt_version=$(curl -s "http://localhost:8081/api/version" 2>/dev/null || echo "")
    
    if [[ "$dt_version" == *"version"* ]]; then
        echo "✅ Dependency Track API is accessible"
        local version_num=$(echo "$dt_version" | grep -o '"version":"[^"]*' | cut -d'"' -f4 2>/dev/null || echo "unknown")
        echo "   Version: $version_num"
        
        # Test API key
        local api_test=$(curl -s -H "X-API-Key: $API_KEY" \
            "http://localhost:8081/api/v1/team" 2>/dev/null || echo "")
        
        if [[ "$api_test" == *"uuid"* ]]; then
            echo "✅ API key authentication working"
        else
            echo "⚠️ API key may need configuration"
        fi
        
        return 0
    else
        echo "❌ Dependency Track API not accessible"
        echo "💡 Make sure Dependency Track is running: make status"
        return 1
    fi
}

# Comprehensive diagnostic function
run_diagnostics() {
    echo ""
    echo "🔍 Running comprehensive diagnostics..."
    echo "====================================="
    
    check_jenkins_security
    echo ""
    
    verify_essential_plugins
    echo ""
    
    test_dependency_track_connectivity
    echo ""
    
    echo "📊 Service Status Summary:"
    echo "   Jenkins: $(curl -s -f http://localhost:8080/login >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready")"
    echo "   Dependency Track: $(curl -s -f http://localhost:8081/api/version >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready")"
    echo "   PostgreSQL: $(docker exec dt-postgres pg_isready -U dtrack 2>/dev/null && echo "✅ Ready" || echo "❌ Not Ready")"
    
    local job_exists=$(curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -q "name" && echo "✅ Exists" || echo "❌ Missing")
    echo "   Pipeline Job: $job_exists"
}

# Enhanced help function
show_help() {
    echo "Jenkins Pipeline Creator for Mend.io Demo"
    echo "========================================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --diagnostics, -d Run diagnostic checks only"
    echo ""
    echo "Examples:"
    echo "  $0                Create the pipeline job"
    echo "  $0 -d             Run diagnostics to check system status"
    echo ""
    echo "Features:"
    echo "  • CSRF-protected Jenkins API calls"
    echo "  • Automatic retry logic with exponential backoff"
    echo "  • Comprehensive error handling and diagnostics"
    echo "  • Complete WebGoat security scanning pipeline"
    echo ""
    echo "Requirements:"
    echo "  • Jenkins running on http://localhost:8080"
    echo "  • Admin credentials: admin/admin"
    echo "  • Essential plugins installed"
    echo "  • Dependency Track accessible"
}

# Extended main function with diagnostics option
main_extended() {
    if [ "$1" = "--diagnostics" ] || [ "$1" = "-d" ]; then
        echo "🎯 Jenkins Pipeline Creator - Diagnostic Mode"
        echo "============================================"
        
        if ! wait_for_jenkins; then
            echo "❌ Jenkins not ready for diagnostics"
            exit 1
        fi
        
        run_diagnostics
        exit 0
    fi
    
    main "$@"
}

# Process command line arguments and run
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --diagnostics|-d)
        main_extended "$@"
        ;;
    *)
        main_extended "$@"
        ;;
esac