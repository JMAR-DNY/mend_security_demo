#!/bin/bash
set -e

# Simplified Dependency Track API Key Creator for Mend.io Demo
# This script opens the Dependency Track interface and guides the user through API key creation

DT_FRONTEND_URL="http://localhost:8082"
DT_API_URL="http://localhost:8081"
# Get the project root directory (parent of scripts folder)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

echo "🔑 Dependency Track API Key Setup"
echo "================================="
echo ""

# Check if Dependency Track is running
echo "🔍 Checking if Dependency Track is accessible..."
if ! curl -s -f "${DT_API_URL}/api/version" >/dev/null 2>&1; then
    echo "❌ Dependency Track is not accessible at ${DT_API_URL}"
    echo "💡 Please ensure your services are running: make start"
    exit 1
fi

echo "✅ Dependency Track is accessible"
echo ""

# Function to open browser
open_browser() {
    local url="$1"
    echo "🌐 Opening Dependency Track interface..."
    
    # For macOS
    if command -v open >/dev/null 2>&1; then
        open "$url"
    # For Linux with GUI
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url"
    # For Windows (WSL)
    elif command -v cmd.exe >/dev/null 2>&1; then
        cmd.exe /c start "$url"
    else
        echo "🔗 Please open this URL manually: $url"
    fi
}

# Function to test API key
test_api_key() {
    local api_key="$1"
    echo ""
    echo "🧪 Testing API key: ${api_key:0:12}..."
    
    # Test basic API access
    local version_test=$(curl -s -H "X-API-Key: $api_key" "${DT_API_URL}/api/version" 2>/dev/null || echo "")
    if [[ "$version_test" != *"version"* ]]; then
        echo "❌ API key failed basic version test"
        return 1
    fi
    
    # Test team access (requires proper permissions)
    local team_test=$(curl -s -H "X-API-Key: $api_key" "${DT_API_URL}/api/v1/team" 2>/dev/null || echo "")
    if [[ "$team_test" != *"uuid"* ]]; then
        echo "❌ API key lacks required permissions"
        return 1
    fi
    
    echo "✅ API key validation successful!"
    return 0
}

# Function to update .env file
update_env_file() {
    local api_key="$1"
    
    echo ""
    echo "💾 Updating .env file in project root: $ENV_FILE"
    
    # Only create backup if file exists and is not just the example
    if [ -f "$ENV_FILE" ]; then
        if ! grep -q "DT_API_KEY=TEST" "$ENV_FILE"; then
            cp "$ENV_FILE" "${ENV_FILE}.backup"
            echo "📋 Created backup: ${ENV_FILE}.backup"
        else
            echo "📋 Skipping backup (file contains example data)"
        fi
    fi
    
    # Update or add DT_API_KEY
    if [ -f "$ENV_FILE" ] && grep -q "^DT_API_KEY=" "$ENV_FILE"; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^DT_API_KEY=.*|DT_API_KEY=$api_key|" "$ENV_FILE"
        else
            # Linux
            sed -i "s|^DT_API_KEY=.*|DT_API_KEY=$api_key|" "$ENV_FILE"
        fi
        echo "✅ Updated existing DT_API_KEY in project .env file"
    else
        # Add new line
        echo "DT_API_KEY=$api_key" >> "$ENV_FILE"
        echo "✅ Added DT_API_KEY to project .env file"
    fi
}

# Main execution
main() {
    echo "📋 Simple 3-Step API Key Creation Process:"
    echo ""
    echo "1. 🌐 Open Dependency Track web interface"
    echo "2. 📝 Follow the guided steps to create an API key"
    echo "3. 🔑 Enter the API key for validation and storage"
    echo ""
    
    # Step 1: Open browser to login page
    echo "Step 1: Opening Dependency Track login page..."
    open_browser "${DT_FRONTEND_URL}/login"
    echo ""
    
    # Step 2: Provide clear instructions
    echo "📋 Follow these steps in the web interface:"
    echo ""
    echo "1. 🔐 Login with credentials:"
    echo "   Username: admin"
    echo "   Password: admin"
    echo ""
    echo "2. 🎯 Navigate to API Key Management:"
    echo "   URL: ${DT_FRONTEND_URL}/admin/accessManagement/teams"
    echo "   (or use the navigation: Administration → Access Management → Teams)"
    echo ""
    echo "3. 🔑 Create API Key:"
    echo "   • Click on a team (usually 'Administrators')"
    echo "   • Look for 'API Keys' section"
    echo "   • Click 'Create API Key' or '+' button"
    echo "   • Give it a name like: 'Jenkins Pipeline Key'"
    echo "   • Copy the generated API key"
    echo ""
    echo "💡 Important: The API key will only be shown once, so copy it immediately!"
    echo ""
    
    # Step 3: Get API key from user and validate
    local api_key=""
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "🔑 Please paste your API key here:"
        read -r api_key
        
        # Basic validation
        if [ -z "$api_key" ]; then
            echo "❌ API key cannot be empty"
            ((attempt++))
            continue
        fi
        
        if [ ${#api_key} -lt 20 ]; then
            echo "❌ API key seems too short (expected 20+ characters)"
            echo "💡 Make sure you copied the complete key"
            ((attempt++))
            continue
        fi
        
        # Test the API key
        if test_api_key "$api_key"; then
            echo ""
            echo "🎉 ✅ API KEY SETUP SUCCESSFUL! ✅"
            
            # Update .env file
            update_env_file "$api_key"
            
            echo ""
            echo "✅ Next Steps:"
            echo "1. Your API key has been saved to .env file"
            echo "2. Restart Jenkins to pick up the new API key: make restart"
            echo "3. Run your demo: make demo"
            echo ""
            return 0
        else
            echo ""
            echo "❌ API key validation failed"
            ((attempt++))
            
            if [ $attempt -le $max_attempts ]; then
                echo "💡 Please try again. Make sure the API key has the right permissions."
                echo "🔄 Attempt $attempt/$max_attempts"
                echo ""
            fi
        fi
    done
    
    echo ""
    echo "❌ Failed to validate API key after $max_attempts attempts"
    echo ""
    echo "🔧 Troubleshooting suggestions:"
    echo "1. Double-check you copied the complete API key"
    echo "2. Ensure you're creating the key from an admin team"
    echo "3. Try creating a new API key"
    echo "4. Verify Dependency Track is fully initialized"
    echo ""
    echo "💡 You can run this script again: ./scripts/create-api-key.sh"
    
    return 1
}

# Help function
show_help() {
    echo "Dependency Track API Key Creator"
    echo "==============================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "This script simplifies API key creation by:"
    echo "• Opening the Dependency Track web interface"
    echo "• Providing step-by-step instructions"
    echo "• Validating the API key"
    echo "• Automatically updating your .env configuration"
    echo ""
    echo "Requirements:"
    echo "• Dependency Track running at ${DT_FRONTEND_URL}"
    echo "• Admin access (admin/admin)"
    echo "• Web browser"
}

# Process command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac