#!/bin/bash

echo "🏥 Checking service health..."

services=("jenkins:8080" "dependency-track-apiserver:8081")
all_healthy=true

for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    if curl -f http://localhost:$port >/dev/null 2>&1; then
        echo "✅ $name is healthy"
    else
        echo "❌ $name is not responding"
        all_healthy=false
    fi
done

if $all_healthy; then
    echo "🎉 All services are healthy!"
    exit 0
else
    echo "⚠️  Some services are not healthy. Check logs with: make logs"
    exit 1
fi