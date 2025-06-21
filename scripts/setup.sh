#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo with Standard Jenkins..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directory structure
echo "📁 Creating directory structure..."
mkdir -p jenkins/casc_configs
mkdir -p workspace
mkdir -p reports

# Create JCasC configuration if it doesn't exist
if [ ! -f "jenkins/casc_configs/jenkins.yaml" ]; then
    echo "📝 Creating Jenkins Configuration as Code setup..."
    cat > jenkins/casc_configs/jenkins.yaml << 'EOF'
jenkins:
  systemMessage: "Mend Security Demo - Jenkins with Auto-Configured Pipeline"
  numExecutors: 2
  scmCheckoutRetryCount: 3
  mode: NORMAL
  
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "admin"
          
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"

  remotingSecurity:
    enabled: true

tool:
  git:
    installations:
      - name: "Default"
        home: "/usr/bin/git"

credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "dt-api-key"
              description: "Dependency Track API Key"
              secret: "odt_0EvOUOJftaK9PHrVIh4yL1LgbAYHLhtJ"

unclassified:
  location:
    adminAddress: "admin@mend-demo.local"
    url: "http://localhost:8080/"
EOF
else
    echo "✅ JCasC configuration already exists"
fi

# Create minimal plugins list
if [ ! -f "jenkins/plugins.txt" ]; then
    echo "📦 Creating minimal plugins list..."
    cat > jenkins/plugins.txt << 'EOF'
# Essential plugins for the demo
workflow-aggregator
git
configuration-as-code
http_request
pipeline-utility-steps
credentials
credentials-binding
timestamper
EOF
else
    echo "✅ Jenkins plugins list already exists"
fi

# Remove Dockerfile.jenkins if it exists
if [ -f "Dockerfile.jenkins" ]; then
    echo "🧹 Removing custom Dockerfile (no longer needed)..."
    rm Dockerfile.jenkins
fi

# Start services (no build required)
echo "🐳 Starting Docker services with standard Jenkins image..."
echo "   (Much faster - no custom image build required!)"
docker-compose up -d

# Function to check service health
check_service() {
    local service_name=$1
    local port=$2
    local max_attempts=20
    local attempt=1
    
    echo "⏳ Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:$port >/dev/null 2>&1; then
            echo "✅ $service_name is ready and responding"
            return 0
        fi
        echo "   Attempt $attempt/$max_attempts - $service_name not ready yet..."
        sleep 10
        ((attempt++))
    done
    
    echo "❌ $service_name failed to start within timeout"
    return 1
}

# Wait for services to start (much faster now)
echo "🔄 Waiting for services to initialize..."
echo "   This should take 3-5 minutes..."

# Wait for PostgreSQL
echo "🗄️ Waiting for PostgreSQL database..."
sleep 10
docker exec dt-postgres pg_isready -U dtrack || echo "PostgreSQL still starting..."

# Wait for Dependency Track API
echo "🛡️ Waiting for Dependency Track API server..."
check_service "Dependency Track API" 8081

# Wait for Jenkins
echo "🔧 Waiting for Jenkins..."
check_service "Jenkins" 8080

# Give Jenkins time to process JCasC
echo "⚙️ Allowing time for Jenkins Configuration as Code to load..."
sleep 30

# Get Dependency Track information
echo "🔑 Checking Dependency Track setup..."
DT_VERSION=$(curl -s http://localhost:8081/api/version 2>/dev/null || echo "API not ready")
if [[ $DT_VERSION == *"version"* ]]; then
    echo "✅ Dependency Track API is accessible"
    echo "   Default API key is pre-configured for demo purposes"
else
    echo "⚠️ Dependency Track API still initializing"
fi

# Final verification
echo ""
echo "🎯 Performing final system verification..."

# Check all containers are running
echo "📊 Container Status:"
docker-compose ps

echo ""
echo "✅ 🎉 SETUP COMPLETE! 🎉"
echo ""
echo "🌐 Access Your Demo Environment:"
echo "   • Jenkins:           http://localhost:8080 (admin/admin)"
echo "   • Dependency Track:  http://localhost:8081 (admin/admin)"
echo "   • DT Frontend:       http://localhost:8082"
echo ""
echo "📝 Next Steps to Complete Setup:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Login with admin/admin"
echo "   3. Go to 'Manage Jenkins' → 'Manage Plugins'"
echo "   4. Install these plugins:"
echo "      • Pipeline: Workflow Aggregator"
echo "      • Git"
echo "      • HTTP Request Plugin"
echo "      • Pipeline Utility Steps"
echo "      • Configuration as Code"
echo "   5. After plugins install, Jenkins will restart automatically"
echo "   6. Create your pipeline job manually or via JCasC"
echo ""
echo "🎬 Advantages of This Approach:"
echo "   ✓ No custom Docker build required (much faster setup)"
echo "   ✓ No SSL certificate issues during build"
echo "   ✓ Standard Jenkins image (more reliable)"
echo "   ✓ Plugins installed through UI (shows Jenkins expertise)"
echo "   ✓ JCasC still handles configuration"
echo ""
echo "⏱️  Total setup time: ~5 minutes (vs 20+ with custom build)"