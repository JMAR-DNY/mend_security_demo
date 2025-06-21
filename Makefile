.PHONY: help setup start stop restart logs clean demo health-check

help:
	@echo "Available commands:"
	@echo "  setup        - Initial setup and start all services"
	@echo "  start        - Start all services"
	@echo "  stop         - Stop all services"
	@echo "  restart      - Restart all services"
	@echo "  logs         - Show logs from all services"
	@echo "  clean        - Stop and remove all containers and volumes"
	@echo "  demo         - Run the security scan demo"
	@echo "  health-check - Check if all services are healthy"

setup:
	@echo "Setting up Mend Security Demo environment..."
	cp .env.example .env
	chmod +x scripts/*.sh
	./scripts/setup.sh

start:
	docker-compose up -d
	@echo "Services starting... Use 'make health-check' to verify"

stop:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f

clean:
	docker-compose down -v --remove-orphans
	docker system prune -f

demo:
	@echo "Running WebGoat security scan demo..."
	./scripts/reset-demo.sh
	@echo "Navigate to Jenkins at http://localhost:8080 and run the 'webgoat-security-scan' job"

health-check:
	./scripts/health-check.sh