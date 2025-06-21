#!groovy
import jenkins.model.*
import hudson.model.*
import hudson.tools.*
import hudson.plugins.git.*
import hudson.tasks.Maven

def instance = Jenkins.getInstance()

// Configure Git
def gitInstallation = new GitTool("Default", "/usr/bin/git", [])
def gitDescriptor = instance.getDescriptor("hudson.plugins.git.GitTool")
gitDescriptor.setInstallations(gitInstallation)
gitDescriptor.save()

// Configure Maven
def mavenInstallation = new Maven.MavenInstallation(
    "Maven-3.9.5",
    "/opt/maven",
    []
)
def mavenDescriptor = instance.getDescriptor("hudson.tasks.Maven")
mavenDescriptor.setInstallations(mavenInstallation)
mavenDescriptor.save()

// Configure Dependency Check
def dcInstallation = new org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation(
    "dependency-check",
    "/opt/dependency-check",
    []
)
def dcDescriptor = instance.getDescriptor("org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation")
if (dcDescriptor != null) {
    dcDescriptor.setInstallations(dcInstallation)
    dcDescriptor.save()
}

instance.save()
println "Global tools configured successfully"