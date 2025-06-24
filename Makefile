.PHONY: help setup start stop restart logs clean demo health-check status verify-plugins check-db check-cert check-fuzzy check-feeds check-api check-pipeline monitor debug-all

help:
	@echo "🔧 Mend Security Demo - Available Commands:"
	@echo ""
	@echo "🚀 Core Commands:"
	@echo "  setup        - Complete setup with runtime plugin installation (7-10 min)"
	@echo "  start        - Start all services"
	@echo "  stop         - Stop all services"
	@echo "  restart      - Restart all services"
	@echo "  logs         - Show logs from all services"
	@echo "  clean        - Stop and remove all containers and volumes"
	@echo "  demo         - Instructions for running the security scan demo"
	@echo ""
	@echo "🔍 Diagnostics & Monitoring:"
	@echo "  health-check - Check if all services are healthy"
	@echo "  status       - Show current status of all services"
	@echo "  verify-plugins - Check if Jenkins plugins are installed"
	@echo "  check-db     - Show Dependency Track database size and stats"
	@echo "  check-cert   - Monitor certificate and download issues"
	@echo "  check-fuzzy  - Verify fuzzy analyzer settings"
	@echo "  check-feeds  - Check vulnerability feed download status"
	@echo "  check-api    - Test Dependency Track API connectivity"
	@echo "  check-pipeline - Verify Jenkins pipeline job status"
	@echo "  monitor      - Real-time monitoring dashboard"
	@echo "  debug-all    - Run comprehensive diagnostics"
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
	@echo "🚀 Setting up Mend Security Demo with pre-built Jenkins image..."
	@echo "⏰ This will take 5-8 minutes (builds custom Jenkins image with plugins)"
	@echo "🔧 Building Jenkins with pre-installed plugins for reliability"
	[ ! -f .env ] && cp .env.example .env || echo "Using existing .env"
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

restart-env:
	@echo "🔄 Restarting services with fresh environment variables..."
	@echo "💡 This fixes issues where Jenkins doesn't pick up .env changes"
	@echo ""
	@echo "📋 Current API key status:"
	@grep "^DT_API_KEY=" .env 2>/dev/null | sed 's/DT_API_KEY=.*/DT_API_KEY=***[REDACTED]***/' || echo "❌ No DT_API_KEY found in .env"
	@echo ""
	@echo "🛑 Stopping containers for clean restart..."
	docker-compose down
	@echo "🚀 Starting with fresh environment..."
	docker-compose up -d
	@echo "⏳ Waiting for services to initialize..."
	@sleep 30
	@echo "🔍 Verifying Jenkins has the API key..."
	@docker exec jenkins printenv DT_API_KEY | head -c 20 2>/dev/null && echo "..." || echo "❌ DT_API_KEY not found in Jenkins container"
	@echo "✅ Environment restart complete!"

logs:
	@echo "📋 Showing logs from all services (Ctrl+C to exit)..."
	docker-compose logs -f

clean:
	@echo "🧹 Cleaning up all containers, volumes, and data..."
	@echo "⚠️  This will remove all demo data!"
	@echo "Are you sure? [y/N] "; \
	read answer; \
	if [ "$$answer" = "y" ] || [ "$$answer" = "Y" ]; then \
		echo "🗑️ Removing containers and volumes..."; \
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
	@docker exec jenkins /bin/bash -c " \
		if [ -f /var/jenkins_home/plugins/workflow-aggregator.jpi ]; then \
			echo '✅ Pipeline (workflow-aggregator)'; \
		else \
			echo '❌ Pipeline (workflow-aggregator) - MISSING'; \
		fi; \
		if [ -f /var/jenkins_home/plugins/dependency-check-jenkins-plugin.jpi ]; then \
			echo '✅ OWASP Dependency Check'; \
		else \
			echo '❌ OWASP Dependency Check - MISSING'; \
		fi; \
		if [ -f /var/jenkins_home/plugins/http_request.jpi ]; then \
			echo '✅ HTTP Request'; \
		else \
			echo '❌ HTTP Request - MISSING'; \
		fi; \
		if [ -f /var/jenkins_home/plugins/configuration-as-code.jpi ]; then \
			echo '✅ Configuration as Code'; \
		else \
			echo '❌ Configuration as Code - MISSING'; \
		fi; \
		if [ -f /var/jenkins_home/plugins/job-dsl.jpi ]; then \
			echo '✅ Job DSL'; \
		else \
			echo '❌ Job DSL - MISSING'; \
		fi; \
		if [ -f /var/jenkins_home/plugins/maven-plugin.jpi ]; then \
			echo '✅ Maven Integration'; \
		else \
			echo '❌ Maven Integration - MISSING'; \
		fi; \
		if [ -f /var/jenkins_home/plugins/git.jpi ]; then \
			echo '✅ Git'; \
		else \
			echo '❌ Git - MISSING'; \
		fi \
	" 2>/dev/null || echo "❌ Could not check plugins (Jenkins may not be running)"
	@echo ""
	@echo "💡 If plugins are missing:"
	@echo "   • Run: make restart"
	@echo "   • Wait for full initialization"
	@echo "   • Check: make logs"

