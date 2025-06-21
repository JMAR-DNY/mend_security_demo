#!/bin/bash
set -e

echo "🚀 Setting up Mend Security Demo environment..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p jenkins/init.groovy.d jenkins/jobs workspace

# Start services
echo "🐳 Starting Docker services..."
docker-compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start (this may take a few minutes)..."
sleep 60

# Check service health
echo "🏥 Checking service health..."
./scripts/health-check.sh

echo "✅ Setup complete!"
echo ""
echo "🌐 Access your services:"
echo "   Jenkins: http://localhost:8080 (admin/admin)"
echo "   Dependency Track: http://localhost:8081 (admin/admin)"
echo "   Dependency Track Frontend: http://localhost:8082"
echo ""
echo "🎬 To run the demo: make demo"