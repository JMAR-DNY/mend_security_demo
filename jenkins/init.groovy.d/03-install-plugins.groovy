import jenkins.model.*
import java.util.logging.Logger

def logger = Logger.getLogger("")
def instance = Jenkins.getInstance()
def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()

// Read plugins from file
def pluginsFile = new File("/usr/share/jenkins/ref/plugins.txt")
if (!pluginsFile.exists()) {
    logger.info("No plugins.txt file found, skipping plugin installation")
    return
}

logger.info("Starting plugin installation from plugins.txt...")

// Read and parse plugins
def plugins = []
pluginsFile.eachLine { line ->
    line = line.trim()
    if (line && !line.startsWith("#")) {
        plugins << line
    }
}

logger.info("Found ${plugins.size()} plugins to install")

// Check and install plugins
def pluginsToInstall = []
plugins.each { pluginName ->
    def installed = pm.getPlugin(pluginName)
    if (installed == null) {
        logger.info("Plugin ${pluginName} is not installed, adding to install list")
        pluginsToInstall << pluginName
    } else {
        logger.info("Plugin ${pluginName} is already installed")
    }
}

if (!pluginsToInstall.isEmpty()) {
    logger.info("Installing ${pluginsToInstall.size()} plugins...")
    
    // Update the update center
    uc.updateAllSites()
    
    def installFutures = []
    pluginsToInstall.each { pluginName ->
        def plugin = uc.getPlugin(pluginName)
        if (plugin != null) {
            logger.info("Installing plugin: ${pluginName}")
            installFutures << plugin.deploy()
        } else {
            logger.warning("Plugin ${pluginName} not found in update center")
        }
    }
    
    // Wait for installations to complete
    installFutures.each { it.get() }
    
    logger.info("Plugin installation complete, restart required")
    instance.save()
    instance.doSafeRestart(null)
} else {
    logger.info("All plugins already installed")
}