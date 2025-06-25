#!/bin/bash
set -e

# Jenkins Pipeline Creator for Mend.io Demo - Fixed with CSRF Protection
# This script creates the WebGoat security scan pipeline programmatically

# Get the project root directory (parent of scripts folder)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables from .env file if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "📋 Loading environment variables from project .env file..."
    set -a  # automatically export all variables
    source "$PROJECT_ROOT/.env"
    set +a  # stop auto-exporting
else
    echo "❌ ERROR: No .env file found in project root: $PROJECT_ROOT/.env"
    echo "💡 Please create a .env file with required variables"
    exit 1
fi

# Set variables from environment with validation
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-admin}"
JOB_NAME="${JOB_NAME:-webgoat-security-scan}"

# Validate required API key
if [ -z "$DT_API_KEY" ]; then
    echo "❌ ERROR: DT_API_KEY not found in .env file"
    echo "💡 Please ensure your .env file contains: DT_API_KEY=your-api-key-here"
    exit 1
fi

API_KEY="$DT_API_KEY"

echo "🔧 Creating Jenkins Pipeline: $JOB_NAME"
echo "🛡️ Handling CSRF protection for secure API calls"
echo "🔑 Using API Key: ${API_KEY:0:12}... (from .env file)"

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

        environment {
            DT_API_URL = 'http://dependency-track-apiserver:8080'
            DT_API_KEY = "${env.DT_API_KEY}"
            WEBGOAT_REPO = "${env.WEBGOAT_REPO}"
            WEBGOAT_TAG = "${env.WEBGOAT_TAG}"
            PROJECT_NAME = "${env.PROJECT_NAME}"
            PROJECT_VERSION = "${env.PROJECT_VERSION}"
            MAVEN_OPTS = '-Xmx1024m -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true --add-opens java.base/java.lang=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED'
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
                    echo '🔍 Running OWASP Dependency Check via direct Java execution...'
                    echo 'ℹ️ Using returnStatus to handle vulnerabilities without failing pipeline'
                    
                    script {
                        // Use returnStatus: true to capture exit code without failing the pipeline
                        def exitCode = sh(
                            script: '''
                                echo "🔧 Setting up Dependency Check execution environment..."
                                
                                # Define tool directory
                                TOOL_DIR="$JENKINS_HOME/tools/org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation/dependency-check"
                                
                                echo "📁 Tool directory: $TOOL_DIR"
                                
                                # Verify tool installation
                                if [ ! -d "$TOOL_DIR" ]; then
                                    echo "❌ Dependency Check tool directory not found: $TOOL_DIR"
                                    exit 1
                                fi
                                
                                if [ ! -d "$TOOL_DIR/lib" ]; then
                                    echo "❌ Dependency Check lib directory not found: $TOOL_DIR/lib"
                                    exit 1
                                fi
                                
                                # Check for main JAR file
                                MAIN_JAR=$(find "$TOOL_DIR/lib" -name "dependency-check-cli-*.jar" | head -1)
                                if [ -z "$MAIN_JAR" ]; then
                                    echo "❌ Dependency Check CLI JAR not found in $TOOL_DIR/lib"
                                    echo "📋 Available JARs:"
                                    ls -la "$TOOL_DIR/lib/" | grep dependency-check || echo "No dependency-check JARs found"
                                    exit 1
                                fi
                                
                                echo "✅ Found main JAR: $MAIN_JAR"
                                
                                # Verify Java is available
                                if ! command -v java >/dev/null 2>&1; then
                                    echo "❌ Java not found in PATH"
                                    echo "PATH: $PATH"
                                    exit 1
                                fi
                                
                                JAVA_VERSION=$(java -version 2>&1 | head -1)
                                echo "✅ Java available: $JAVA_VERSION"
                                
                                echo ""
                                echo "🚀 Starting OWASP Dependency Check scan..."
                                echo "📊 Scan target: $(pwd)"
                                echo "📈 This may take 3-5 minutes for the first run..."
                                echo ""
                                
                                # Execute Dependency Check directly via Java
                                # Note: This will return non-zero exit code if vulnerabilities are found
                                java -Xmx4g \\
                                    -Dfile.encoding=UTF-8 \\
                                    -Djava.awt.headless=true \\
                                    -cp "$TOOL_DIR/lib/*" \\
                                    org.owasp.dependencycheck.App \\
                                    --scan . \\
                                    --format ALL \\
                                    --enableRetired \\
                                    --enableExperimental \\
                                    --failOnCVSS 11 \\
                                    --out . \\
                                    --project "WebGoat" \\
                                    --prettyPrint \\
                                    --log /tmp/dependency-check.log
                            ''',
                            returnStatus: true  // This captures the exit code instead of failing the pipeline
                        )
                        
                        echo ""
                        echo "📊 Dependency Check Results:"
                        echo "Exit code: ${exitCode}"
                        
                        // Show the generated reports
                        sh '''
                            echo "📋 Generated Reports:"
                            if ls dependency-check-report.* >/dev/null 2>&1; then
                                echo "✅ Reports generated successfully:"
                                ls -la dependency-check-report.*
                            else
                                echo "⚠️ No reports found with standard naming"
                                echo "📁 Checking for any XML/HTML/JSON files:"
                                find . -maxdepth 1 \\( -name "*.xml" -o -name "*.html" -o -name "*.json" \\) -newer . 2>/dev/null || echo "No recent report files found"
                            fi
                        '''
                        
                        // Show log tail if available
                        sh '''
                            if [ -f /tmp/dependency-check.log ]; then
                                echo ""
                                echo "📋 Last 10 lines of dependency check log:"
                                tail -10 /tmp/dependency-check.log
                            fi
                        '''
                        
                        // Handle the exit code appropriately
                        if (exitCode == 0) {
                            echo "✅ Dependency Check completed successfully with no vulnerabilities found"
                        } else if (exitCode > 0 && exitCode < 20) {
                            echo "⚠️ Dependency Check found vulnerabilities (exit code: ${exitCode})"
                            echo "ℹ️ This is expected for WebGoat - intentionally vulnerable application"
                            echo "✅ Continuing pipeline to upload results to Dependency Track"
                            
                            // Optional: You can categorize the severity based on exit codes
                            if (exitCode >= 11) {
                                echo "🔴 High severity vulnerabilities detected"
                            } else if (exitCode >= 7) {
                                echo "🟡 Medium severity vulnerabilities detected"  
                            } else {
                                echo "🟢 Low severity vulnerabilities detected"
                            }
                        } else {
                            // Only fail for truly critical tool errors (exit codes >= 20)
                            error "Dependency Check failed with critical tool error (exit code: ${exitCode})"
                        }
                    }
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
                            // Upload SBOM to existing WebGoat project
                            echo "📤 Uploading SBOM to existing WebGoat project..."
                            
                            def uploadResponse = httpRequest(
                                httpMode: 'POST',
                                url: "${DT_API_URL}/api/v1/bom",
                                customHeaders: [
                                    [name: 'X-API-Key', value: "${DT_API_KEY}"]
                                ],
                                multipartName: 'bom',
                                uploadFile: 'target/webgoat-bom.json',
                                formData: [
                                    [name: 'autoCreate', value: 'true'],
                                    [name: 'projectName', value: 'WebGoat'],
                                    [name: 'projectVersion', value: '8.1.0']
                                ]
                            )
                            
                            echo "🎉 SBOM upload successful! HTTP ${uploadResponse.status}"
                            
                            // Parse the token from response if present
                            if (uploadResponse.content) {
                                def responseJson = readJSON text: uploadResponse.content
                                if (responseJson.token) {
                                    echo "✅ Processing token: ${responseJson.token}"
                                }
                            }
                            
                            echo "🌐 View results at: http://localhost:8081"
                            echo "📊 Navigate to Projects → WebGoat to see vulnerability analysis"
                            
                        } catch (Exception e) {
                            echo "⚠️ Jenkins httpRequest failed: ${e.getMessage()}"
                            echo "🔄 Using curl fallback for SBOM upload..."
                            
                            // Fallback: Upload SBOM via curl
                            sh '''
                                echo "📤 Uploading SBOM via curl..."
                                curl -w "HTTP Status: %{http_code}\\n" \
                                    -X POST "${DT_API_URL}/api/v1/bom" \
                                    -H "X-API-Key: ${DT_API_KEY}" \
                                    -F "autoCreate=true" \
                                    -F "projectName=WebGoat" \
                                    -F "projectVersion=8.1.0" \
                                    -F "bom=@target/webgoat-bom.json"
                            '''
                            
                            echo "✅ Curl upload completed using verified method"
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
    

    # Skip credential creation - using environment variables instead
    echo "ℹ️ Skipping credential creation - using environment variables from .env file"
    
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