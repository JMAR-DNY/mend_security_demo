.PHONY: help setup start stop restart logs clean demo health-check status rebuild

help:
	@echo "🔧 Mend Security Demo - Available Commands:"
	@echo ""
	@echo "  setup        - Complete setup with custom Jenkins image (first time: 15-20 min)"
	@echo "  start        - Start all services"
	@echo "  stop         - Stop all services"
	@echo "  restart      - Restart all services"
	@echo "  rebuild      - Rebuild Jenkins image and restart services"
	@echo "  logs         - Show logs from all services"
	@echo "  clean        - Stop and remove all containers and volumes"
	@echo "  demo         - Instructions for running the security scan demo"
	@echo "  health-check - Check if all services are healthy"
	@echo "  status       - Show current status of all services"
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  1. make setup    (builds custom Jenkins image with plugins & jobs)"
	@echo "  2. make demo     (run the demonstration)"
	@echo ""
	@echo "📋 First-time Setup Notes:"
	@echo "  • Custom Jenkins image build: ~5-10 minutes"
	@echo "  • Service initialization: ~5-10 minutes"
	@echo "  • Total time: 15-20 minutes on first run"
	@echo "  • Subsequent starts: ~2-3 minutes"
	@echo ""

setup:
	@echo "🚀 Setting up Mend Security Demo with custom Jenkins image..."
	@echo "⏰ This will take 15-20 minutes on first run (builds custom Jenkins image)"
	@echo "⚡ Subsequent runs will be much faster (2-3 minutes)"
	cp .env.example .env 2>/dev/null || echo "Using existing .env"
	chmod +x scripts/*.sh 2>/dev/null || echo "Scripts already executable"
	./scripts/setup.sh

start:
	@echo "🐳 Starting all services..."
	docker-compose up -d
	@echo "✅ Services starting... Use 'make health-check' to verify readiness"

stop:
	@echo "🛑 Stopping all services..."
	docker-compose down

restart:
	@echo "🔄 Restarting all services..."
	docker-compose restart
	@echo "✅ Services restarted"

rebuild:
	@echo "🏗️ Rebuilding Jenkins image and restarting services..."
	docker-compose down
	docker-compose up -d --build
	@echo "✅ Jenkins image rebuilt and services restarted"

logs:
	@echo "📋 Showing logs from all services (Ctrl+C to exit)..."
	docker-compose logs -f

clean:
	@echo "🧹 Cleaning up all containers, volumes, and data..."
	@echo "⚠️  This will remove all demo data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker-compose down -v --remove-orphans; \
		docker system prune -f; \
		docker rmi mend-security-demo-clone_jenkins 2>/dev/null || echo "Custom Jenkins image already removed"; \
		echo "✅ Cleanup complete"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

demo:
	@echo ""
	@echo "🎬 🎯 MEND SECURITY DEMO - EXECUTION GUIDE 🎯 🎬"
	@echo ""
	@echo "🌐 Access Points:"
	@echo "   • Jenkins:          http://localhost:8080 (admin/admin)"
	@echo "   • Dependency Track: http://localhost:8081 (admin/admin)"
	@echo "   • DT Frontend:      http://localhost:8082"
	@echo ""
	@echo "🚀 Demo Execution Steps:"
	@echo "   1. Open Jenkins: http://localhost:8080"
	@echo "   2. Login with admin/admin"
	@echo "   3. Find 'webgoat-security-scan' pipeline job"
	@echo "   4. Click 'Build Now' to start the security scan"
	@echo "   5. Watch the pipeline execute in real-time"
	@echo "   6. Review results in Dependency Track: http://localhost:8081"
	@echo ""
	@echo "📋 Pipeline Stages (Demo talking points):"
	@echo "   Stage 1: 🔄 Checkout - Clone WebGoat v8.1.0 from GitHub"
	@echo "   Stage 2: 🔨 Build - Compile with Maven"
	@echo "   Stage 3: 🔍 Dependency Scan - OWASP vulnerability scanning"
	@echo "   Stage 4: 📋 Generate SBOM - Create Software Bill of Materials"
	@echo "   Stage 5: ⬆️ Upload to DT - Send to Dependency Track for management"
	@echo ""
	@echo "💡 Key Value Propositions to Highlight:"
	@echo "   ✓ Automated security scanning in CI/CD pipeline"
	@echo "   ✓ Complete software supply chain visibility"
	@echo "   ✓ Centralized vulnerability management with Dependency Track"
	@echo "   ✓ Industry-standard SBOM generation (CycloneDX format)"
	@echo "   ✓ Continuous monitoring and risk assessment"
	@echo "   ✓ Infrastructure as Code (Jenkins configs version-controlled)"
	@echo ""
	@echo "🎯 Expected Demo Outcomes:"
	@echo "   • WebGoat vulnerabilities detected and cataloged"
	@echo "   • SBOM generated showing all dependencies"
	@echo "   • Security data centralized in Dependency Track"
	@echo "   • Executive dashboards and reporting available"
	@echo ""
	@echo "⏱️  Demo Runtime: ~3-5 minutes for full pipeline execution"
	@echo ""
	@echo "🏆 Technical Excellence Demonstrated:"
	@echo "   • Custom Jenkins image with pre-installed plugins"
	@echo "   • Jenkins Configuration as Code (JCasC)"
	@echo "   • Automated container orchestration"
	@echo "   • Production-ready security scanning workflow"
	@echo ""

health-check:
	@echo "🏥 Checking service health..."
	./scripts/health-check.sh

status:
	@echo "📊 Current Service Status:"
	@echo ""
	@docker-compose ps
	@echo ""
	@echo "🔍 Detailed Health Checks:"
	@echo -n "   PostgreSQL: "
	@docker exec dt-postgres pg_isready -U dtrack 2>/dev/null && echo "✅ Ready" || echo "❌ Not Ready"
	@echo -n "   Jenkins: "
	@curl -s -f http://localhost:8080/login >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready"
	@echo -n "   Dependency Track: "
	@curl -s -f http://localhost:8081/api/version >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Not Ready"
	@echo -n "   Jenkins Job: "
	@curl -s -u admin:admin http://localhost:8080/job/webgoat-security-scan/api/json 2>/dev/null | grep -q "name" && echo "✅ Created" || echo "⚠️ Pending/Missing"
	@echo ""
	@echo "🌐 Service URLs:"
	@echo "   Jenkins:          http://localhost:8080"
	@echo "   Dependency Track: http://localhost:8081"
	@echo "   DT Frontend:      http://localhost:8082"
	@echo ""
	@echo "🔧 If services aren't ready:"
	@echo "   • Wait a few more minutes for initialization"
	@echo "   • Check logs: make logs"
	@echo "   • Restart services: make restart"