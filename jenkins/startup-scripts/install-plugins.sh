#!/bin/bash
# This script runs at container startup to install plugins

JENKINS_HOME=/var/jenkins_home
PLUGIN_TXT=/usr/share/jenkins/ref/plugins.txt
PLUGIN_DIR=$JENKINS_HOME/plugins

# Check if plugins are already installed
if [ -f "$JENKINS_HOME/.plugins-installed" ]; then
    echo "Plugins already installed, skipping..."
    exit 0
fi

echo "Installing Jenkins plugins from $PLUGIN_TXT..."

# Create plugins directory if it doesn't exist
mkdir -p $PLUGIN_DIR

# Use jenkins-plugin-cli to install plugins
# This runs inside the container where network/SSL is more stable
if [ -f "$PLUGIN_TXT" ]; then
    # Try with default update center first
    jenkins-plugin-cli \
        --war /usr/share/jenkins/jenkins.war \
        --plugin-file $PLUGIN_TXT \
        --plugin-download-directory $PLUGIN_DIR \
        --verbose \
    || {
        echo "Default update center failed, trying stable update center..."
        jenkins-plugin-cli \
            --war /usr/share/jenkins/jenkins.war \
            --plugin-file $PLUGIN_TXT \
            --plugin-download-directory $PLUGIN_DIR \
            --jenkins-update-center "https://updates.jenkins.io/stable-2.426/update-center.json" \
            --verbose
    }
    
    # Mark plugins as installed
    touch $JENKINS_HOME/.plugins-installed
    echo "Plugin installation complete!"
else
    echo "No plugins.txt found at $PLUGIN_TXT"
fi