check-db:
	@echo "🗄️ Dependency Track Database Status:"
	@echo ""
	@echo "📊 Database Size:"
	@docker exec dt-postgres psql -U dtrack -d dtrack -c "SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;" 2>/dev/null || echo "❌ Could not connect to database"
	@echo ""
	@echo "📋 Table Statistics:"
	@docker exec dt-postgres psql -U dtrack -d dtrack -c "\
		SELECT \
			schemaname, \
			tablename, \
			pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size, \
			pg_total_relation_size(schemaname||'.'||tablename) as bytes \
		FROM pg_tables \
		WHERE schemaname = 'public' \
		ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC \
		LIMIT 10;" 2>/dev/null || echo "❌ Could not get table statistics"
	@echo ""
	@echo "💡 Database Health Indicators:"
	@echo "   • Healthy size: 200MB+ (indicates vulnerability feeds downloaded)"
	@echo "   • Problem size: Repeated calls same size means feed is stuck"
	@echo "   • Fresh install: <20MB (feeds not yet started)"

check-cert:
	@echo "🔐 Certificate and Download Status Monitor:"
	@echo "💡 Press Ctrl+C to exit monitoring"
	@echo ""
	@docker logs dt-apiserver --since 10m 2>&1 | grep -E "(download|error|failed|certificate|PKIX)" | tail -20 || echo "❌ No certificate/download logs found"
	@echo ""
	@echo "🔍 Real-time monitoring (last 50 lines, updates every 5 seconds):"
	@docker logs -f dt-apiserver | grep -E "(download|error|failed|certificate|PKIX|SSL)"

check-fuzzy:
	@echo "🔍 Fuzzy Analyzer Configuration Status:"
	@echo ""
	@echo "📋 Environment Variables in Container:"
	@docker exec dt-apiserver printenv | grep -E "(FUZZY|ANALYZER)" | sort || echo "❌ No fuzzy analyzer environment variables found"
	@echo ""
	@echo "🔧 API Configuration Status:"
	@API_KEY=$$(grep "^DT_API_KEY=" .env 2>/dev/null | cut -d'=' -f2); \
	if [ -n "$$API_KEY" ]; then \
		echo "Using API key: $${API_KEY:0:12}..."; \
		curl -s -H "X-API-Key: $$API_KEY" "http://localhost:8081/api/v1/configProperty" | \
		jq -r '.[] | select(.propertyName | contains("analyzer")) | select(.propertyName | contains("fuzzy")) | "🎯 \(.propertyName): \(.propertyValue)"' 2>/dev/null || \
		echo "❌ Could not retrieve fuzzy analyzer settings via API"; \
	else \
		echo "❌ No API key found in .env file"; \
	fi
	@echo ""
	@echo "💡 To enable fuzzy analyzers if disabled:"
	@echo "   • Run: ./scripts/force-fuzzy-analyzers.sh (if available)"
	@echo "   • Or manually enable in Dependency Track UI"

check-feeds:
	@echo "📥 Vulnerability Feed Download Status:"
	@echo ""
	@echo "🔍 Recent Feed Activity (last 30 minutes):"
	@docker logs dt-apiserver --since 30m 2>&1 | grep -E "(feed|download|vulnerability|NVD|OSV)" | tail -10 || echo "❌ No recent feed activity found"
	@echo ""
	@echo "📊 Feed Download Indicators:"
	@echo "   ✅ Good: 'Successfully downloaded' or 'Processing feeds'"
	@echo "   ⚠️  Issue: 'PKIX path building failed' or 'SSL handshake'"
	@echo "   ❌ Problem: 'Connection refused' or 'timeout'"
	@echo ""
	@echo "🗄️ Database size (feed download indicator):"
	@docker exec dt-postgres psql -U dtrack -d dtrack -c "SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;" 2>/dev/null || echo "❌ Could not check database size"

