// 02-tools.groovy
#!groovy
import jenkins.model.*
import hudson.model.*
import hudson.tools.*

def instance = Jenkins.getInstance()

try {
    // Configure Git - use simple approach
    def gitTool = new hudson.plugins.git.GitTool("Default", "/usr/bin/git", [])
    def gitDescriptor = instance.getDescriptor("hudson.plugins.git.GitTool")
    if (gitDescriptor != null) {
        gitDescriptor.setInstallations(gitTool)
        gitDescriptor.save()
        println "Git tool configured successfully"
    }
} catch (Exception e) {
    println "Git tool configuration skipped: ${e.getMessage()}"
}

try {
    // Configure Maven
    def mavenInstallation = new hudson.tasks.Maven.MavenInstallation(
        "Maven-3.9.5",
        "/opt/maven",
        []
    )
    def mavenDescriptor = instance.getDescriptor("hudson.tasks.Maven")
    if (mavenDescriptor != null) {
        mavenDescriptor.setInstallations(mavenInstallation)
        mavenDescriptor.save()
        println "Maven configured successfully"
    }
} catch (Exception e) {
    println "Maven configuration skipped: ${e.getMessage()}"
}

// Skip Dependency Check tool configuration for now - it will be auto-installed
println "Tool configuration completed"