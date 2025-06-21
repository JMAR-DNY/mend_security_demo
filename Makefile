.PHONY: help setup start stop restart logs clean demo health-check status verify-plugins

help:
	@echo "🔧 Mend Security Demo - Available Commands:"
	@echo ""
	@echo "  setup        - Complete setup with runtime plugin installation (7-10 min)"
	@echo "  start        - Start all services"
	@echo "  stop         - Stop all services"
	@echo "  restart      - Restart all services"
	@echo "  logs         - Show logs from all services"
	@echo "  clean        - Stop and remove all containers and volumes"
	@echo "  demo         - Instructions for running the security scan demo"
	@echo "  health-check - Check if all services are healthy"
	@echo "  status       - Show current status of all services"
	@echo "  verify-plugins - Check if Jenkins plugins are installed"
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  1. make setup    (installs plugins at runtime, creates pipeline job)"
	@echo "  2. make demo     (run the demonstration)"
	@echo ""
	@echo "📋 Setup Notes:"
	@echo "  • Runtime plugin installation: ~3-5 minutes"
	@echo "  • Service initialization: ~4-5 minutes"
	@echo "  • Total time: 7-10 minutes (much faster than custom builds)"
	@echo "  • Pipeline job auto-created via JCasC"
	@echo ""

setup:
	@echo "🚀 Setting up Mend Security Demo with runtime plugin installation..."
	@echo "⏰ This will take 7-10 minutes (installs plugins at runtime)"
	@echo "⚡ Much faster than custom Docker builds!"
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

logs:
	@echo "📋 Showing logs from all services (Ctrl+C to exit)..."
	docker-compose logs -f

clean:
	@echo "🧹 Cleaning up all containers, volumes, and data..."
	@echo "⚠️  This will remove all demo data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $REPLY =~ ^[Yy]$ ]]; then \
		docker-compose down -v --remove-orphans; \
		docker system prune -f; \
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
	@echo "   3. Find 'webgoat-security-scan' pipeline job (auto-created)"
	@echo "   4. Click 'Build Now' to start the security scan"
	@echo "   5. Watch the pipeline execute in real-time"
	@echo "   6. Review results in Dependency Track: http://localhost:8081"
	@echo ""
	@echo "📋 Pipeline Stages (Demo talking points):"
	@echo "   Stage 1: 🔄 Checkout - Clone WebGoat v8.1.0 from GitHub"
	@echo "   Stage 2: 🔨 Build - Compile with Maven + CycloneDX plugin injection"
	@echo "   Stage 3: 🔍 Dependency Scan - OWASP vulnerability scanning"
	@echo "   Stage 4: 📋 Generate SBOM - Create Software Bill of Materials"
	@echo "   Stage 5: ⬆️ Upload to DT - Send to Dependency Track via API"
	@echo ""
	@echo "💡 Key Value Propositions to Highlight:"
	@echo "   ✓ Fully automated security scanning in CI/CD pipeline"
	@echo "   ✓ Complete software supply chain visibility (SBOM)"
	@echo "   ✓ Centralized vulnerability management with Dependency Track"
	@echo "   ✓ Industry-standard SBOM generation (CycloneDX format)"
	@echo "   ✓ Continuous monitoring and risk assessment"
	@echo "   ✓ Infrastructure as Code (Jenkins configured via JCasC)"
	@echo "   ✓ Runtime plugin installation (no custom Docker builds)"
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
	@echo "   • Jenkins Configuration as Code (JCasC)"
	@echo "   • Runtime plugin installation strategy"
	@echo "   • Automated container orchestration"
	@echo "   • Production-ready security scanning workflow"
	@echo "   • Professional DevOps practices"
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
	@echo "   • Verify plugins: make verify-plugins"

verify-plugins:
	@echo "🔌 Checking Jenkins plugin installation..."
	@echo ""
	@echo "Essential plugins for Mend demo:"
	@docker exec jenkins /bin/bash -c "
		if [ -f /var/jenkins_home/plugins/workflow-aggregator.jpi ]; then
			echo '✅ Pipeline (workflow-aggregator)'
		else
			echo '❌ Pipeline (workflow-aggregator) - MISSING'
		fi
		
		if [ -f /var/jenkins_home/plugins/dependency-check-jenkins-plugin.jpi ]; then
			echo '✅ OWASP Dependency Check'
		else
			echo '❌ OWASP Dependency Check - MISSING'
		fi
		
		if [ -f /var/jenkins_home/plugins/http_request.jpi ]; then
			echo '✅ HTTP Request'
		else
			echo '❌ HTTP Request - MISSING'
		fi
		
		if [ -f /var/jenkins_home/plugins/configuration-as-code.jpi ]; then
			echo '✅ Configuration as Code'
		else
			echo '❌ Configuration as Code - MISSING'
		fi
		
		if [ -f /var/jenkins_home/plugins/job-dsl.jpi ]; then
			echo '✅ Job DSL'
		else
			echo '❌ Job DSL - MISSING'
		fi
		
		if [ -f /var/jenkins_home/plugins/maven-plugin.jpi ]; then
			echo '✅ Maven Integration'
		else
			echo '❌ Maven Integration - MISSING'
		fi
		
		if [ -f /var/jenkins_home/plugins/git.jpi ]; then
			echo '✅ Git'
		else
			echo '❌ Git - MISSING'
		fi
	" 2>/dev/null || echo "❌ Could not check plugins (Jenkins may not be running)"
	@echo ""
	@echo "💡 If plugins are missing:"
	@echo "   • Run: make restart"
	@echo "   • Wait for full initialization"
	@echo "   • Check: make logs