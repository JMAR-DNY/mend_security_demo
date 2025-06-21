#!/bin/bash
set -e

echo "🔄 Resetting demo environment..."

# Function to check if service is responding
check_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:$port >/dev/null 2>&1; then
            echo "✅ $service_name is ready"
            return 0
        fi
        echo "⏳ Waiting for $service_name... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    echo "❌ $service_name failed to start within timeout"
    return 1
}

# Stop existing containers
echo "🛑 Stopping existing containers..."
docker-compose down

# Clean up old data (optional - comment out to preserve data)
echo "🧹 Cleaning up old demo data..."
docker volume rm mend-security-demo_dt-data 2>/dev/null || echo "No dt-data volume to remove"
docker volume rm mend-security-demo_postgres-data 2>/dev/null || echo "No postgres-data volume to remove"

# Start services
echo "🚀 Starting fresh demo environment..."
docker-compose up -d

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to initialize..."
check_service "PostgreSQL" 5432

# Wait for Dependency Track API to be ready
echo "⏳ Waiting for Dependency Track API to initialize (this may take several minutes)..."
check_service "Dependency Track API" 8081

# Wait for Jenkins to be ready
echo "⏳ Waiting for Jenkins to initialize..."
check_service "Jenkins" 8080

# Get Dependency Track API key
echo "🔑 Retrieving Dependency Track API key..."
sleep 30  # Give DT time to fully initialize

# Attempt to get API key
DT_API_KEY=""
for i in {1..10}; do
    echo "Attempt $i to get API key..."
    API_RESPONSE=$(curl -s -X GET \
        -H "Content-Type: application/json" \
        -u "admin:admin" \
        http://localhost:8081/api/v1/user/admin 2>/dev/null || echo "")
    
    if [[ $API_RESPONSE == *"apiKey"* ]]; then
        DT_API_KEY=$(echo $API_RESPONSE | grep -o '"apiKey":"[^"]*' | cut -d'"' -f4)
        break
    fi
    
    echo "API not ready yet, waiting..."
    sleep 15
done

if [ -n "$DT_API_KEY" ]; then
    echo "✅ Retrieved API key: ${DT_API_KEY:0:10}..."
    
    # Update Jenkins credential with real API key
    echo "🔧 Updating Jenkins credentials with Dependency Track API key..."
    
    # This would typically be done through Jenkins API or configuration
    echo "Manual step: Update Jenkins credential 'dt-api-key' with value: $DT_API_KEY"
else
    echo "⚠️  Could not retrieve API key automatically"
    echo "Manual step required:"
    echo "1. Go to http://localhost:8081"
    echo "2. Login with admin/admin"
    echo "3. Go to Administration -> Access Management -> Teams"
    echo "4. Click on 'Administrators' team"
    echo "5. Copy the API key"
    echo "6. Go to Jenkins at http://localhost:8080"
    echo "7. Go to Manage Jenkins -> Credentials"
    echo "8. Update the 'dt-api-key' credential with the copied API key"
fi

echo ""
echo "🎉 Demo environment reset complete!"
echo ""
echo "🌐 Access your services:"
echo "   Jenkins: http://localhost:8080 (admin/admin)"
echo "   Dependency Track: http://localhost:8081 (admin/admin)"
echo "   Dependency Track Frontend: http://localhost:8082"
echo ""
echo "🎬 To run the security scan:"
echo "   1. Go to Jenkins: http://localhost:8080"
echo "   2. Click on 'webgoat-security-scan' job"
echo "   3. Click 'Build Now'"
echo ""
echo "📊 After the scan completes:"
echo "   Check Dependency Track at http://localhost:8081 for vulnerability analysis"