check-api:
	@echo "🔗 Dependency Track API Connectivity Test:"
	@echo ""
	@echo "🔍 Basic API Health:"
	@curl -s -w "HTTP Status: %{http_code}\nResponse Time: %{time_total}s\n" \
		http://localhost:8081/api/version 2>/dev/null || echo "❌ API not accessible"
	@echo ""
	@echo "🔑 API Key Test:"
	@API_KEY=$$(grep "^DT_API_KEY=" .env 2>/dev/null | cut -d'=' -f2); \
	if [ -n "$$API_KEY" ]; then \
		echo "Testing API key: $${API_KEY:0:12}..."; \
		RESPONSE=$$(curl -s -w "%{http_code}" -H "X-API-Key: $$API_KEY" \
			"http://localhost:8081/api/v1/project" -o /tmp/api-test.json); \
		if [ "$$RESPONSE" = "200" ]; then \
			echo "✅ API key valid"; \
			PROJECT_COUNT=$$(jq length /tmp/api-test.json 2>/dev/null || echo "unknown"); \
			echo "📋 Projects in Dependency Track: $$PROJECT_COUNT"; \
		else \
			echo "❌ API key invalid (HTTP $$RESPONSE)"; \
		fi; \
		rm -f /tmp/api-test.json; \
	else \
		echo "❌ No API key found in .env file"; \
	fi

check-pipeline:
	@echo "🚀 Jenkins Pipeline Job Status:"
	@echo ""
	@echo "🔍 Job Existence Check:"
	@JOB_STATUS=$$(curl -s -u admin:admin "http://localhost:8080/job/webgoat-security-scan/api/json" 2>/dev/null); \
	if echo "$$JOB_STATUS" | grep -q '"name"'; then \
		echo "✅ Pipeline job 'webgoat-security-scan' exists"; \
		LAST_BUILD=$$(echo "$$JOB_STATUS" | jq -r '.lastBuild.number // "never"' 2>/dev/null); \
		echo "📋 Last build number: $$LAST_BUILD"; \
		if [ "$$LAST_BUILD" != "never" ] && [ "$$LAST_BUILD" != "null" ]; then \
			BUILD_STATUS=$$(echo "$$JOB_STATUS" | jq -r '.lastBuild.result // "RUNNING"' 2>/dev/null); \
			echo "📊 Last build result: $$BUILD_STATUS"; \
		fi; \
	else \
		echo "❌ Pipeline job 'webgoat-security-scan' not found"; \
		echo "💡 Create it with: ./scripts/create-pipeline.sh"; \
	fi
	@echo ""
	@echo "🔑 Jenkins API Access:"
	@curl -s -u admin:admin "http://localhost:8080/api/json" >/dev/null 2>&1 && \
		echo "✅ Jenkins API accessible with admin credentials" || \
		echo "❌ Cannot access Jenkins API"

monitor:
	@echo "📊 Real-Time Dependency Track Monitoring Dashboard"
	@echo "💡 Press Ctrl+C to exit"
	@echo ""
	@while true; do \
		clear; \
		echo "🕐 $$(date)"; \
		echo ""; \
		echo "📊 Service Status:"; \
		docker-compose ps --format "table {{.Name}}\t{{.Status}}" | head -4; \
		echo ""; \
		echo "🗄️ Database Size:"; \
		docker exec dt-postgres psql -U dtrack -d dtrack -c "SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;" 2>/dev/null | grep -v "db_size" | grep -v "^-" || echo "❌ DB Error"; \
		echo ""; \
		echo "🔐 Recent Activity (last 5 minutes):"; \
		docker logs dt-apiserver --since 5m 2>&1 | grep -E "(download|error|failed|SUCCESS)" | tail -3 || echo "No recent activity"; \
		echo ""; \
		echo "🔄 Refreshing in 10 seconds..."; \
		sleep 10; \
	done

debug-all:
	@echo "🔬 Comprehensive System Diagnostics"
	@echo "======================================"
	@echo ""
	@echo "🐳 Docker Status:"
	@docker-compose ps
	@echo ""
	@echo "🗄️ Database Status:"
	@make check-db
	@echo ""
	@echo "🔐 Certificate Status:"
	@docker logs dt-apiserver --since 10m 2>&1 | grep -E "(certificate|PKIX|SSL)" | tail -5 || echo "No certificate issues found"
	@echo ""
	@echo "🔍 Fuzzy Analyzer Status:"
	@make check-fuzzy
	@echo ""
	@echo "🔗 API Connectivity:"
	@make check-api
	@echo ""
	@echo "🚀 Pipeline Status:"
	@make check-pipeline
	@echo ""
	@echo "💾 Disk Usage:"
	@docker system df
	@echo ""
	@echo "🔧 Quick Fixes:"
	@echo "   • Database stuck at 65MB: make restart (fixes certificate issues)"
	@echo "   • Missing plugins: make verify-plugins"
	@echo "   • API issues: Check .env file and make restart-env"
	@echo "   • Pipeline missing: ./scripts/create-pipeline.sh"