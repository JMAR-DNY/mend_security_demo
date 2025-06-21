import jenkins.model.*
import hudson.model.*
import hudson.tools.*

def instance = Jenkins.getInstance()

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

println "Tool configuration completed"