#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGE_MANAGER = ROOT / "OpenClawInstaller" / "Localization" / "LanguageManager.swift"
LOCALIZABLE = ROOT / "OpenClawInstaller" / "Localization" / "Resources" / "Localizable.xcstrings"
RESOURCES = ROOT / "OpenClawInstaller" / "Resources"
I18N_ROOT = RESOURCES / "I18n"
SKILLS_ROOT = Path.home() / ".openclaw" / "getclowhub-skills-catalog"
PLUGINS_ROOT = Path.home() / ".openclaw" / "getclowhub-plugins-catalog"
OPENCLAW_PACKAGE_ROOT = Path.home() / ".npm-global" / "lib" / "node_modules" / "openclaw"

COMMON = {
    "common.error.unknown": "unknown error",
    "common.value.unknown": "Unknown",
    "common.action.add": "Add",
    "common.action.cancel": "Cancel",
    "common.action.copy": "Copy",
    "common.action.delete": "Delete",
    "common.action.edit": "Edit",
    "common.action.ok": "OK",
    "common.action.paste": "Paste",
    "common.action.preview": "Preview",
    "common.action.refresh": "Refresh",
    "common.action.remove": "Remove",
    "common.action.rename": "Rename",
    "common.action.retry": "Retry",
    "common.action.create": "Create",
    "common.action.save": "Save",
    "common.action.send": "Send",
    "common.action.start": "Start",
    "common.action.stop": "Stop",
    "common.action.restart": "Restart",
    "common.toast.copied": "Copied",
    "common.empty.parenthesized": "(empty)",
    "app.update.currentVersion": "GetClawHub v%@",
    "app.update.toVersion": "Update to v%@",
    "app.update.installLatest": "Install the latest app update",
    "app.update.upToDate": "Up to date",
    "app.update.check": "Check for Updates",
    "app.update.lookForLatest": "Look for the latest GetClawHub version",
    "billing.loginRequired": "Please log in to view billing.",
    "billing.unavailable": "Billing is not available in this build.",
    "installer.environment.title": "Environment Check",
    "installer.environment.checking": "Checking your system environment...",
    "installer.environment.operatingSystem": "Operating System",
    "installer.environment.architecture": "Architecture",
    "installer.environment.diskSpace": "Available Disk Space",
    "installer.environment.nodeWillUseBundled": "%@ (will use bundled %@)",
    "installer.environment.nodeWillInstallBundled": "Not installed (will install bundled %@)",
    "installer.environment.nodeBundledNote": "OpenClaw includes an independent Node.js %@ runtime and can run without a system Node installation.",
    "installer.environment.openClawNotInstalled": "Not Installed",
    "installer.environment.issuesFound": "Issues Found:",
    "legacy.installer.title": "OpenClaw Installer",
    "legacy.installer.subtitleMacOS": "for macOS",
    "legacy.installer.checkingEnvironment": "Checking environment...",
    "legacy.installer.systemInformation": "System Information",
    "legacy.installer.checkEnvironment": "Check Environment",
    "legacy.installer.startInstallation": "Start Installation",
    "legacy.installer.adminPrivileges": "Administrator Privileges",
    "legacy.installer.granted": "Granted",
    "legacy.installer.notGranted": "Not Granted",
    "legacy.installer.notDetected": "Not Detected",
    "install.status.uninstalling": "Uninstalling OpenClaw...",
    "install.status.uninstallComplete": "Uninstall Complete",
    "install.status.dataPreserved": "Configuration and login data preserved. Can be restored after reinstallation.",
    "install.status.openclawInstalled": "OpenClaw is installed",
    "install.status.readyToInstall": "Ready to install OpenClaw",
    "install.status.installed": "Installed",
    "install.status.completed": "Completed",
    "install.status.starting": "Starting",
    "install.action.start": "Start Installation",
    "install.action.openDashboard": "Open Dashboard",
    "install.action.uninstall": "Uninstall",
    "install.action.quit": "Quit",
    "install.action.getStarted": "Get Started",
    "install.action.generate": "Generate",
    "install.action.continue": "Continue",
    "install.action.retryStart": "Retry Start",
    "install.action.goToManagement": "Go to Management",
    "install.alert.uninstallTitle": "Uninstall OpenClaw?",
    "install.alert.uninstallMessage": "This will remove OpenClaw, Node.js runtime and log files.\nConfiguration and login data will be preserved.",
    "install.welcome.title": "Welcome to OpenClaw Installer",
    "install.welcome.subtitle": "This wizard will install and configure OpenClaw on your Mac.",
    "install.welcome.feature.automated.title": "Automated Setup",
    "install.welcome.feature.automated.description": "Check your environment and install required components automatically.",
    "install.welcome.feature.configuration.title": "Easy Configuration",
    "install.welcome.feature.configuration.description": "Set up your gateway token and local configuration in one flow.",
    "install.welcome.feature.secure.title": "Secure",
    "install.welcome.feature.secure.description": "Protect local gateway access with an authentication token.",
    "install.welcome.feature.quick.title": "Quick Setup",
    "install.welcome.feature.quick.description": "Complete installation in just a few minutes.",
    "install.node.title": "Node.js Installation",
    "install.node.installingNode": "Installing Node.js",
    "install.node.solution.internet": "Check your internet connection and try again.",
    "install.node.solution.disk": "Make sure there is enough disk space.",
    "install.node.solution.vpn": "If downloads fail, try switching network or VPN.",
    "install.node.success": "Node.js installed successfully",
    "install.node.ready": "Ready",
    "install.openclaw.title": "OpenClaw Installation",
    "install.openclaw.installing": "Installing OpenClaw",
    "install.openclaw.solution.node": "Make sure Node.js was installed successfully.",
    "install.openclaw.solution.npm": "Check npm access and package availability.",
    "install.openclaw.solution.network": "Check your network connection.",
    "install.openclaw.solution.log": "Review the installation log for details.",
    "install.openclaw.success": "OpenClaw installed successfully",
    "install.openclaw.readyForConfig": "Ready for configuration",
    "install.openclaw.configHelp": "Continue to configure the local gateway.",
    "install.shared.log": "Installation Log",
    "install.shared.progress": "Progress",
    "install.shared.failed": "Installation Failed",
    "install.shared.errorDetails": "Error Details:",
    "install.shared.possibleSolutions": "Possible Solutions:",
    "install.shared.solution.retry": "Retry after fixing the issue.",
    "install.shared.version": "Version:",
    "install.shared.location": "Location:",
    "install.shared.status": "Status:",
    "install.config.title": "Gateway Configuration",
    "install.config.subtitle": "Configure your local OpenClaw gateway.",
    "install.config.authToken": "Gateway Auth Token",
    "install.config.tokenPlaceholder": "Enter Gateway Auth Token",
    "install.config.tokenHelp": "This token is stored in ~/.openclaw/openclaw.json and used when opening the dashboard.",
    "install.config.whyToken": "Why set an auth token?",
    "install.config.whyTokenDetail": "The auth token protects your local gateway from unauthorized access.",
    "install.complete.title": "Installation Complete!",
    "install.complete.subtitle": "OpenClaw is ready to use.",
    "install.complete.configuration": "Configuration",
    "install.complete.gatewayStarting": "Starting OpenClaw Gateway service...",
    "install.complete.gatewayStarted": "OpenClaw Gateway started",
    "install.complete.gatewayFailed": "Gateway failed to start",
    "install.progress.checkingEnvironment": "Checking system environment...",
    "install.progress.analyzingRequirements": "Analyzing requirements...",
    "install.progress.systemRequirementsNotMet": "System requirements not met:\n%@",
    "install.progress.nodeRequired": "Node.js installation required",
    "install.progress.nodeUpgradeRequired": "Node.js upgrade required",
    "install.progress.nodeAlreadyInstalled": "Node.js already installed",
    "install.progress.openClawAlreadyInstalled": "OpenClaw already installed",
    "install.progress.openClawRequired": "OpenClaw installation required",
    "install.progress.startingNode": "Starting Node.js installation...",
    "install.progress.nodeSuccess": "Node.js installed successfully",
    "install.progress.nodeFailed": "Node.js installation failed: %@",
    "install.progress.startingOpenClaw": "Starting OpenClaw installation...",
    "install.progress.openClawSuccess": "OpenClaw installed successfully",
    "install.progress.openClawFailed": "OpenClaw installation failed: %@",
    "install.progress.savingConfig": "Saving gateway configuration...",
    "install.progress.configSaved": "Configuration saved",
    "install.progress.configSaveFailed": "Failed to save configuration: %@",
    "install.node.status.detectingRegion": "Detecting region...",
    "install.node.region.china": "China",
    "install.node.region.international": "International",
    "install.node.mirror.china": "China mirror",
    "install.node.mirror.official": "Official mirror",
    "install.node.status.regionDetected": "Region detected: %@. Fetching latest Node.js version...",
    "install.node.status.latestLTS": "Latest LTS version: %@",
    "install.node.status.downloadingFrom": "Downloading Node.js %@ from %@...",
    "install.node.status.downloadComplete": "Download complete",
    "install.node.status.downloadingPercent": "Downloading... %lld%%",
    "install.node.status.verifyingDownload": "Verifying download integrity...",
    "install.node.status.preparingExtract": "Preparing to extract Node.js...",
    "install.node.status.extracting": "Extracting Node.js (this may take a moment)...",
    "install.node.status.extractingPercent": "Extracting Node.js... %lld%%",
    "install.node.status.verifyingBinaries": "Verifying extracted binaries...",
    "install.node.status.complete": "Installation complete",
    "install.node.status.installing": "Installing Node.js...",
    "install.node.status.verifyingInstallation": "Verifying installation...",
    "install.node.status.installedAt": "Node.js %@ installed at %@",
    "install.node.status.usingBundled": "Using bundled Node.js %@...",
    "install.node.status.bundledMissing": "Bundled Node.js not found, downloading...",
    "install.node.status.success": "Node.js installation successful!",
    "install.node.status.cancelled": "Download cancelled",
    "install.openclaw.status.installingBundled": "Installing OpenClaw from bundled package...",
    "install.openclaw.status.extracting": "Extracting OpenClaw...",
    "install.openclaw.status.extractingPercent": "Extracting OpenClaw... %lld%%",
    "install.openclaw.status.removingQuarantine": "Removing quarantine attributes...",
    "install.openclaw.status.settingUpBinary": "Setting up OpenClaw binary...",
    "install.openclaw.status.complete": "Installation complete!",
    "install.openclaw.status.configuring": "Configuring OpenClaw...",
    "install.openclaw.status.configured": "OpenClaw configured successfully",
    "install.openclaw.status.verifying": "Verifying installation...",
    "install.openclaw.status.verifiedAt": "OpenClaw %@ verified at %@",
    "install.openclaw.status.installedAt": "OpenClaw installed at %@",
    "menu.status.uptime": "Uptime:",
    "menu.status.openDashboard": "Open Dashboard",
    "menu.status.startService": "Start Service",
    "menu.status.stopService": "Stop Service",
    "menu.status.statusLine": "Status: %@",
    "menu.status.restartService": "Restart",
    "menu.status.checkUpdates": "Check for Updates",
    "menu.status.showMainWindow": "Show Main Window",
    "menu.status.quitInstaller": "Quit OpenClaw Installer",
    "menu.status.helperVersion": "OpenClaw Helper v%@ (%@)",
    "menu.status.serviceVersion": "OpenClaw Service %@",
    "help.status.online": "Online",
    "help.status.offline": "Offline",
    "help.welcome.title": "Hi! I'm GetClawHub Assistant",
    "help.welcome.subtitle": "Ask me anything about using GetClowHub.",
    "help.status.typing": "Typing...",
    "help.status.offlineFaq": "Offline — FAQ answers only",
    "help.input.placeholder": "Ask a question...",
    "help.quick.status.start": "What if the service won't start?",
    "help.quick.status.restart": "How to restart the service?",
    "help.quick.status.systemInfo": "How to view system info?",
    "help.quick.config.models": "How to configure models?",
    "help.quick.config.port": "How to change the port?",
    "help.quick.config.provider": "How to switch providers?",
    "help.quick.chat.slash": "How to use slash commands?",
    "help.quick.chat.switchAssistant": "How to switch AI assistant?",
    "help.quick.chat.history": "How to view message history?",
    "help.quick.cron.create": "How to create a cron job?",
    "help.quick.cron.expression": "How to write cron expressions?",
    "help.quick.cron.pause": "How to pause a task?",
    "help.quick.persona.edit": "How to edit AI personality?",
    "help.quick.persona.files": "What are the four files?",
    "help.quick.persona.preview": "How to preview changes?",
    "help.quick.subAgents.create": "How to create a sub-agent?",
    "help.quick.subAgents.switch": "How to switch AI in Chat?",
    "help.quick.subAgents.delete": "How to delete a sub-agent?",
    "help.quick.skills.install": "How to install a skill?",
    "help.quick.skills.status": "What do skill statuses mean?",
    "help.quick.skills.findMore": "Where to find more skills?",
    "help.quick.models.default": "How to set the default model?",
    "help.quick.models.fallback": "What is Fallback?",
    "help.quick.models.image": "How to add an image model?",
    "help.quick.channels.telegram": "How to connect Telegram?",
    "help.quick.channels.status": "What do channel status lights mean?",
    "help.quick.channels.remove": "How to remove a channel?",
    "help.quick.plugins.enable": "How to enable a plugin?",
    "help.quick.plugins.available": "What plugins are available?",
    "help.quick.plugins.status": "What do plugin statuses mean?",
    "help.quick.logs.search": "How to search logs?",
    "help.quick.logs.colors": "What do log colors mean?",
    "help.quick.logs.export": "How to export logs?",
    "help.quick.budget.set": "How to set a budget?",
    "help.quick.budget.alerts": "How do budget alerts work?",
    "help.quick.budget.costs": "How to view costs?",
    "help.quick.billing.view": "How to view billing?",
    "help.quick.billing.limit": "What is the spend limit for a key?",
    "help.quick.billing.reset": "How often does the budget reset?",
    "help.quick.market.install": "How to install an agent?",
    "help.quick.market.contents": "What's in the marketplace?",
    "help.quick.market.uninstall": "How to uninstall an agent?",
    "help.quick.tasks.create": "How to create a cron job?",
    "help.quick.tasks.pause": "How to pause automation?",
    "help.quick.tasks.edit": "How to edit automation?",
    "help.quick.outputs.what": "What appears in Outputs?",
    "help.quick.outputs.hidden": "Why are config files hidden?",
    "help.quick.outputs.open": "How to open generated files?",
    "subAgents.title": "Multi-Agent",
    "subAgents.count.agents": "(%lld agents)",
    "subAgents.action.new": "New Agent",
    "subAgents.action.openWorkspace": "Open Workspace",
    "subAgents.loading.agents": "Loading agents...",
    "subAgents.loading.models": "Loading models...",
    "subAgents.empty.title": "No agents yet",
    "subAgents.empty.detail": "Create an agent to specialize in different tasks",
    "subAgents.toast.fileSaved": "%@ %@ saved",
    "subAgents.toast.deleted": "Agent \"%@\" deleted",
    "subAgents.toast.modelChanged": "%@ model → %@",
    "subAgents.alert.deleteTitle": "Delete Agent",
    "subAgents.alert.deleteMessage": "Delete \"%@\"? This will remove the agent and its workspace.",
    "subAgents.model.label": "Model:",
    "subAgents.model.default": "Default",
    "subAgents.model.defaultInherit": "Default (inherit)",
    "subAgents.model.defaultFromConfig": "Default (inherit from config)",
    "subAgents.model.defaultTag": "(default)",
    "subAgents.create.title": "New Agent",
    "subAgents.create.agentId": "Agent ID",
    "subAgents.create.agentIdPlaceholder": "e.g. news-helper",
    "subAgents.create.agentIdHelp": "Lowercase letters, numbers, hyphens only",
    "subAgents.create.displayName": "Display Name",
    "subAgents.create.displayNamePlaceholder": "e.g. News Helper",
    "subAgents.create.displayNameHelp": "Optional. Written to IDENTITY.md as the agent's name",
    "subAgents.create.model": "Model",
    "subAgents.create.division": "Division",
    "subAgents.create.divisionHelp": "Agent category for sidebar grouping",
    "collab.title": "Collab Tasks",
    "collab.empty.title": "No collaboration tasks",
    "collab.empty.detail": "Type /collab in chat or select Commander to send a task",
    "collab.history.help": "Collaboration history (%lld)",
    "collab.history.title": "History",
    "collab.history.records": "%lld records",
    "collab.history.subtasks": "%lld/%lld subtasks",
    "collab.commander.settings": "Commander Settings",
    "collab.panel.collapse": "Collapse panel",
    "collab.panel.close": "Close panel",
    "collab.progress.label": "Progress: %@",
    "collab.phase.understanding": "Understanding...",
    "collab.phase.researching": "Researching...",
    "collab.phase.decomposing": "Decomposing...",
    "collab.phase.awaitingApproval": "Awaiting approval",
    "collab.phase.running": "Running...",
    "collab.phase.verifying": "Verifying...",
    "collab.phase.summarizing": "Summarizing...",
    "collab.phase.done": "Done",
    "collab.phase.runningPlain": "Running",
    "collab.phase.verifyingPlain": "Verifying",
    "collab.phase.summarizingPlain": "Summarizing",
    "collab.phase.preparing": "Preparing",
    "collab.requirements.gathering": "Requirements Gathering",
    "collab.final.summary": "Final Summary",
    "collab.settings.agentTimeout": "Agent Timeout",
    "collab.settings.custom": "Custom",
    "collab.settings.hours": "hours",
    "collab.settings.timeoutHelp": "Max execution time per subtask (current: %@)",
    "collab.settings.maxConcurrency": "Max Concurrency",
    "collab.settings.unlimited": "Unlimited",
    "collab.settings.maxConcurrencyHelp": "Max concurrent subtasks (0 = unlimited)",
    "collab.settings.retryContextLength": "Retry Context Length",
    "collab.settings.chars": "chars",
    "collab.settings.retryContextHelp": "History length passed to agent on retry",
    "collab.settings.resetDefaults": "Reset Defaults",
    "collab.action.cancelAll": "Cancel All",
    "collab.task.retry": "Retry this task",
    "collab.task.forceComplete": "Mark as completed (unblock downstream tasks)",
    "collab.task.skip": "Skip this task",
    "collab.task.dependsOn": "Depends on: #%@",
    "collab.task.error": "Error: %@",
    "collab.process.running": "Process running",
    "collab.process.ended": "Process ended",
    "collab.process.lines": "%lld lines",
    "collab.process.files": "%lld files",
    "collab.process.longRunning": "Long running",
    "collab.output.files": "Output files:",
    "collab.agent.running": "Agent running...",
    "catalog.action.install": "Install",
    "catalog.action.installing": "Installing...",
    "catalog.action.uninstall": "Uninstall",
    "catalog.action.remove": "Remove",
    "catalog.action.removing": "Removing...",
    "catalog.action.cancel": "Cancel",
    "catalog.action.close": "Close",
    "catalog.action.refresh": "Refresh",
    "catalog.action.update": "Update",
    "catalog.action.upgrade": "Upgrade",
    "catalog.action.upgrading": "Upgrading...",
    "catalog.action.enable": "Enable",
    "catalog.action.disable": "Disable",
    "catalog.status.installed": "Installed",
    "catalog.status.notInstalled": "Not installed",
    "catalog.status.ready": "Ready",
    "catalog.status.missing": "Missing",
    "catalog.status.loaded": "Loaded",
    "catalog.status.disabled": "Disabled",
    "catalog.status.unavailable": "Unavailable",
    "catalog.status.updateAvailable": "Update available",
    "catalog.section.recommend": "Recommend",
    "catalog.section.catalog": "Catalog",
    "catalog.section.all": "All",
    "catalog.section.installed": "Installed",
    "catalog.section.builtIn": "Built-in",
    "catalog.section.custom": "Custom",
    "catalog.detail.description": "Description",
    "catalog.count.installed": "%lld installed",
    "dashboard.count.configured": "(%lld configured)",
    "dashboard.status.port": "Port",
    "dashboard.status.uptime": "Uptime",
    "dashboard.status.version": "Version",
    "dashboard.status.service.running": "Running",
    "dashboard.status.service.stopped": "Stopped",
    "dashboard.status.service.starting": "Starting",
    "dashboard.status.service.stopping": "Stopping",
    "dashboard.status.service.error": "Error",
    "dashboard.status.service.unknown": "Unknown",
    "dashboard.status.agentSessions": "Agent Sessions",
    "dashboard.status.totalAgents": "Total: %lld agents",
    "dashboard.status.noSessions": "No sessions",
    "dashboard.status.cronHealth": "Cron Health",
    "dashboard.status.total": "Total: %lld",
    "dashboard.status.active": "Active: %lld",
    "dashboard.status.next": "Next: %@",
    "dashboard.status.disabledParen": "(disabled)",
    "dashboard.status.channelsCount": "%lld channels",
    "dashboard.status.tokenUsage": "Token Usage",
    "dashboard.status.tokenTotal": "Total:",
    "dashboard.status.noTokenData": "No token data",
    "dashboard.status.systemInformation": "System Information",
    "dashboard.status.macosVersion": "macOS Version",
    "dashboard.status.architecture": "Architecture",
    "dashboard.status.availableSpace": "Available Space",
    "dashboard.status.openClawPath": "OpenClaw Path",
    "dashboard.status.label.budget": "Budget:",
    "dashboard.status.label.cost": "Cost:",
    "dashboard.status.label.estimatedCost": "Est. Cost:",
    "dashboard.service.toast.started": "Service started successfully",
    "dashboard.service.toast.startFailed": "Failed to start service: %@",
    "dashboard.service.toast.stopped": "Service stopped successfully",
    "dashboard.service.toast.stopFailed": "Failed to stop service: %@",
    "dashboard.service.toast.restarted": "Service restarted successfully",
    "dashboard.service.toast.restartFailed": "Failed to restart service: %@",
    "dashboard.config.error.invalidPort": "Invalid port number. Must be between 1 and 65535",
    "dashboard.config.toast.saved": "Configuration saved to openclaw.json",
    "dashboard.config.error.saveFailed": "Failed to save configuration file",
    "dashboard.alert.error": "Error",
    "dashboard.agent.remove.title": "Remove Agent",
    "dashboard.agent.remove.message": "Are you sure you want to remove \"%@\"? This will delete the agent and its workspace.",
    "dashboard.agent.addWorkFolder": "Add Work Folder...",
    "dashboard.agent.fallbackDescription": "General-purpose assistant",
    "dashboard.model.label": "Model",
    "dashboard.model.defaultInherit": "Default (inherit)",
    "dashboard.model.defaultWithValue": "Default (%@)",
    "dashboard.chat.viewResult": "View result ↑",
    "dashboard.chat.moveToBackground": "Move to Background",
    "dashboard.chat.clearConversation": "Clear Conversation",
    "dashboard.chat.modelSwitchFailedNotSent": "Could not switch to the selected model, so the message was not sent.",
    "dashboard.diagnostics.title": "Diagnostics Report",
    "dashboard.outputs.title": "Outputs",
    "dashboard.outputs.empty": "No outputs yet",
    "dashboard.terminal.title": "Terminal",
    "dashboard.activity.empty": "No activity yet",
    "dashboard.tooltip.chooseModel": "Choose model",
    "dashboard.tooltip.attachFile": "Attach File",
    "dashboard.tooltip.searchChats": "Search chats",
    "dashboard.tooltip.taskRunning": "Task running",
    "dashboard.tooltip.hideTerminal": "Hide Terminal",
    "dashboard.tooltip.showTerminal": "Show Terminal",
    "dashboard.tooltip.hideOutputs": "Hide Outputs",
    "dashboard.tooltip.showOutputs": "Show Outputs",
    "dashboard.tooltip.confirmAndSend": "Confirm and send",
    "dashboard.tooltip.removeAttachment": "Remove attachment",
    "dashboard.tooltip.openOutputsFolder": "Open Outputs Folder",
    "dashboard.tooltip.clearConversation": "Clear Conversation",
    "dashboard.tooltip.collapseSessionDetails": "Collapse session details",
    "dashboard.tooltip.expandSessionDetails": "Expand session details",
    "dashboard.tooltip.editAgent": "Edit agent",
    "dashboard.session.action.rename": "Rename",
    "dashboard.session.action.pin": "Pin",
    "dashboard.session.action.unpin": "Unpin",
    "dashboard.session.action.export": "Export…",
    "dashboard.session.action.archive": "Archive",
    "dashboard.session.action.confirmDelete": "Confirm delete",
    "dashboard.session.newChat": "New chat",
    "dashboard.sidebar.pinned": "Pinned",
    "dashboard.skills.title": "Skills",
    "dashboard.skills.enabledCount": "%lld / %lld enabled",
    "dashboard.skills.loading": "Loading…",
    "dashboard.skills.empty": "No skills detected",
    "dashboard.skills.viewAll": "View all (%lld)",
    "dashboard.composer.mode.label": "Mode:",
    "dashboard.composer.mode.chat": "Chat",
    "dashboard.composer.mode.task": "Run Task",
    "dashboard.composer.mode.code": "Code Mode",
    "dashboard.channels.title": "Channels",
    "dashboard.channels.add": "Add Channel",
    "dashboard.channels.loading": "Loading channels...",
    "dashboard.channels.empty.title": "No channels configured",
    "dashboard.channels.empty.detail": "Add a channel to get started",
    "dashboard.channels.status.configured": "Configured",
    "dashboard.channels.status.notConfigured": "Not Configured",
    "dashboard.channels.status.linked": "Linked",
    "dashboard.channels.status.notLinked": "Not Linked",
    "dashboard.channels.status.connected": "Connected",
    "dashboard.channels.alert.removeTitle": "Remove Channel",
    "dashboard.channels.alert.removeMessage": "Are you sure you want to remove the %@ channel? This will delete its configuration.",
    "dashboard.channels.sheet.channelType": "Channel Type",
    "dashboard.channels.sheet.pluginMissing": "Plugin for %@ is not installed. Please install the plugin first.",
    "dashboard.channels.sheet.qr.startHelp": "Click the button below to start WeChat QR login",
    "dashboard.channels.sheet.qr.start": "Start QR Login",
    "dashboard.channels.sheet.qr.scan": "Scan with WeChat to connect",
    "dashboard.channels.sheet.qr.waiting": "Waiting for scan...",
    "dashboard.channels.sheet.qr.generating": "Generating QR code...",
    "dashboard.channels.sheet.qr.success": "WeChat connected successfully!",
    "dashboard.channels.sheet.done": "Done",
    "dashboard.channels.sheet.accountId": "Account ID",
    "dashboard.channels.sheet.accountHelp": "Use default for the primary account, or enter another ID to add multiple accounts for the same channel.",
    "dashboard.channels.sheet.displayName": "Display Name",
    "dashboard.channels.sheet.optional": "Optional",
    "dashboard.channels.sheet.appKey": "App Key",
    "dashboard.channels.sheet.enterAppKey": "Enter App Key",
    "dashboard.channels.sheet.appSecret": "App Secret",
    "dashboard.channels.sheet.enterAppSecret": "Enter App Secret",
    "dashboard.channels.sheet.dingtalkHelp": "Go to DingTalk Open Platform to create an app and get the App Key and App Secret.",
    "dashboard.channels.sheet.feishuHelp": "Go to Feishu Open Platform to create an app and get the App ID and App Secret.",
    "dashboard.channels.sheet.token": "Token",
    "dashboard.channels.sheet.enterToken": "Enter bot token or API key",
    "dashboard.channels.sheet.tokenHelp": "For Telegram/Discord: bot token. For Slack: bot token (xoxb-...). Other channels may require different credentials.",
    "dashboard.channels.sheet.cliHelp": "For channels with complex setup (Slack, Matrix, etc.), use the command line:",
    "dashboard.channels.toast.addFailed": "Failed to add %@ %@: %@",
    "dashboard.channels.toast.added": "%@ %@ channel added",
    "dashboard.channels.toast.readConfigFailed": "Failed to read openclaw.json",
    "dashboard.channels.toast.removeFailed": "Failed to remove %@: %@",
    "dashboard.channels.toast.removed": "%@ channel removed",
    "dashboard.cron.title": "Cron Jobs",
    "dashboard.cron.add": "Add Job",
    "dashboard.cron.refreshing": "Refreshing...",
    "dashboard.cron.loadFailed.title": "Could not load cron jobs",
    "dashboard.cron.checking.title": "Checking cron jobs",
    "dashboard.cron.checking.detail": "Reading scheduled automation tasks...",
    "dashboard.cron.empty.title": "No cron jobs configured",
    "dashboard.cron.empty.detail": "Add a cron job to schedule automated tasks",
    "dashboard.cron.agentTag": "Agent: %@",
    "dashboard.cron.next": "Next: %@",
    "dashboard.cron.last": "Last: %@",
    "dashboard.cron.alert.removeTitle": "Remove Cron Job",
    "dashboard.cron.alert.removeMessage": "Are you sure you want to remove the cron job '%@'? This action cannot be undone.",
    "dashboard.cron.sheet.title": "Add Cron Job",
    "dashboard.cron.sheet.name": "Name",
    "dashboard.cron.sheet.namePlaceholder": "e.g. daily-report",
    "dashboard.cron.sheet.expression": "Cron Expression",
    "dashboard.cron.sheet.expressionPlaceholder": "e.g. 0 9 * * *",
    "dashboard.cron.sheet.expressionHelp": "Format: minute hour day month weekday (e.g. \"0 9 * * *\" = every day at 9:00 AM)",
    "dashboard.cron.sheet.timezone": "Timezone",
    "dashboard.cron.sheet.timezonePlaceholder": "e.g. Asia/Shanghai",
    "dashboard.cron.sheet.agent": "Agent",
    "dashboard.cron.sheet.sessionTarget": "Session Target",
    "dashboard.cron.sheet.session.isolated": "Isolated",
    "dashboard.cron.sheet.session.main": "Main",
    "dashboard.cron.sheet.sessionHelp": "Isolated: each run in a separate session. Main: reuse the main session.",
    "dashboard.cron.sheet.message": "Message",
    "dashboard.cron.sheet.messagePlaceholder": "The message/instruction to send when the cron job triggers...",
    "dashboard.cron.toast.addFailed": "Failed to add cron job: %@",
    "dashboard.cron.toast.created": "Cron job '%@' created",
    "dashboard.cron.toast.enableFailed": "Failed to enable cron job: %@",
    "dashboard.cron.toast.enabled": "Cron job '%@' enabled",
    "dashboard.cron.toast.disableFailed": "Failed to disable cron job: %@",
    "dashboard.cron.toast.disabled": "Cron job '%@' disabled",
    "dashboard.cron.toast.removeFailed": "Failed to remove cron job: %@",
    "dashboard.cron.toast.removed": "Cron job '%@' removed",
    "dashboard.cron.toast.runFailed": "Failed to run cron job: %@",
    "dashboard.cron.toast.triggered": "Cron job '%@' triggered",
    "dashboard.models.title": "Models",
    "dashboard.models.loading": "Loading models...",
    "dashboard.models.empty": "No models configured",
    "dashboard.models.cliHint": "For aliases and auth configuration, use:",
    "dashboard.models.default": "Default",
    "dashboard.models.imageModel": "Image Model",
    "dashboard.models.notSet": "Not set",
    "dashboard.models.fallbacks": "Fallbacks",
    "dashboard.models.imageFallbacks": "Img Fallbacks",
    "dashboard.models.none": "None",
    "dashboard.models.fallbackModels": "Fallback Models",
    "dashboard.models.imageFallbackModels": "Image Fallback Models",
    "dashboard.models.badge.default": "DEFAULT",
    "dashboard.models.badge.image": "IMAGE",
    "dashboard.models.badge.fallback": "FALLBACK",
    "dashboard.models.badge.imageFallback": "IMG FB",
    "dashboard.models.local": "Local",
    "dashboard.models.auth": "Auth",
    "dashboard.models.action.setImage": "Set Image",
    "dashboard.models.action.setImageFallback": "Set Img FB",
    "dashboard.models.action.fallback": "Fallback",
    "dashboard.models.action.setFallback": "Set Fallback",
    "dashboard.models.action.setDefault": "Set Default",
    "dashboard.models.toast.setDefaultFailed": "Failed to set default model: %@",
    "dashboard.models.toast.defaultSet": "Default model set to %@",
    "dashboard.models.toast.setImageFailed": "Failed to set image model: %@",
    "dashboard.models.toast.imageSet": "Image model set to %@",
    "dashboard.models.toast.addFallbackFailed": "Failed to add fallback: %@",
    "dashboard.models.toast.fallbackAdded": "%@ added to fallbacks",
    "dashboard.models.toast.removeFallbackFailed": "Failed to remove fallback: %@",
    "dashboard.models.toast.fallbackRemoved": "%@ removed from fallbacks",
    "dashboard.models.toast.addImageFallbackFailed": "Failed to add image fallback: %@",
    "dashboard.models.toast.imageFallbackAdded": "%@ added to image fallbacks",
    "dashboard.models.toast.removeImageFallbackFailed": "Failed to remove image fallback: %@",
    "dashboard.models.toast.imageFallbackRemoved": "%@ removed from image fallbacks",
    "dashboard.logs.searchPlaceholder": "Search logs...",
    "dashboard.logs.auto": "Auto",
    "dashboard.logs.export": "Export",
    "dashboard.logs.openFile": "Open File",
    "dashboard.logs.empty.title": "No Logs Available",
    "dashboard.logs.empty.detail": "Logs will appear here when the gateway service is running",
    "dashboard.logs.toast.exported": "Logs exported successfully",
    "dashboard.logs.toast.cleared": "Logs cleared",
    "workspace.outputs.title": "Outputs",
    "workspace.outputs.openInFinder": "Open in Finder",
    "workspace.outputs.hideProjectFiles": "Hide Project Files",
    "workspace.outputs.showProjectFiles": "Show Project Files",
    "workspace.outputs.empty": "No outputs yet",
    "workspace.files.filterPlaceholder": "Filter files...",
    "workspace.files.empty": "No files",
    "workspace.files.noMatches": "No matching files",
    "workspace.files.fallbackPath": "Fallback: %@",
    "workspace.files.newFile": "New File",
    "workspace.files.newFolder": "New Folder",
    "workspace.files.cut": "Cut",
    "workspace.files.copy": "Copy",
    "workspace.files.paste": "Paste",
    "workspace.files.deleteConfirm": "Are you sure you want to delete \"%@\"?",
    "workspace.files.pathCopied": "Path copied",
    "workspace.files.copyPathHelp": "Double-click to copy path",
    "workspace.files.decreaseFont": "Decrease font size (⌘-)",
    "workspace.files.increaseFont": "Increase font size (⌘+)",
    "workspace.files.disableWordWrap": "Disable word wrap",
    "workspace.files.enableWordWrap": "Enable word wrap",
    "workspace.files.fullscreen": "Fullscreen",
    "workspace.files.exitFullscreen": "Exit Fullscreen",
    "workspace.files.position": "Ln %lld, Col %lld",
    "workspace.project.newChat": "New chat in project",
    "workspace.project.revealInFinder": "Reveal in Finder",
    "workspace.project.removeFromAgent": "Remove from Agent",
    "error.report.action": "Report Issue",
    "error.report.title": "Error Report Copied",
    "error.report.message": "Error details have been copied to your clipboard. Please paste them when reporting the issue.",
    "error.report.contentTitle": "Error Report",
    "error.report.contentSystemInfo": "System Info:",
    "error.report.contentPleaseReport": "Please report this issue to the developers."
}

COMMON_ZH_HANS = {
    "common.error.unknown": "未知错误",
    "common.value.unknown": "未知",
    "common.action.add": "添加",
    "common.action.cancel": "取消",
    "common.action.copy": "复制",
    "common.action.delete": "删除",
    "common.action.edit": "编辑",
    "common.action.ok": "确定",
    "common.action.paste": "粘贴",
    "common.action.preview": "预览",
    "common.action.refresh": "刷新",
    "common.action.remove": "移除",
    "common.action.rename": "重命名",
    "common.action.retry": "重试",
    "common.action.create": "创建",
    "common.action.save": "保存",
    "common.action.send": "发送",
    "common.action.start": "启动",
    "common.action.stop": "停止",
    "common.action.restart": "重启",
    "common.toast.copied": "已复制",
    "common.empty.parenthesized": "（空）",
    "app.update.currentVersion": "GetClawHub v%@",
    "app.update.toVersion": "更新到 v%@",
    "app.update.installLatest": "安装最新应用更新",
    "app.update.upToDate": "已是最新版本",
    "app.update.check": "检查更新",
    "app.update.lookForLatest": "检查最新的 GetClawHub 版本",
    "billing.loginRequired": "请先登录后查看账单。",
    "billing.unavailable": "当前构建不包含账单功能。",
    "installer.environment.title": "环境检查",
    "installer.environment.checking": "正在检查系统环境...",
    "installer.environment.operatingSystem": "操作系统",
    "installer.environment.architecture": "架构",
    "installer.environment.diskSpace": "可用磁盘空间",
    "installer.environment.nodeWillUseBundled": "%@（将使用内置 %@）",
    "installer.environment.nodeWillInstallBundled": "未安装（将自动安装内置 %@）",
    "installer.environment.nodeBundledNote": "OpenClaw 自带独立的 Node.js %@ 运行时，无需系统 Node 即可运行。",
    "installer.environment.openClawNotInstalled": "未安装",
    "installer.environment.issuesFound": "发现问题：",
    "legacy.installer.title": "OpenClaw 安装器",
    "legacy.installer.subtitleMacOS": "适用于 macOS",
    "legacy.installer.checkingEnvironment": "正在检查环境...",
    "legacy.installer.systemInformation": "系统信息",
    "legacy.installer.checkEnvironment": "检查环境",
    "legacy.installer.startInstallation": "开始安装",
    "legacy.installer.adminPrivileges": "管理员权限",
    "legacy.installer.granted": "已授予",
    "legacy.installer.notGranted": "未授予",
    "legacy.installer.notDetected": "未检测到",
    "install.status.uninstalling": "正在卸载 OpenClaw...",
    "install.status.uninstallComplete": "卸载完成",
    "install.status.dataPreserved": "配置和登录数据已保留，重新安装后可恢复。",
    "install.status.openclawInstalled": "OpenClaw 已安装",
    "install.status.readyToInstall": "可以安装 OpenClaw",
    "install.status.installed": "已安装",
    "install.status.completed": "已完成",
    "install.status.starting": "启动中",
    "install.action.start": "开始安装",
    "install.action.openDashboard": "打开控制台",
    "install.action.uninstall": "卸载",
    "install.action.quit": "退出",
    "install.action.getStarted": "开始",
    "install.action.generate": "生成",
    "install.action.continue": "继续",
    "install.action.retryStart": "重试启动",
    "install.action.goToManagement": "进入管理",
    "install.alert.uninstallTitle": "卸载 OpenClaw？",
    "install.alert.uninstallMessage": "这将移除 OpenClaw、Node.js 运行时和日志文件。\n配置和登录数据会被保留。",
    "install.welcome.title": "欢迎使用 OpenClaw 安装器",
    "install.welcome.subtitle": "此向导会在你的 Mac 上安装并配置 OpenClaw。",
    "install.welcome.feature.automated.title": "自动化安装",
    "install.welcome.feature.automated.description": "自动检查环境并安装所需组件。",
    "install.welcome.feature.configuration.title": "轻松配置",
    "install.welcome.feature.configuration.description": "在一个流程中设置 Gateway Token 和本地配置。",
    "install.welcome.feature.secure.title": "安全",
    "install.welcome.feature.secure.description": "使用认证 Token 保护本地 Gateway 访问。",
    "install.welcome.feature.quick.title": "快速设置",
    "install.welcome.feature.quick.description": "几分钟内完成安装。",
    "install.node.title": "Node.js 安装",
    "install.node.installingNode": "正在安装 Node.js",
    "install.node.solution.internet": "检查网络连接后重试。",
    "install.node.solution.disk": "确认有足够的磁盘空间。",
    "install.node.solution.vpn": "如果下载失败，请尝试切换网络或 VPN。",
    "install.node.success": "Node.js 安装成功",
    "install.node.ready": "就绪",
    "install.openclaw.title": "OpenClaw 安装",
    "install.openclaw.installing": "正在安装 OpenClaw",
    "install.openclaw.solution.node": "确认 Node.js 已成功安装。",
    "install.openclaw.solution.npm": "检查 npm 访问和包可用性。",
    "install.openclaw.solution.network": "检查网络连接。",
    "install.openclaw.solution.log": "查看安装日志获取详细信息。",
    "install.openclaw.success": "OpenClaw 安装成功",
    "install.openclaw.readyForConfig": "可以进行配置",
    "install.openclaw.configHelp": "继续配置本地 Gateway。",
    "install.shared.log": "安装日志",
    "install.shared.progress": "进度",
    "install.shared.failed": "安装失败",
    "install.shared.errorDetails": "错误详情：",
    "install.shared.possibleSolutions": "可能的解决方案：",
    "install.shared.solution.retry": "修复问题后重试。",
    "install.shared.version": "版本：",
    "install.shared.location": "位置：",
    "install.shared.status": "状态：",
    "install.config.title": "Gateway 配置",
    "install.config.subtitle": "配置本地 OpenClaw Gateway。",
    "install.config.authToken": "Gateway 认证 Token",
    "install.config.tokenPlaceholder": "输入 Gateway 认证 Token",
    "install.config.tokenHelp": "此 Token 会保存到 ~/.openclaw/openclaw.json，并在打开控制台时使用。",
    "install.config.whyToken": "为什么需要认证 Token？",
    "install.config.whyTokenDetail": "认证 Token 用于保护你的本地 Gateway，避免未经授权的访问。",
    "install.complete.title": "安装完成！",
    "install.complete.subtitle": "OpenClaw 已准备就绪。",
    "install.complete.configuration": "配置",
    "install.complete.gatewayStarting": "正在启动 OpenClaw Gateway 服务...",
    "install.complete.gatewayStarted": "OpenClaw Gateway 已启动",
    "install.complete.gatewayFailed": "Gateway 启动失败",
    "install.progress.checkingEnvironment": "正在检查系统环境...",
    "install.progress.analyzingRequirements": "正在分析需求...",
    "install.progress.systemRequirementsNotMet": "系统要求未满足：\n%@",
    "install.progress.nodeRequired": "需要安装 Node.js",
    "install.progress.nodeUpgradeRequired": "需要升级 Node.js",
    "install.progress.nodeAlreadyInstalled": "Node.js 已安装",
    "install.progress.openClawAlreadyInstalled": "OpenClaw 已安装",
    "install.progress.openClawRequired": "需要安装 OpenClaw",
    "install.progress.startingNode": "正在开始安装 Node.js...",
    "install.progress.nodeSuccess": "Node.js 安装成功",
    "install.progress.nodeFailed": "Node.js 安装失败：%@",
    "install.progress.startingOpenClaw": "正在开始安装 OpenClaw...",
    "install.progress.openClawSuccess": "OpenClaw 安装成功",
    "install.progress.openClawFailed": "OpenClaw 安装失败：%@",
    "install.progress.savingConfig": "正在保存 Gateway 配置...",
    "install.progress.configSaved": "配置已保存",
    "install.progress.configSaveFailed": "保存配置失败：%@",
    "install.node.status.detectingRegion": "正在检测地区...",
    "install.node.region.china": "中国",
    "install.node.region.international": "国际",
    "install.node.mirror.china": "国内镜像",
    "install.node.mirror.official": "官方镜像",
    "install.node.status.regionDetected": "检测到地区：%@。正在获取最新 Node.js 版本...",
    "install.node.status.latestLTS": "最新 LTS 版本：%@",
    "install.node.status.downloadingFrom": "正在下载 Node.js %@（来源：%@）...",
    "install.node.status.downloadComplete": "下载完成",
    "install.node.status.downloadingPercent": "正在下载... %lld%%",
    "install.node.status.verifyingDownload": "正在校验下载完整性...",
    "install.node.status.preparingExtract": "正在准备解压 Node.js...",
    "install.node.status.extracting": "正在解压 Node.js（可能需要一点时间）...",
    "install.node.status.extractingPercent": "正在解压 Node.js... %lld%%",
    "install.node.status.verifyingBinaries": "正在校验解压后的二进制文件...",
    "install.node.status.complete": "安装完成",
    "install.node.status.installing": "正在安装 Node.js...",
    "install.node.status.verifyingInstallation": "正在验证安装...",
    "install.node.status.installedAt": "Node.js %@ 已安装到 %@",
    "install.node.status.usingBundled": "正在使用内置 Node.js %@...",
    "install.node.status.bundledMissing": "未找到内置 Node.js，正在下载...",
    "install.node.status.success": "Node.js 安装成功！",
    "install.node.status.cancelled": "下载已取消",
    "install.openclaw.status.installingBundled": "正在从内置包安装 OpenClaw...",
    "install.openclaw.status.extracting": "正在解压 OpenClaw...",
    "install.openclaw.status.extractingPercent": "正在解压 OpenClaw... %lld%%",
    "install.openclaw.status.removingQuarantine": "正在移除隔离属性...",
    "install.openclaw.status.settingUpBinary": "正在设置 OpenClaw 二进制文件...",
    "install.openclaw.status.complete": "安装完成！",
    "install.openclaw.status.configuring": "正在配置 OpenClaw...",
    "install.openclaw.status.configured": "OpenClaw 配置成功",
    "install.openclaw.status.verifying": "正在验证安装...",
    "install.openclaw.status.verifiedAt": "OpenClaw %@ 已在 %@ 验证",
    "install.openclaw.status.installedAt": "OpenClaw 已安装到 %@",
    "menu.status.uptime": "运行时长：",
    "menu.status.openDashboard": "打开控制台",
    "menu.status.startService": "启动服务",
    "menu.status.stopService": "停止服务",
    "menu.status.statusLine": "状态：%@",
    "menu.status.restartService": "重启",
    "menu.status.checkUpdates": "检查更新",
    "menu.status.showMainWindow": "显示主窗口",
    "menu.status.quitInstaller": "退出 OpenClaw 安装器",
    "menu.status.helperVersion": "OpenClaw Helper v%@（%@）",
    "menu.status.serviceVersion": "OpenClaw 服务 %@",
    "help.status.online": "在线",
    "help.status.offline": "离线",
    "help.welcome.title": "你好，我是 GetClawHub 助手",
    "help.welcome.subtitle": "可以询问任何关于 GetClowHub 使用的问题。",
    "help.status.typing": "正在输入...",
    "help.status.offlineFaq": "离线模式，仅使用 FAQ 回答",
    "help.input.placeholder": "输入问题...",
    "help.quick.status.start": "服务启动不了怎么办？",
    "help.quick.status.restart": "如何重启服务？",
    "help.quick.status.systemInfo": "如何查看系统信息？",
    "help.quick.config.models": "如何配置模型？",
    "help.quick.config.port": "如何修改端口？",
    "help.quick.config.provider": "Provider 怎么切换？",
    "help.quick.chat.slash": "如何使用斜杠命令？",
    "help.quick.chat.switchAssistant": "如何切换 AI 助手？",
    "help.quick.chat.history": "历史消息怎么查看？",
    "help.quick.cron.create": "如何创建定时任务？",
    "help.quick.cron.expression": "Cron 表达式怎么写？",
    "help.quick.cron.pause": "如何暂停任务？",
    "help.quick.persona.edit": "如何编辑 AI 性格？",
    "help.quick.persona.files": "四个文件分别是什么？",
    "help.quick.persona.preview": "如何预览效果？",
    "help.quick.subAgents.create": "如何创建子代理？",
    "help.quick.subAgents.switch": "如何在 Chat 中切换 AI？",
    "help.quick.subAgents.delete": "如何删除子代理？",
    "help.quick.skills.install": "如何安装新技能？",
    "help.quick.skills.status": "技能状态含义？",
    "help.quick.skills.findMore": "去哪找更多技能？",
    "help.quick.models.default": "如何设置默认模型？",
    "help.quick.models.fallback": "什么是 Fallback？",
    "help.quick.models.image": "如何添加图像模型？",
    "help.quick.channels.telegram": "如何连接 Telegram？",
    "help.quick.channels.status": "渠道状态灯含义？",
    "help.quick.channels.remove": "如何删除渠道？",
    "help.quick.plugins.enable": "如何启用插件？",
    "help.quick.plugins.available": "有哪些可用插件？",
    "help.quick.plugins.status": "插件状态含义？",
    "help.quick.logs.search": "如何搜索日志？",
    "help.quick.logs.colors": "日志颜色含义？",
    "help.quick.logs.export": "如何导出日志？",
    "help.quick.budget.set": "如何设置预算？",
    "help.quick.budget.alerts": "预算告警怎么用？",
    "help.quick.budget.costs": "如何查看费用？",
    "help.quick.billing.view": "如何查看账单？",
    "help.quick.billing.limit": "Key 的消费额度是多少？",
    "help.quick.billing.reset": "账单多久重置？",
    "help.quick.market.install": "如何安装智能体？",
    "help.quick.market.contents": "市场里都有什么？",
    "help.quick.market.uninstall": "如何卸载智能体？",
    "help.quick.tasks.create": "如何创建定时任务？",
    "help.quick.tasks.pause": "如何暂停自动化？",
    "help.quick.tasks.edit": "如何编辑自动化？",
    "help.quick.outputs.what": "Outputs 里显示什么？",
    "help.quick.outputs.hidden": "为什么看不到配置文件？",
    "help.quick.outputs.open": "如何打开生成文件？",
    "subAgents.title": "多 Agent",
    "subAgents.count.agents": "（%lld 个 Agent）",
    "subAgents.action.new": "新建 Agent",
    "subAgents.action.openWorkspace": "打开工作区",
    "subAgents.loading.agents": "正在加载 Agent...",
    "subAgents.loading.models": "正在加载模型...",
    "subAgents.empty.title": "暂无 Agent",
    "subAgents.empty.detail": "创建一个 Agent 来专门处理不同任务",
    "subAgents.toast.fileSaved": "%@ %@ 已保存",
    "subAgents.toast.deleted": "Agent“%@”已删除",
    "subAgents.toast.modelChanged": "%@ 模型 → %@",
    "subAgents.alert.deleteTitle": "删除 Agent",
    "subAgents.alert.deleteMessage": "删除“%@”？这会移除该 Agent 及其工作区。",
    "subAgents.model.label": "模型：",
    "subAgents.model.default": "默认",
    "subAgents.model.defaultInherit": "默认（继承）",
    "subAgents.model.defaultFromConfig": "默认（继承配置）",
    "subAgents.model.defaultTag": "（默认）",
    "subAgents.create.title": "新建 Agent",
    "subAgents.create.agentId": "Agent ID",
    "subAgents.create.agentIdPlaceholder": "例如 news-helper",
    "subAgents.create.agentIdHelp": "只能使用小写字母、数字和连字符",
    "subAgents.create.displayName": "显示名称",
    "subAgents.create.displayNamePlaceholder": "例如 News Helper",
    "subAgents.create.displayNameHelp": "可选。会作为 Agent 名称写入 IDENTITY.md",
    "subAgents.create.model": "模型",
    "subAgents.create.division": "分组",
    "subAgents.create.divisionHelp": "用于侧边栏分组的 Agent 类别",
    "collab.title": "协作任务",
    "collab.empty.title": "暂无协作任务",
    "collab.empty.detail": "在聊天中输入 /collab，或选择 Commander 发送任务",
    "collab.history.help": "协作历史（%lld）",
    "collab.history.title": "历史",
    "collab.history.records": "%lld 条记录",
    "collab.history.subtasks": "%lld/%lld 个子任务",
    "collab.commander.settings": "Commander 设置",
    "collab.panel.collapse": "收起面板",
    "collab.panel.close": "关闭面板",
    "collab.progress.label": "进度：%@",
    "collab.phase.understanding": "正在理解需求...",
    "collab.phase.researching": "正在调研...",
    "collab.phase.decomposing": "正在拆解...",
    "collab.phase.awaitingApproval": "等待确认",
    "collab.phase.running": "运行中...",
    "collab.phase.verifying": "正在验证...",
    "collab.phase.summarizing": "正在总结...",
    "collab.phase.done": "已完成",
    "collab.phase.runningPlain": "运行中",
    "collab.phase.verifyingPlain": "验证中",
    "collab.phase.summarizingPlain": "总结中",
    "collab.phase.preparing": "准备中",
    "collab.requirements.gathering": "需求收集",
    "collab.final.summary": "最终总结",
    "collab.settings.agentTimeout": "Agent 超时",
    "collab.settings.custom": "自定义",
    "collab.settings.hours": "小时",
    "collab.settings.timeoutHelp": "每个子任务最长执行时间（当前：%@）",
    "collab.settings.maxConcurrency": "最大并发",
    "collab.settings.unlimited": "不限",
    "collab.settings.maxConcurrencyHelp": "最多同时执行的子任务数（0 = 不限）",
    "collab.settings.retryContextLength": "重试上下文长度",
    "collab.settings.chars": "字符",
    "collab.settings.retryContextHelp": "重试时传给 Agent 的历史长度",
    "collab.settings.resetDefaults": "重置默认值",
    "collab.action.cancelAll": "全部取消",
    "collab.task.retry": "重试此任务",
    "collab.task.forceComplete": "标记为完成（解除下游阻塞）",
    "collab.task.skip": "跳过此任务",
    "collab.task.dependsOn": "依赖：#%@",
    "collab.task.error": "错误：%@",
    "collab.process.running": "进程运行中",
    "collab.process.ended": "进程已结束",
    "collab.process.lines": "%lld 行",
    "collab.process.files": "%lld 个文件",
    "collab.process.longRunning": "运行时间较长",
    "collab.output.files": "输出文件：",
    "collab.agent.running": "Agent 运行中...",
    "catalog.action.install": "安装",
    "catalog.action.installing": "安装中...",
    "catalog.action.uninstall": "卸载",
    "catalog.action.remove": "移除",
    "catalog.action.removing": "移除中...",
    "catalog.action.cancel": "取消",
    "catalog.action.close": "关闭",
    "catalog.action.refresh": "刷新",
    "catalog.action.update": "更新",
    "catalog.action.upgrade": "升级",
    "catalog.action.upgrading": "升级中...",
    "catalog.action.enable": "启用",
    "catalog.action.disable": "停用",
    "catalog.status.installed": "已安装",
    "catalog.status.notInstalled": "未安装",
    "catalog.status.ready": "就绪",
    "catalog.status.missing": "缺少依赖",
    "catalog.status.loaded": "已加载",
    "catalog.status.disabled": "已停用",
    "catalog.status.unavailable": "不可用",
    "catalog.status.updateAvailable": "有更新",
    "catalog.section.recommend": "推荐",
    "catalog.section.catalog": "目录",
    "catalog.section.all": "全部",
    "catalog.section.installed": "已安装",
    "catalog.section.builtIn": "内置",
    "catalog.section.custom": "自定义",
    "catalog.detail.description": "描述",
    "catalog.count.installed": "已安装 %lld 个",
    "dashboard.count.configured": "（已配置 %lld 个）",
    "dashboard.status.port": "端口",
    "dashboard.status.uptime": "运行时长",
    "dashboard.status.version": "版本",
    "dashboard.status.service.running": "运行中",
    "dashboard.status.service.stopped": "已停止",
    "dashboard.status.service.starting": "启动中",
    "dashboard.status.service.stopping": "停止中",
    "dashboard.status.service.error": "错误",
    "dashboard.status.service.unknown": "未知",
    "dashboard.status.agentSessions": "Agent 会话",
    "dashboard.status.totalAgents": "共 %lld 个 Agent",
    "dashboard.status.noSessions": "暂无会话",
    "dashboard.status.cronHealth": "定时任务健康",
    "dashboard.status.total": "总数：%lld",
    "dashboard.status.active": "启用：%lld",
    "dashboard.status.next": "下次：%@",
    "dashboard.status.disabledParen": "（已停用）",
    "dashboard.status.channelsCount": "%lld 个频道",
    "dashboard.status.tokenUsage": "Token 用量",
    "dashboard.status.tokenTotal": "总计：",
    "dashboard.status.noTokenData": "暂无 token 数据",
    "dashboard.status.systemInformation": "系统信息",
    "dashboard.status.macosVersion": "macOS 版本",
    "dashboard.status.architecture": "架构",
    "dashboard.status.availableSpace": "可用空间",
    "dashboard.status.openClawPath": "OpenClaw 路径",
    "dashboard.status.label.budget": "预算：",
    "dashboard.status.label.cost": "费用：",
    "dashboard.status.label.estimatedCost": "预估费用：",
    "dashboard.service.toast.started": "服务已启动",
    "dashboard.service.toast.startFailed": "启动服务失败：%@",
    "dashboard.service.toast.stopped": "服务已停止",
    "dashboard.service.toast.stopFailed": "停止服务失败：%@",
    "dashboard.service.toast.restarted": "服务已重启",
    "dashboard.service.toast.restartFailed": "重启服务失败：%@",
    "dashboard.config.error.invalidPort": "端口号无效，必须在 1 到 65535 之间",
    "dashboard.config.toast.saved": "配置已保存到 openclaw.json",
    "dashboard.config.error.saveFailed": "保存配置文件失败",
    "dashboard.alert.error": "错误",
    "dashboard.agent.remove.title": "移除 Agent",
    "dashboard.agent.remove.message": "确定要移除“%@”吗？这会删除该 Agent 及其工作区。",
    "dashboard.agent.addWorkFolder": "添加工作文件夹...",
    "dashboard.agent.fallbackDescription": "通用助手",
    "dashboard.model.label": "模型",
    "dashboard.model.defaultInherit": "默认（继承）",
    "dashboard.model.defaultWithValue": "默认（%@）",
    "dashboard.chat.viewResult": "查看结果 ↑",
    "dashboard.chat.moveToBackground": "转到后台",
    "dashboard.chat.clearConversation": "清空会话",
    "dashboard.chat.modelSwitchFailedNotSent": "无法切换到选中的模型，因此消息未发送。",
    "dashboard.diagnostics.title": "诊断报告",
    "dashboard.outputs.title": "输出",
    "dashboard.outputs.empty": "暂无输出",
    "dashboard.terminal.title": "终端",
    "dashboard.activity.empty": "暂无活动",
    "dashboard.tooltip.chooseModel": "选择模型",
    "dashboard.tooltip.attachFile": "附加文件",
    "dashboard.tooltip.searchChats": "搜索会话",
    "dashboard.tooltip.taskRunning": "任务运行中",
    "dashboard.tooltip.hideTerminal": "隐藏终端",
    "dashboard.tooltip.showTerminal": "显示终端",
    "dashboard.tooltip.hideOutputs": "隐藏输出",
    "dashboard.tooltip.showOutputs": "显示输出",
    "dashboard.tooltip.confirmAndSend": "确认并发送",
    "dashboard.tooltip.removeAttachment": "移除附件",
    "dashboard.tooltip.openOutputsFolder": "打开输出文件夹",
    "dashboard.tooltip.clearConversation": "清空会话",
    "dashboard.tooltip.collapseSessionDetails": "收起会话详情",
    "dashboard.tooltip.expandSessionDetails": "展开会话详情",
    "dashboard.tooltip.editAgent": "编辑 Agent",
    "dashboard.session.action.rename": "重命名",
    "dashboard.session.action.pin": "置顶",
    "dashboard.session.action.unpin": "取消置顶",
    "dashboard.session.action.export": "导出…",
    "dashboard.session.action.archive": "归档",
    "dashboard.session.action.confirmDelete": "确认删除",
    "dashboard.session.newChat": "新会话",
    "dashboard.sidebar.pinned": "已置顶",
    "dashboard.skills.title": "技能",
    "dashboard.skills.enabledCount": "%lld / %lld 已启用",
    "dashboard.skills.loading": "加载中…",
    "dashboard.skills.empty": "未检测到技能",
    "dashboard.skills.viewAll": "查看全部（%lld）",
    "dashboard.composer.mode.label": "模式：",
    "dashboard.composer.mode.chat": "聊天",
    "dashboard.composer.mode.task": "执行任务",
    "dashboard.composer.mode.code": "代码模式",
    "dashboard.channels.title": "频道",
    "dashboard.channels.add": "添加频道",
    "dashboard.channels.loading": "正在加载频道...",
    "dashboard.channels.empty.title": "暂无已配置频道",
    "dashboard.channels.empty.detail": "添加一个频道开始使用",
    "dashboard.channels.status.configured": "已配置",
    "dashboard.channels.status.notConfigured": "未配置",
    "dashboard.channels.status.linked": "已连接",
    "dashboard.channels.status.notLinked": "未连接",
    "dashboard.channels.status.connected": "已连接",
    "dashboard.channels.alert.removeTitle": "移除频道",
    "dashboard.channels.alert.removeMessage": "确定要移除 %@ 频道吗？这会删除它的配置。",
    "dashboard.channels.sheet.channelType": "频道类型",
    "dashboard.channels.sheet.pluginMissing": "%@ 插件尚未安装，请先安装插件。",
    "dashboard.channels.sheet.qr.startHelp": "点击下方按钮开始微信扫码登录",
    "dashboard.channels.sheet.qr.start": "开始扫码登录",
    "dashboard.channels.sheet.qr.scan": "使用微信扫码连接",
    "dashboard.channels.sheet.qr.waiting": "正在等待扫码...",
    "dashboard.channels.sheet.qr.generating": "正在生成二维码...",
    "dashboard.channels.sheet.qr.success": "微信连接成功！",
    "dashboard.channels.sheet.done": "完成",
    "dashboard.channels.sheet.accountId": "账号 ID",
    "dashboard.channels.sheet.accountHelp": "主账号可使用 default，也可以输入其他 ID 为同一频道添加多个账号。",
    "dashboard.channels.sheet.displayName": "显示名称",
    "dashboard.channels.sheet.optional": "可选",
    "dashboard.channels.sheet.appKey": "App Key",
    "dashboard.channels.sheet.enterAppKey": "输入 App Key",
    "dashboard.channels.sheet.appSecret": "App Secret",
    "dashboard.channels.sheet.enterAppSecret": "输入 App Secret",
    "dashboard.channels.sheet.dingtalkHelp": "前往钉钉开放平台创建应用，并获取 App Key 和 App Secret。",
    "dashboard.channels.sheet.feishuHelp": "前往飞书开放平台创建应用，并获取 App ID 和 App Secret。",
    "dashboard.channels.sheet.token": "Token",
    "dashboard.channels.sheet.enterToken": "输入机器人 token 或 API key",
    "dashboard.channels.sheet.tokenHelp": "Telegram/Discord 使用机器人 token，Slack 使用 bot token（xoxb-...）。其他频道可能需要不同凭证。",
    "dashboard.channels.sheet.cliHelp": "Slack、Matrix 等复杂频道可使用命令行配置：",
    "dashboard.channels.toast.addFailed": "添加 %@ %@ 失败：%@",
    "dashboard.channels.toast.added": "%@ %@ 频道已添加",
    "dashboard.channels.toast.readConfigFailed": "读取 openclaw.json 失败",
    "dashboard.channels.toast.removeFailed": "移除 %@ 失败：%@",
    "dashboard.channels.toast.removed": "%@ 频道已移除",
    "dashboard.cron.title": "定时任务",
    "dashboard.cron.add": "添加任务",
    "dashboard.cron.refreshing": "正在刷新...",
    "dashboard.cron.loadFailed.title": "无法加载定时任务",
    "dashboard.cron.checking.title": "正在检查定时任务",
    "dashboard.cron.checking.detail": "正在读取计划自动化任务...",
    "dashboard.cron.empty.title": "暂无已配置定时任务",
    "dashboard.cron.empty.detail": "添加定时任务来安排自动化操作",
    "dashboard.cron.agentTag": "Agent：%@",
    "dashboard.cron.next": "下次：%@",
    "dashboard.cron.last": "上次：%@",
    "dashboard.cron.alert.removeTitle": "移除定时任务",
    "dashboard.cron.alert.removeMessage": "确定要移除定时任务“%@”吗？此操作无法撤销。",
    "dashboard.cron.sheet.title": "添加定时任务",
    "dashboard.cron.sheet.name": "名称",
    "dashboard.cron.sheet.namePlaceholder": "例如 daily-report",
    "dashboard.cron.sheet.expression": "Cron 表达式",
    "dashboard.cron.sheet.expressionPlaceholder": "例如 0 9 * * *",
    "dashboard.cron.sheet.expressionHelp": "格式：分钟 小时 日 月 星期（例如 “0 9 * * *” = 每天上午 9:00）",
    "dashboard.cron.sheet.timezone": "时区",
    "dashboard.cron.sheet.timezonePlaceholder": "例如 Asia/Shanghai",
    "dashboard.cron.sheet.agent": "Agent",
    "dashboard.cron.sheet.sessionTarget": "会话目标",
    "dashboard.cron.sheet.session.isolated": "隔离",
    "dashboard.cron.sheet.session.main": "主会话",
    "dashboard.cron.sheet.sessionHelp": "隔离：每次运行使用独立会话。主会话：复用主会话。",
    "dashboard.cron.sheet.message": "消息",
    "dashboard.cron.sheet.messagePlaceholder": "定时任务触发时要发送的消息/指令...",
    "dashboard.cron.toast.addFailed": "添加定时任务失败：%@",
    "dashboard.cron.toast.created": "定时任务“%@”已创建",
    "dashboard.cron.toast.enableFailed": "启用定时任务失败：%@",
    "dashboard.cron.toast.enabled": "定时任务“%@”已启用",
    "dashboard.cron.toast.disableFailed": "停用定时任务失败：%@",
    "dashboard.cron.toast.disabled": "定时任务“%@”已停用",
    "dashboard.cron.toast.removeFailed": "移除定时任务失败：%@",
    "dashboard.cron.toast.removed": "定时任务“%@”已移除",
    "dashboard.cron.toast.runFailed": "运行定时任务失败：%@",
    "dashboard.cron.toast.triggered": "定时任务“%@”已触发",
    "dashboard.models.title": "模型",
    "dashboard.models.loading": "正在加载模型...",
    "dashboard.models.empty": "暂无已配置模型",
    "dashboard.models.cliHint": "别名和认证配置请使用：",
    "dashboard.models.default": "默认",
    "dashboard.models.imageModel": "图像模型",
    "dashboard.models.notSet": "未设置",
    "dashboard.models.fallbacks": "回退",
    "dashboard.models.imageFallbacks": "图像回退",
    "dashboard.models.none": "无",
    "dashboard.models.fallbackModels": "回退模型",
    "dashboard.models.imageFallbackModels": "图像回退模型",
    "dashboard.models.badge.default": "默认",
    "dashboard.models.badge.image": "图像",
    "dashboard.models.badge.fallback": "回退",
    "dashboard.models.badge.imageFallback": "图像回退",
    "dashboard.models.local": "本地",
    "dashboard.models.auth": "已认证",
    "dashboard.models.action.setImage": "设为图像",
    "dashboard.models.action.setImageFallback": "设为图像回退",
    "dashboard.models.action.fallback": "回退",
    "dashboard.models.action.setFallback": "设为回退",
    "dashboard.models.action.setDefault": "设为默认",
    "dashboard.models.toast.setDefaultFailed": "设置默认模型失败：%@",
    "dashboard.models.toast.defaultSet": "默认模型已设为 %@",
    "dashboard.models.toast.setImageFailed": "设置图像模型失败：%@",
    "dashboard.models.toast.imageSet": "图像模型已设为 %@",
    "dashboard.models.toast.addFallbackFailed": "添加回退模型失败：%@",
    "dashboard.models.toast.fallbackAdded": "%@ 已添加到回退模型",
    "dashboard.models.toast.removeFallbackFailed": "移除回退模型失败：%@",
    "dashboard.models.toast.fallbackRemoved": "%@ 已从回退模型移除",
    "dashboard.models.toast.addImageFallbackFailed": "添加图像回退模型失败：%@",
    "dashboard.models.toast.imageFallbackAdded": "%@ 已添加到图像回退模型",
    "dashboard.models.toast.removeImageFallbackFailed": "移除图像回退模型失败：%@",
    "dashboard.models.toast.imageFallbackRemoved": "%@ 已从图像回退模型移除",
    "dashboard.logs.searchPlaceholder": "搜索日志...",
    "dashboard.logs.auto": "自动",
    "dashboard.logs.export": "导出",
    "dashboard.logs.openFile": "打开文件",
    "dashboard.logs.empty.title": "暂无日志",
    "dashboard.logs.empty.detail": "网关服务运行后日志会显示在这里",
    "dashboard.logs.toast.exported": "日志已导出",
    "dashboard.logs.toast.cleared": "日志已清空",
    "workspace.outputs.title": "输出",
    "workspace.outputs.openInFinder": "在 Finder 中打开",
    "workspace.outputs.hideProjectFiles": "隐藏项目文件",
    "workspace.outputs.showProjectFiles": "显示项目文件",
    "workspace.outputs.empty": "暂无输出",
    "workspace.files.filterPlaceholder": "过滤文件...",
    "workspace.files.empty": "暂无文件",
    "workspace.files.noMatches": "没有匹配的文件",
    "workspace.files.fallbackPath": "回退：%@",
    "workspace.files.newFile": "新建文件",
    "workspace.files.newFolder": "新建文件夹",
    "workspace.files.cut": "剪切",
    "workspace.files.copy": "复制",
    "workspace.files.paste": "粘贴",
    "workspace.files.deleteConfirm": "确定要删除“%@”吗？",
    "workspace.files.pathCopied": "路径已复制",
    "workspace.files.copyPathHelp": "双击复制路径",
    "workspace.files.decreaseFont": "减小字体（⌘-）",
    "workspace.files.increaseFont": "增大字体（⌘+）",
    "workspace.files.disableWordWrap": "关闭自动换行",
    "workspace.files.enableWordWrap": "启用自动换行",
    "workspace.files.fullscreen": "全屏",
    "workspace.files.exitFullscreen": "退出全屏",
    "workspace.files.position": "第 %lld 行，第 %lld 列",
    "workspace.project.newChat": "在项目中新建会话",
    "workspace.project.revealInFinder": "在 Finder 中显示",
    "workspace.project.removeFromAgent": "从 Agent 移除",
    "error.report.action": "报告问题",
    "error.report.title": "错误报告已复制",
    "error.report.message": "错误详情已复制到剪贴板。报告问题时请粘贴这些内容。",
    "error.report.contentTitle": "错误报告",
    "error.report.contentSystemInfo": "系统信息：",
    "error.report.contentPleaseReport": "请将此问题报告给开发者。"
}

COMMON_ZH_HANT = {
    "common.error.unknown": "未知錯誤",
    "common.value.unknown": "未知",
    "common.action.add": "新增",
    "common.action.cancel": "取消",
    "common.action.copy": "複製",
    "common.action.delete": "刪除",
    "common.action.edit": "編輯",
    "common.action.ok": "確定",
    "common.action.paste": "貼上",
    "common.action.preview": "預覽",
    "common.action.refresh": "重新整理",
    "common.action.remove": "移除",
    "common.action.rename": "重新命名",
    "common.action.retry": "重試",
    "common.action.create": "建立",
    "common.action.save": "儲存",
    "common.action.send": "傳送",
    "common.action.start": "啟動",
    "common.action.stop": "停止",
    "common.action.restart": "重新啟動",
    "common.toast.copied": "已複製",
    "common.empty.parenthesized": "（空）",
    "app.update.currentVersion": "GetClawHub v%@",
    "app.update.toVersion": "更新到 v%@",
    "app.update.installLatest": "安裝最新應用程式更新",
    "app.update.upToDate": "已是最新版本",
    "app.update.check": "檢查更新",
    "app.update.lookForLatest": "檢查最新的 GetClawHub 版本",
    "billing.loginRequired": "請先登入後查看帳單。",
    "billing.unavailable": "目前建置不包含帳單功能。",
    "installer.environment.title": "環境檢查",
    "installer.environment.checking": "正在檢查系統環境...",
    "installer.environment.operatingSystem": "作業系統",
    "installer.environment.architecture": "架構",
    "installer.environment.diskSpace": "可用磁碟空間",
    "installer.environment.nodeWillUseBundled": "%@（將使用內建 %@）",
    "installer.environment.nodeWillInstallBundled": "未安裝（將自動安裝內建 %@）",
    "installer.environment.nodeBundledNote": "OpenClaw 自帶獨立的 Node.js %@ 執行階段，無需系統 Node 即可執行。",
    "installer.environment.openClawNotInstalled": "未安裝",
    "installer.environment.issuesFound": "發現問題：",
    "legacy.installer.title": "OpenClaw 安裝器",
    "legacy.installer.subtitleMacOS": "適用於 macOS",
    "legacy.installer.checkingEnvironment": "正在檢查環境...",
    "legacy.installer.systemInformation": "系統資訊",
    "legacy.installer.checkEnvironment": "檢查環境",
    "legacy.installer.startInstallation": "開始安裝",
    "legacy.installer.adminPrivileges": "管理員權限",
    "legacy.installer.granted": "已授予",
    "legacy.installer.notGranted": "未授予",
    "legacy.installer.notDetected": "未偵測到",
    "install.status.uninstalling": "正在解除安裝 OpenClaw...",
    "install.status.uninstallComplete": "解除安裝完成",
    "install.status.dataPreserved": "設定和登入資料已保留，重新安裝後可還原。",
    "install.status.openclawInstalled": "OpenClaw 已安裝",
    "install.status.readyToInstall": "可以安裝 OpenClaw",
    "install.status.installed": "已安裝",
    "install.status.completed": "已完成",
    "install.status.starting": "啟動中",
    "install.action.start": "開始安裝",
    "install.action.openDashboard": "開啟控制台",
    "install.action.uninstall": "解除安裝",
    "install.action.quit": "結束",
    "install.action.getStarted": "開始",
    "install.action.generate": "產生",
    "install.action.continue": "繼續",
    "install.action.retryStart": "重試啟動",
    "install.action.goToManagement": "進入管理",
    "install.alert.uninstallTitle": "解除安裝 OpenClaw？",
    "install.alert.uninstallMessage": "這將移除 OpenClaw、Node.js 執行階段和日誌檔案。\n設定和登入資料會被保留。",
    "install.welcome.title": "歡迎使用 OpenClaw 安裝器",
    "install.welcome.subtitle": "此精靈會在你的 Mac 上安裝並設定 OpenClaw。",
    "install.welcome.feature.automated.title": "自動化安裝",
    "install.welcome.feature.automated.description": "自動檢查環境並安裝所需元件。",
    "install.welcome.feature.configuration.title": "輕鬆設定",
    "install.welcome.feature.configuration.description": "在一個流程中設定 Gateway Token 和本機設定。",
    "install.welcome.feature.secure.title": "安全",
    "install.welcome.feature.secure.description": "使用認證 Token 保護本機 Gateway 存取。",
    "install.welcome.feature.quick.title": "快速設定",
    "install.welcome.feature.quick.description": "幾分鐘內完成安裝。",
    "install.node.title": "Node.js 安裝",
    "install.node.installingNode": "正在安裝 Node.js",
    "install.node.solution.internet": "檢查網路連線後重試。",
    "install.node.solution.disk": "確認有足夠的磁碟空間。",
    "install.node.solution.vpn": "如果下載失敗，請嘗試切換網路或 VPN。",
    "install.node.success": "Node.js 安裝成功",
    "install.node.ready": "就緒",
    "install.openclaw.title": "OpenClaw 安裝",
    "install.openclaw.installing": "正在安裝 OpenClaw",
    "install.openclaw.solution.node": "確認 Node.js 已成功安裝。",
    "install.openclaw.solution.npm": "檢查 npm 存取和套件可用性。",
    "install.openclaw.solution.network": "檢查網路連線。",
    "install.openclaw.solution.log": "查看安裝日誌取得詳細資訊。",
    "install.openclaw.success": "OpenClaw 安裝成功",
    "install.openclaw.readyForConfig": "可以進行設定",
    "install.openclaw.configHelp": "繼續設定本機 Gateway。",
    "install.shared.log": "安裝日誌",
    "install.shared.progress": "進度",
    "install.shared.failed": "安裝失敗",
    "install.shared.errorDetails": "錯誤詳情：",
    "install.shared.possibleSolutions": "可能的解決方案：",
    "install.shared.solution.retry": "修復問題後重試。",
    "install.shared.version": "版本：",
    "install.shared.location": "位置：",
    "install.shared.status": "狀態：",
    "install.config.title": "Gateway 設定",
    "install.config.subtitle": "設定本機 OpenClaw Gateway。",
    "install.config.authToken": "Gateway 認證 Token",
    "install.config.tokenPlaceholder": "輸入 Gateway 認證 Token",
    "install.config.tokenHelp": "此 Token 會儲存到 ~/.openclaw/openclaw.json，並在開啟控制台時使用。",
    "install.config.whyToken": "為什麼需要認證 Token？",
    "install.config.whyTokenDetail": "認證 Token 用於保護你的本機 Gateway，避免未授權存取。",
    "install.complete.title": "安裝完成！",
    "install.complete.subtitle": "OpenClaw 已準備就緒。",
    "install.complete.configuration": "設定",
    "install.complete.gatewayStarting": "正在啟動 OpenClaw Gateway 服務...",
    "install.complete.gatewayStarted": "OpenClaw Gateway 已啟動",
    "install.complete.gatewayFailed": "Gateway 啟動失敗",
    "install.progress.checkingEnvironment": "正在檢查系統環境...",
    "install.progress.analyzingRequirements": "正在分析需求...",
    "install.progress.systemRequirementsNotMet": "系統要求未滿足：\n%@",
    "install.progress.nodeRequired": "需要安裝 Node.js",
    "install.progress.nodeUpgradeRequired": "需要升級 Node.js",
    "install.progress.nodeAlreadyInstalled": "Node.js 已安裝",
    "install.progress.openClawAlreadyInstalled": "OpenClaw 已安裝",
    "install.progress.openClawRequired": "需要安裝 OpenClaw",
    "install.progress.startingNode": "正在開始安裝 Node.js...",
    "install.progress.nodeSuccess": "Node.js 安裝成功",
    "install.progress.nodeFailed": "Node.js 安裝失敗：%@",
    "install.progress.startingOpenClaw": "正在開始安裝 OpenClaw...",
    "install.progress.openClawSuccess": "OpenClaw 安裝成功",
    "install.progress.openClawFailed": "OpenClaw 安裝失敗：%@",
    "install.progress.savingConfig": "正在儲存 Gateway 設定...",
    "install.progress.configSaved": "設定已儲存",
    "install.progress.configSaveFailed": "儲存設定失敗：%@",
    "install.node.status.detectingRegion": "正在偵測地區...",
    "install.node.region.china": "中國",
    "install.node.region.international": "國際",
    "install.node.mirror.china": "國內鏡像",
    "install.node.mirror.official": "官方鏡像",
    "install.node.status.regionDetected": "偵測到地區：%@。正在取得最新 Node.js 版本...",
    "install.node.status.latestLTS": "最新 LTS 版本：%@",
    "install.node.status.downloadingFrom": "正在下載 Node.js %@（來源：%@）...",
    "install.node.status.downloadComplete": "下載完成",
    "install.node.status.downloadingPercent": "正在下載... %lld%%",
    "install.node.status.verifyingDownload": "正在校驗下載完整性...",
    "install.node.status.preparingExtract": "正在準備解壓縮 Node.js...",
    "install.node.status.extracting": "正在解壓縮 Node.js（可能需要一點時間）...",
    "install.node.status.extractingPercent": "正在解壓縮 Node.js... %lld%%",
    "install.node.status.verifyingBinaries": "正在校驗解壓縮後的二進位檔案...",
    "install.node.status.complete": "安裝完成",
    "install.node.status.installing": "正在安裝 Node.js...",
    "install.node.status.verifyingInstallation": "正在驗證安裝...",
    "install.node.status.installedAt": "Node.js %@ 已安裝到 %@",
    "install.node.status.usingBundled": "正在使用內建 Node.js %@...",
    "install.node.status.bundledMissing": "未找到內建 Node.js，正在下載...",
    "install.node.status.success": "Node.js 安裝成功！",
    "install.node.status.cancelled": "下載已取消",
    "install.openclaw.status.installingBundled": "正在從內建套件安裝 OpenClaw...",
    "install.openclaw.status.extracting": "正在解壓縮 OpenClaw...",
    "install.openclaw.status.extractingPercent": "正在解壓縮 OpenClaw... %lld%%",
    "install.openclaw.status.removingQuarantine": "正在移除隔離屬性...",
    "install.openclaw.status.settingUpBinary": "正在設定 OpenClaw 二進位檔案...",
    "install.openclaw.status.complete": "安裝完成！",
    "install.openclaw.status.configuring": "正在設定 OpenClaw...",
    "install.openclaw.status.configured": "OpenClaw 設定成功",
    "install.openclaw.status.verifying": "正在驗證安裝...",
    "install.openclaw.status.verifiedAt": "OpenClaw %@ 已在 %@ 驗證",
    "install.openclaw.status.installedAt": "OpenClaw 已安裝到 %@",
    "menu.status.uptime": "執行時間：",
    "menu.status.openDashboard": "開啟控制台",
    "menu.status.startService": "啟動服務",
    "menu.status.stopService": "停止服務",
    "menu.status.statusLine": "狀態：%@",
    "menu.status.restartService": "重新啟動",
    "menu.status.checkUpdates": "檢查更新",
    "menu.status.showMainWindow": "顯示主視窗",
    "menu.status.quitInstaller": "結束 OpenClaw 安裝器",
    "menu.status.helperVersion": "OpenClaw Helper v%@（%@）",
    "menu.status.serviceVersion": "OpenClaw 服務 %@",
    "help.status.online": "線上",
    "help.status.offline": "離線",
    "help.welcome.title": "你好，我是 GetClawHub 助手",
    "help.welcome.subtitle": "可以詢問任何關於 GetClowHub 使用的問題。",
    "help.status.typing": "正在輸入...",
    "help.status.offlineFaq": "離線模式，僅使用 FAQ 回答",
    "help.input.placeholder": "輸入問題...",
    "help.quick.status.start": "服務啟動不了怎麼辦？",
    "help.quick.status.restart": "如何重新啟動服務？",
    "help.quick.status.systemInfo": "如何查看系統資訊？",
    "help.quick.config.models": "如何設定模型？",
    "help.quick.config.port": "如何修改連接埠？",
    "help.quick.config.provider": "Provider 怎麼切換？",
    "help.quick.chat.slash": "如何使用斜線命令？",
    "help.quick.chat.switchAssistant": "如何切換 AI 助手？",
    "help.quick.chat.history": "歷史訊息怎麼查看？",
    "help.quick.cron.create": "如何建立定時任務？",
    "help.quick.cron.expression": "Cron 表達式怎麼寫？",
    "help.quick.cron.pause": "如何暫停任務？",
    "help.quick.persona.edit": "如何編輯 AI 性格？",
    "help.quick.persona.files": "四個檔案分別是什麼？",
    "help.quick.persona.preview": "如何預覽效果？",
    "help.quick.subAgents.create": "如何建立子代理？",
    "help.quick.subAgents.switch": "如何在 Chat 中切換 AI？",
    "help.quick.subAgents.delete": "如何刪除子代理？",
    "help.quick.skills.install": "如何安裝新技能？",
    "help.quick.skills.status": "技能狀態含義？",
    "help.quick.skills.findMore": "去哪找更多技能？",
    "help.quick.models.default": "如何設定預設模型？",
    "help.quick.models.fallback": "什麼是 Fallback？",
    "help.quick.models.image": "如何新增圖像模型？",
    "help.quick.channels.telegram": "如何連接 Telegram？",
    "help.quick.channels.status": "頻道狀態燈含義？",
    "help.quick.channels.remove": "如何刪除頻道？",
    "help.quick.plugins.enable": "如何啟用外掛？",
    "help.quick.plugins.available": "有哪些可用外掛？",
    "help.quick.plugins.status": "外掛狀態含義？",
    "help.quick.logs.search": "如何搜尋日誌？",
    "help.quick.logs.colors": "日誌顏色含義？",
    "help.quick.logs.export": "如何匯出日誌？",
    "help.quick.budget.set": "如何設定預算？",
    "help.quick.budget.alerts": "預算告警怎麼用？",
    "help.quick.budget.costs": "如何查看費用？",
    "help.quick.billing.view": "如何查看帳單？",
    "help.quick.billing.limit": "Key 的消費額度是多少？",
    "help.quick.billing.reset": "帳單多久重置？",
    "help.quick.market.install": "如何安裝智能體？",
    "help.quick.market.contents": "市場裡都有什麼？",
    "help.quick.market.uninstall": "如何解除安裝智能體？",
    "help.quick.tasks.create": "如何建立定時任務？",
    "help.quick.tasks.pause": "如何暫停自動化？",
    "help.quick.tasks.edit": "如何編輯自動化？",
    "help.quick.outputs.what": "Outputs 裡顯示什麼？",
    "help.quick.outputs.hidden": "為什麼看不到設定檔？",
    "help.quick.outputs.open": "如何開啟生成檔案？",
    "subAgents.title": "多 Agent",
    "subAgents.count.agents": "（%lld 個 Agent）",
    "subAgents.action.new": "新增 Agent",
    "subAgents.action.openWorkspace": "開啟工作區",
    "subAgents.loading.agents": "正在載入 Agent...",
    "subAgents.loading.models": "正在載入模型...",
    "subAgents.empty.title": "暫無 Agent",
    "subAgents.empty.detail": "建立一個 Agent 來專門處理不同任務",
    "subAgents.toast.fileSaved": "%@ %@ 已儲存",
    "subAgents.toast.deleted": "Agent「%@」已刪除",
    "subAgents.toast.modelChanged": "%@ 模型 → %@",
    "subAgents.alert.deleteTitle": "刪除 Agent",
    "subAgents.alert.deleteMessage": "刪除「%@」？這會移除該 Agent 及其工作區。",
    "subAgents.model.label": "模型：",
    "subAgents.model.default": "預設",
    "subAgents.model.defaultInherit": "預設（繼承）",
    "subAgents.model.defaultFromConfig": "預設（繼承設定）",
    "subAgents.model.defaultTag": "（預設）",
    "subAgents.create.title": "新增 Agent",
    "subAgents.create.agentId": "Agent ID",
    "subAgents.create.agentIdPlaceholder": "例如 news-helper",
    "subAgents.create.agentIdHelp": "只能使用小寫字母、數字和連字號",
    "subAgents.create.displayName": "顯示名稱",
    "subAgents.create.displayNamePlaceholder": "例如 News Helper",
    "subAgents.create.displayNameHelp": "可選。會作為 Agent 名稱寫入 IDENTITY.md",
    "subAgents.create.model": "模型",
    "subAgents.create.division": "分組",
    "subAgents.create.divisionHelp": "用於側邊欄分組的 Agent 類別",
    "collab.title": "協作任務",
    "collab.empty.title": "暫無協作任務",
    "collab.empty.detail": "在聊天中輸入 /collab，或選擇 Commander 傳送任務",
    "collab.history.help": "協作歷史（%lld）",
    "collab.history.title": "歷史",
    "collab.history.records": "%lld 筆記錄",
    "collab.history.subtasks": "%lld/%lld 個子任務",
    "collab.commander.settings": "Commander 設定",
    "collab.panel.collapse": "收起面板",
    "collab.panel.close": "關閉面板",
    "collab.progress.label": "進度：%@",
    "collab.phase.understanding": "正在理解需求...",
    "collab.phase.researching": "正在調研...",
    "collab.phase.decomposing": "正在拆解...",
    "collab.phase.awaitingApproval": "等待確認",
    "collab.phase.running": "執行中...",
    "collab.phase.verifying": "正在驗證...",
    "collab.phase.summarizing": "正在總結...",
    "collab.phase.done": "已完成",
    "collab.phase.runningPlain": "執行中",
    "collab.phase.verifyingPlain": "驗證中",
    "collab.phase.summarizingPlain": "總結中",
    "collab.phase.preparing": "準備中",
    "collab.requirements.gathering": "需求收集",
    "collab.final.summary": "最終總結",
    "collab.settings.agentTimeout": "Agent 逾時",
    "collab.settings.custom": "自訂",
    "collab.settings.hours": "小時",
    "collab.settings.timeoutHelp": "每個子任務最長執行時間（目前：%@）",
    "collab.settings.maxConcurrency": "最大並行",
    "collab.settings.unlimited": "不限",
    "collab.settings.maxConcurrencyHelp": "最多同時執行的子任務數（0 = 不限）",
    "collab.settings.retryContextLength": "重試上下文長度",
    "collab.settings.chars": "字元",
    "collab.settings.retryContextHelp": "重試時傳給 Agent 的歷史長度",
    "collab.settings.resetDefaults": "重設預設值",
    "collab.action.cancelAll": "全部取消",
    "collab.task.retry": "重試此任務",
    "collab.task.forceComplete": "標記為完成（解除下游阻塞）",
    "collab.task.skip": "略過此任務",
    "collab.task.dependsOn": "依賴：#%@",
    "collab.task.error": "錯誤：%@",
    "collab.process.running": "程序執行中",
    "collab.process.ended": "程序已結束",
    "collab.process.lines": "%lld 行",
    "collab.process.files": "%lld 個檔案",
    "collab.process.longRunning": "執行時間較長",
    "collab.output.files": "輸出檔案：",
    "collab.agent.running": "Agent 執行中...",
    "catalog.action.install": "安裝",
    "catalog.action.installing": "安裝中...",
    "catalog.action.uninstall": "解除安裝",
    "catalog.action.remove": "移除",
    "catalog.action.removing": "移除中...",
    "catalog.action.cancel": "取消",
    "catalog.action.close": "關閉",
    "catalog.action.refresh": "重新整理",
    "catalog.action.update": "更新",
    "catalog.action.upgrade": "升級",
    "catalog.action.upgrading": "升級中...",
    "catalog.action.enable": "啟用",
    "catalog.action.disable": "停用",
    "catalog.status.installed": "已安裝",
    "catalog.status.notInstalled": "未安裝",
    "catalog.status.ready": "就緒",
    "catalog.status.missing": "缺少依賴",
    "catalog.status.loaded": "已載入",
    "catalog.status.disabled": "已停用",
    "catalog.status.unavailable": "不可用",
    "catalog.status.updateAvailable": "有更新",
    "catalog.section.recommend": "推薦",
    "catalog.section.catalog": "目錄",
    "catalog.section.all": "全部",
    "catalog.section.installed": "已安裝",
    "catalog.section.builtIn": "內建",
    "catalog.section.custom": "自訂",
    "catalog.detail.description": "描述",
    "catalog.count.installed": "已安裝 %lld 個",
    "dashboard.count.configured": "（已設定 %lld 個）",
    "dashboard.status.port": "連接埠",
    "dashboard.status.uptime": "執行時間",
    "dashboard.status.version": "版本",
    "dashboard.status.service.running": "執行中",
    "dashboard.status.service.stopped": "已停止",
    "dashboard.status.service.starting": "啟動中",
    "dashboard.status.service.stopping": "停止中",
    "dashboard.status.service.error": "錯誤",
    "dashboard.status.service.unknown": "未知",
    "dashboard.status.agentSessions": "Agent 會話",
    "dashboard.status.totalAgents": "共 %lld 個 Agent",
    "dashboard.status.noSessions": "暫無會話",
    "dashboard.status.cronHealth": "定時任務健康",
    "dashboard.status.total": "總數：%lld",
    "dashboard.status.active": "啟用：%lld",
    "dashboard.status.next": "下次：%@",
    "dashboard.status.disabledParen": "（已停用）",
    "dashboard.status.channelsCount": "%lld 個頻道",
    "dashboard.status.tokenUsage": "Token 用量",
    "dashboard.status.tokenTotal": "總計：",
    "dashboard.status.noTokenData": "暫無 token 資料",
    "dashboard.status.systemInformation": "系統資訊",
    "dashboard.status.macosVersion": "macOS 版本",
    "dashboard.status.architecture": "架構",
    "dashboard.status.availableSpace": "可用空間",
    "dashboard.status.openClawPath": "OpenClaw 路徑",
    "dashboard.status.label.budget": "預算：",
    "dashboard.status.label.cost": "費用：",
    "dashboard.status.label.estimatedCost": "預估費用：",
    "dashboard.service.toast.started": "服務已啟動",
    "dashboard.service.toast.startFailed": "啟動服務失敗：%@",
    "dashboard.service.toast.stopped": "服務已停止",
    "dashboard.service.toast.stopFailed": "停止服務失敗：%@",
    "dashboard.service.toast.restarted": "服務已重新啟動",
    "dashboard.service.toast.restartFailed": "重新啟動服務失敗：%@",
    "dashboard.config.error.invalidPort": "連接埠號無效，必須在 1 到 65535 之間",
    "dashboard.config.toast.saved": "設定已儲存到 openclaw.json",
    "dashboard.config.error.saveFailed": "儲存設定檔失敗",
    "dashboard.alert.error": "錯誤",
    "dashboard.agent.remove.title": "移除 Agent",
    "dashboard.agent.remove.message": "確定要移除「%@」嗎？這會刪除該 Agent 及其工作區。",
    "dashboard.agent.addWorkFolder": "新增工作資料夾...",
    "dashboard.agent.fallbackDescription": "通用助理",
    "dashboard.model.label": "模型",
    "dashboard.model.defaultInherit": "預設（繼承）",
    "dashboard.model.defaultWithValue": "預設（%@）",
    "dashboard.chat.viewResult": "查看結果 ↑",
    "dashboard.chat.moveToBackground": "轉到後台",
    "dashboard.chat.clearConversation": "清空會話",
    "dashboard.chat.modelSwitchFailedNotSent": "無法切換到選取的模型，因此訊息未傳送。",
    "dashboard.diagnostics.title": "診斷報告",
    "dashboard.outputs.title": "輸出",
    "dashboard.outputs.empty": "暫無輸出",
    "dashboard.terminal.title": "終端機",
    "dashboard.activity.empty": "暫無活動",
    "dashboard.tooltip.chooseModel": "選擇模型",
    "dashboard.tooltip.attachFile": "附加檔案",
    "dashboard.tooltip.searchChats": "搜尋會話",
    "dashboard.tooltip.taskRunning": "任務執行中",
    "dashboard.tooltip.hideTerminal": "隱藏終端機",
    "dashboard.tooltip.showTerminal": "顯示終端機",
    "dashboard.tooltip.hideOutputs": "隱藏輸出",
    "dashboard.tooltip.showOutputs": "顯示輸出",
    "dashboard.tooltip.confirmAndSend": "確認並傳送",
    "dashboard.tooltip.removeAttachment": "移除附件",
    "dashboard.tooltip.openOutputsFolder": "開啟輸出資料夾",
    "dashboard.tooltip.clearConversation": "清空會話",
    "dashboard.tooltip.collapseSessionDetails": "收起會話詳情",
    "dashboard.tooltip.expandSessionDetails": "展開會話詳情",
    "dashboard.tooltip.editAgent": "編輯 Agent",
    "dashboard.session.action.rename": "重新命名",
    "dashboard.session.action.pin": "置頂",
    "dashboard.session.action.unpin": "取消置頂",
    "dashboard.session.action.export": "匯出…",
    "dashboard.session.action.archive": "封存",
    "dashboard.session.action.confirmDelete": "確認刪除",
    "dashboard.session.newChat": "新會話",
    "dashboard.sidebar.pinned": "已置頂",
    "dashboard.skills.title": "技能",
    "dashboard.skills.enabledCount": "%lld / %lld 已啟用",
    "dashboard.skills.loading": "載入中…",
    "dashboard.skills.empty": "未偵測到技能",
    "dashboard.skills.viewAll": "查看全部（%lld）",
    "dashboard.composer.mode.label": "模式：",
    "dashboard.composer.mode.chat": "聊天",
    "dashboard.composer.mode.task": "執行任務",
    "dashboard.composer.mode.code": "程式碼模式",
    "dashboard.channels.title": "頻道",
    "dashboard.channels.add": "新增頻道",
    "dashboard.channels.loading": "正在載入頻道...",
    "dashboard.channels.empty.title": "暫無已設定頻道",
    "dashboard.channels.empty.detail": "新增一個頻道開始使用",
    "dashboard.channels.status.configured": "已設定",
    "dashboard.channels.status.notConfigured": "未設定",
    "dashboard.channels.status.linked": "已連接",
    "dashboard.channels.status.notLinked": "未連接",
    "dashboard.channels.status.connected": "已連接",
    "dashboard.channels.alert.removeTitle": "移除頻道",
    "dashboard.channels.alert.removeMessage": "確定要移除 %@ 頻道嗎？這會刪除它的設定。",
    "dashboard.channels.sheet.channelType": "頻道類型",
    "dashboard.channels.sheet.pluginMissing": "%@ 外掛尚未安裝，請先安裝外掛。",
    "dashboard.channels.sheet.qr.startHelp": "點擊下方按鈕開始微信掃碼登入",
    "dashboard.channels.sheet.qr.start": "開始掃碼登入",
    "dashboard.channels.sheet.qr.scan": "使用微信掃碼連接",
    "dashboard.channels.sheet.qr.waiting": "正在等待掃碼...",
    "dashboard.channels.sheet.qr.generating": "正在產生 QR Code...",
    "dashboard.channels.sheet.qr.success": "微信連接成功！",
    "dashboard.channels.sheet.done": "完成",
    "dashboard.channels.sheet.accountId": "帳號 ID",
    "dashboard.channels.sheet.accountHelp": "主帳號可使用 default，也可以輸入其他 ID 為同一頻道新增多個帳號。",
    "dashboard.channels.sheet.displayName": "顯示名稱",
    "dashboard.channels.sheet.optional": "可選",
    "dashboard.channels.sheet.appKey": "App Key",
    "dashboard.channels.sheet.enterAppKey": "輸入 App Key",
    "dashboard.channels.sheet.appSecret": "App Secret",
    "dashboard.channels.sheet.enterAppSecret": "輸入 App Secret",
    "dashboard.channels.sheet.dingtalkHelp": "前往釘釘開放平台建立應用，並取得 App Key 和 App Secret。",
    "dashboard.channels.sheet.feishuHelp": "前往飛書開放平台建立應用，並取得 App ID 和 App Secret。",
    "dashboard.channels.sheet.token": "Token",
    "dashboard.channels.sheet.enterToken": "輸入機器人 token 或 API key",
    "dashboard.channels.sheet.tokenHelp": "Telegram/Discord 使用機器人 token，Slack 使用 bot token（xoxb-...）。其他頻道可能需要不同憑證。",
    "dashboard.channels.sheet.cliHelp": "Slack、Matrix 等複雜頻道可使用命令列設定：",
    "dashboard.channels.toast.addFailed": "新增 %@ %@ 失敗：%@",
    "dashboard.channels.toast.added": "%@ %@ 頻道已新增",
    "dashboard.channels.toast.readConfigFailed": "讀取 openclaw.json 失敗",
    "dashboard.channels.toast.removeFailed": "移除 %@ 失敗：%@",
    "dashboard.channels.toast.removed": "%@ 頻道已移除",
    "dashboard.cron.title": "定時任務",
    "dashboard.cron.add": "新增任務",
    "dashboard.cron.refreshing": "正在重新整理...",
    "dashboard.cron.loadFailed.title": "無法載入定時任務",
    "dashboard.cron.checking.title": "正在檢查定時任務",
    "dashboard.cron.checking.detail": "正在讀取排程自動化任務...",
    "dashboard.cron.empty.title": "暫無已設定定時任務",
    "dashboard.cron.empty.detail": "新增定時任務來安排自動化操作",
    "dashboard.cron.agentTag": "Agent：%@",
    "dashboard.cron.next": "下次：%@",
    "dashboard.cron.last": "上次：%@",
    "dashboard.cron.alert.removeTitle": "移除定時任務",
    "dashboard.cron.alert.removeMessage": "確定要移除定時任務「%@」嗎？此操作無法復原。",
    "dashboard.cron.sheet.title": "新增定時任務",
    "dashboard.cron.sheet.name": "名稱",
    "dashboard.cron.sheet.namePlaceholder": "例如 daily-report",
    "dashboard.cron.sheet.expression": "Cron 表達式",
    "dashboard.cron.sheet.expressionPlaceholder": "例如 0 9 * * *",
    "dashboard.cron.sheet.expressionHelp": "格式：分鐘 小時 日 月 星期（例如「0 9 * * *」= 每天上午 9:00）",
    "dashboard.cron.sheet.timezone": "時區",
    "dashboard.cron.sheet.timezonePlaceholder": "例如 Asia/Shanghai",
    "dashboard.cron.sheet.agent": "Agent",
    "dashboard.cron.sheet.sessionTarget": "會話目標",
    "dashboard.cron.sheet.session.isolated": "隔離",
    "dashboard.cron.sheet.session.main": "主會話",
    "dashboard.cron.sheet.sessionHelp": "隔離：每次執行使用獨立會話。主會話：重用主會話。",
    "dashboard.cron.sheet.message": "訊息",
    "dashboard.cron.sheet.messagePlaceholder": "定時任務觸發時要傳送的訊息/指令...",
    "dashboard.cron.toast.addFailed": "新增定時任務失敗：%@",
    "dashboard.cron.toast.created": "定時任務「%@」已建立",
    "dashboard.cron.toast.enableFailed": "啟用定時任務失敗：%@",
    "dashboard.cron.toast.enabled": "定時任務「%@」已啟用",
    "dashboard.cron.toast.disableFailed": "停用定時任務失敗：%@",
    "dashboard.cron.toast.disabled": "定時任務「%@」已停用",
    "dashboard.cron.toast.removeFailed": "移除定時任務失敗：%@",
    "dashboard.cron.toast.removed": "定時任務「%@」已移除",
    "dashboard.cron.toast.runFailed": "執行定時任務失敗：%@",
    "dashboard.cron.toast.triggered": "定時任務「%@」已觸發",
    "dashboard.models.title": "模型",
    "dashboard.models.loading": "正在載入模型...",
    "dashboard.models.empty": "暫無已設定模型",
    "dashboard.models.cliHint": "別名和認證設定請使用：",
    "dashboard.models.default": "預設",
    "dashboard.models.imageModel": "圖像模型",
    "dashboard.models.notSet": "未設定",
    "dashboard.models.fallbacks": "回退",
    "dashboard.models.imageFallbacks": "圖像回退",
    "dashboard.models.none": "無",
    "dashboard.models.fallbackModels": "回退模型",
    "dashboard.models.imageFallbackModels": "圖像回退模型",
    "dashboard.models.badge.default": "預設",
    "dashboard.models.badge.image": "圖像",
    "dashboard.models.badge.fallback": "回退",
    "dashboard.models.badge.imageFallback": "圖像回退",
    "dashboard.models.local": "本機",
    "dashboard.models.auth": "已認證",
    "dashboard.models.action.setImage": "設為圖像",
    "dashboard.models.action.setImageFallback": "設為圖像回退",
    "dashboard.models.action.fallback": "回退",
    "dashboard.models.action.setFallback": "設為回退",
    "dashboard.models.action.setDefault": "設為預設",
    "dashboard.models.toast.setDefaultFailed": "設定預設模型失敗：%@",
    "dashboard.models.toast.defaultSet": "預設模型已設為 %@",
    "dashboard.models.toast.setImageFailed": "設定圖像模型失敗：%@",
    "dashboard.models.toast.imageSet": "圖像模型已設為 %@",
    "dashboard.models.toast.addFallbackFailed": "新增回退模型失敗：%@",
    "dashboard.models.toast.fallbackAdded": "%@ 已新增到回退模型",
    "dashboard.models.toast.removeFallbackFailed": "移除回退模型失敗：%@",
    "dashboard.models.toast.fallbackRemoved": "%@ 已從回退模型移除",
    "dashboard.models.toast.addImageFallbackFailed": "新增圖像回退模型失敗：%@",
    "dashboard.models.toast.imageFallbackAdded": "%@ 已新增到圖像回退模型",
    "dashboard.models.toast.removeImageFallbackFailed": "移除圖像回退模型失敗：%@",
    "dashboard.models.toast.imageFallbackRemoved": "%@ 已從圖像回退模型移除",
    "dashboard.logs.searchPlaceholder": "搜尋日誌...",
    "dashboard.logs.auto": "自動",
    "dashboard.logs.export": "匯出",
    "dashboard.logs.openFile": "開啟檔案",
    "dashboard.logs.empty.title": "暫無日誌",
    "dashboard.logs.empty.detail": "閘道服務執行後日誌會顯示在這裡",
    "dashboard.logs.toast.exported": "日誌已匯出",
    "dashboard.logs.toast.cleared": "日誌已清空",
    "workspace.outputs.title": "輸出",
    "workspace.outputs.openInFinder": "在 Finder 中開啟",
    "workspace.outputs.hideProjectFiles": "隱藏專案檔案",
    "workspace.outputs.showProjectFiles": "顯示專案檔案",
    "workspace.outputs.empty": "暫無輸出",
    "workspace.files.filterPlaceholder": "篩選檔案...",
    "workspace.files.empty": "暫無檔案",
    "workspace.files.noMatches": "沒有符合的檔案",
    "workspace.files.fallbackPath": "回退：%@",
    "workspace.files.newFile": "新增檔案",
    "workspace.files.newFolder": "新增資料夾",
    "workspace.files.cut": "剪下",
    "workspace.files.copy": "複製",
    "workspace.files.paste": "貼上",
    "workspace.files.deleteConfirm": "確定要刪除「%@」嗎？",
    "workspace.files.pathCopied": "路徑已複製",
    "workspace.files.copyPathHelp": "雙擊複製路徑",
    "workspace.files.decreaseFont": "縮小字體（⌘-）",
    "workspace.files.increaseFont": "放大字體（⌘+）",
    "workspace.files.disableWordWrap": "關閉自動換行",
    "workspace.files.enableWordWrap": "啟用自動換行",
    "workspace.files.fullscreen": "全螢幕",
    "workspace.files.exitFullscreen": "離開全螢幕",
    "workspace.files.position": "第 %lld 行，第 %lld 欄",
    "workspace.project.newChat": "在專案中新增會話",
    "workspace.project.revealInFinder": "在 Finder 中顯示",
    "workspace.project.removeFromAgent": "從 Agent 移除",
    "error.report.action": "回報問題",
    "error.report.title": "錯誤報告已複製",
    "error.report.message": "錯誤詳情已複製到剪貼簿。回報問題時請貼上這些內容。",
    "error.report.contentTitle": "錯誤報告",
    "error.report.contentSystemInfo": "系統資訊：",
    "error.report.contentPleaseReport": "請將此問題回報給開發者。"
}

SKILLS_UI = {
    "skills.title": "Skills",
    "skills.subtitle": "Extend GetClowHub with task-specific skills",
    "skills.search.placeholder": "Search skills",
    "skills.help.installFromRepository": "Install skill from GitHub repository",
    "skills.help.refresh": "Refresh skills",
    "skills.loading.catalog": "Loading skill catalog...",
    "skills.loading.installed": "Loading installed skills...",
    "skills.empty.catalogLoadFailed": "Could not load skill catalog",
    "skills.empty.noRecommended": "No recommended skills",
    "skills.empty.noMatchingRecommended": "No matching recommended skills",
    "skills.empty.noSkills": "No skills found",
    "skills.empty.noMatchingSkills": "No matching skills",
    "skills.empty.noInstalled": "No installed skills",
    "skills.empty.noMatchingInstalled": "No matching installed skills",
    "skills.alert.removeTitle": "Remove Skill",
    "skills.alert.removeMessage": "Remove \"%@\" from installed skills?",
    "skills.manual.title": "Install Skill",
    "skills.manual.subtitle": "Install a GitHub skill repository globally.",
    "skills.manual.repository": "Repository",
    "skills.fallback.installedSkill": "Installed skill",
    "skills.installed.fallback.description": "%@ skill is installed and ready to use.",
    "skills.installed.fallback.content": "%@\n\n%@",
    "skills.toast.updated": "Skills updated successfully",
    "skills.toast.installed": "Installed skill %@",
    "skills.toast.upgraded": "Upgraded skill %@",
    "skills.toast.installFailed": "Failed to install %@: %@",
    "skills.toast.upgradeFailed": "Failed to upgrade %@: %@",
    "skills.toast.manualInstalled": "Installed skill from repository",
    "skills.toast.manualInstallFailed": "Failed to install skill: %@",
    "skills.toast.removed": "Removed skill %@",
    "skills.toast.removeFailed": "Failed to remove %@: %@",
    "skills.error.refreshFailed": "Failed to refresh skills",
    "skills.error.builtInRemove": "Built-in skills cannot be removed"
}

SKILLS_UI_ZH_HANS = {
    "skills.title": "技能",
    "skills.subtitle": "使用面向任务的技能扩展 GetClowHub",
    "skills.search.placeholder": "搜索技能",
    "skills.help.installFromRepository": "从 GitHub 仓库安装技能",
    "skills.help.refresh": "刷新技能",
    "skills.loading.catalog": "正在加载技能目录...",
    "skills.loading.installed": "正在加载已安装技能...",
    "skills.empty.catalogLoadFailed": "无法加载技能目录",
    "skills.empty.noRecommended": "暂无推荐技能",
    "skills.empty.noMatchingRecommended": "没有匹配的推荐技能",
    "skills.empty.noSkills": "没有找到技能",
    "skills.empty.noMatchingSkills": "没有匹配的技能",
    "skills.empty.noInstalled": "暂无已安装技能",
    "skills.empty.noMatchingInstalled": "没有匹配的已安装技能",
    "skills.alert.removeTitle": "移除技能",
    "skills.alert.removeMessage": "要从已安装技能中移除“%@”吗？",
    "skills.manual.title": "安装技能",
    "skills.manual.subtitle": "全局安装一个 GitHub 技能仓库。",
    "skills.manual.repository": "仓库",
    "skills.fallback.installedSkill": "已安装技能",
    "skills.installed.fallback.description": "%@ 技能已安装，可直接使用。",
    "skills.installed.fallback.content": "%@\n\n%@",
    "skills.toast.updated": "技能已更新",
    "skills.toast.installed": "已安装技能 %@",
    "skills.toast.upgraded": "已升级技能 %@",
    "skills.toast.installFailed": "安装 %@ 失败：%@",
    "skills.toast.upgradeFailed": "升级 %@ 失败：%@",
    "skills.toast.manualInstalled": "已从仓库安装技能",
    "skills.toast.manualInstallFailed": "安装技能失败：%@",
    "skills.toast.removed": "已移除技能 %@",
    "skills.toast.removeFailed": "移除 %@ 失败：%@",
    "skills.error.refreshFailed": "刷新技能失败",
    "skills.error.builtInRemove": "内置技能不能移除"
}

SKILLS_UI_ZH_HANT = {
    "skills.title": "技能",
    "skills.subtitle": "使用面向任務的技能擴充 GetClowHub",
    "skills.search.placeholder": "搜尋技能",
    "skills.help.installFromRepository": "從 GitHub 倉庫安裝技能",
    "skills.help.refresh": "重新整理技能",
    "skills.loading.catalog": "正在載入技能目錄...",
    "skills.loading.installed": "正在載入已安裝技能...",
    "skills.empty.catalogLoadFailed": "無法載入技能目錄",
    "skills.empty.noRecommended": "暫無推薦技能",
    "skills.empty.noMatchingRecommended": "沒有符合的推薦技能",
    "skills.empty.noSkills": "沒有找到技能",
    "skills.empty.noMatchingSkills": "沒有符合的技能",
    "skills.empty.noInstalled": "暫無已安裝技能",
    "skills.empty.noMatchingInstalled": "沒有符合的已安裝技能",
    "skills.alert.removeTitle": "移除技能",
    "skills.alert.removeMessage": "要從已安裝技能中移除「%@」嗎？",
    "skills.manual.title": "安裝技能",
    "skills.manual.subtitle": "全域安裝一個 GitHub 技能倉庫。",
    "skills.manual.repository": "倉庫",
    "skills.fallback.installedSkill": "已安裝技能",
    "skills.installed.fallback.description": "%@ 技能已安裝，可直接使用。",
    "skills.installed.fallback.content": "%@\n\n%@",
    "skills.toast.updated": "技能已更新",
    "skills.toast.installed": "已安裝技能 %@",
    "skills.toast.upgraded": "已升級技能 %@",
    "skills.toast.installFailed": "安裝 %@ 失敗：%@",
    "skills.toast.upgradeFailed": "升級 %@ 失敗：%@",
    "skills.toast.manualInstalled": "已從倉庫安裝技能",
    "skills.toast.manualInstallFailed": "安裝技能失敗：%@",
    "skills.toast.removed": "已移除技能 %@",
    "skills.toast.removeFailed": "移除 %@ 失敗：%@",
    "skills.error.refreshFailed": "重新整理技能失敗",
    "skills.error.builtInRemove": "內建技能不能移除"
}

PLUGINS_UI = {
    "plugins.title": "Plugins",
    "plugins.subtitle": "Install curated OpenClaw plugins from the GetClowHub catalog",
    "plugins.search.placeholder": "Search plugins",
    "plugins.help.updateInstalled": "Update installed plugins",
    "plugins.help.installCustom": "Install custom plugin",
    "plugins.help.refresh": "Refresh plugins",
    "plugins.loading.catalog": "Loading plugin catalog...",
    "plugins.loading.installed": "Loading installed plugins...",
    "plugins.empty.catalogLoadFailed": "Could not load plugin catalog",
    "plugins.empty.noRecommended": "No recommended plugins",
    "plugins.empty.noMatchingRecommended": "No matching recommended plugins",
    "plugins.empty.noPlugins": "No plugins found",
    "plugins.empty.noMatchingPlugins": "No matching plugins",
    "plugins.empty.noInstalled": "No installed plugins",
    "plugins.empty.noMatchingInstalled": "No matching installed plugins",
    "plugins.alert.uninstallTitle": "Uninstall Plugin",
    "plugins.alert.uninstallMessage": "Are you sure you want to uninstall '%@'?",
    "plugins.install.title": "Install Plugin",
    "plugins.install.method": "Install Method",
    "plugins.install.method.npm": "npm",
    "plugins.install.method.file": "File",
    "plugins.install.method.link": "Link",
    "plugins.install.quickSelect": "Quick Select",
    "plugins.install.preset.custom": "Custom",
    "plugins.install.packageName": "Package Name",
    "plugins.install.packagePlaceholder": "e.g. @openclaw/discord",
    "plugins.install.presetAlreadyInstalled": "%@ plugin is already installed",
    "plugins.install.pluginFile": "Plugin File",
    "plugins.install.filePlaceholder": "Select a plugin file...",
    "plugins.install.browse": "Browse",
    "plugins.install.supportedFileTypes": "Supported: .ts .js .zip .tgz .tar.gz",
    "plugins.install.pluginLink": "Plugin Link",
    "plugins.install.linkPlaceholder": "https://github.com/owner/repo",
    "plugins.install.linkHelp": "Enter a plugin URL, GitHub repository, archive URL, or remote package spec",
    "plugins.install.installing": "Installing...",
    "plugins.toast.notInstallable": "%@ is not installable by OpenClaw.",
    "plugins.toast.installed": "Installed plugin %@",
    "plugins.toast.installFailed": "Failed to install %@: %@",
    "plugins.toast.enableFailed": "Failed to enable %@: %@",
    "plugins.toast.enabled": "%@ enabled",
    "plugins.toast.disableFailed": "Failed to disable %@: %@",
    "plugins.toast.disabled": "%@ disabled",
    "plugins.toast.customInstallFailed": "Failed to install plugin: %@",
    "plugins.toast.customInstalled": "Plugin installed successfully",
    "plugins.toast.weixinInstallFailed": "Failed to install Weixin plugin: %@",
    "plugins.toast.weixinInstalled": "Weixin plugin installed successfully",
    "plugins.toast.builtInUninstall": "Built-in plugins cannot be uninstalled. Use Disable instead.",
    "plugins.toast.uninstallFailed": "Failed to uninstall %@: %@",
    "plugins.toast.uninstalled": "%@ uninstalled",
    "plugins.toast.removeFilesFailed": "Failed to remove %@ files: %@",
    "plugins.toast.updateFailed": "Failed to update %@: %@",
    "plugins.toast.updated": "%@ updated",
    "plugins.toast.updateAllFailed": "Failed to update plugins: %@",
    "plugins.toast.allUpdated": "All plugins updated",
    "plugins.fallback.installedPlugin": "Installed OpenClaw plugin",
    "plugins.fallback.openClawPlugin": "OpenClaw plugin",
    "plugins.installed.family.provider.displayName": "%@ Provider",
    "plugins.installed.family.provider.description": "Model provider for connecting OpenClaw to %@ models.",
    "plugins.installed.family.provider.category": "Provider",
    "plugins.installed.family.browser.displayName": "%@ Browser",
    "plugins.installed.family.browser.description": "Browser automation capability for opening pages, inspecting content, and interacting with websites.",
    "plugins.installed.family.browser.category": "Browser",
    "plugins.installed.family.speech.displayName": "%@ Speech",
    "plugins.installed.family.speech.description": "Speech capability for transcription, voice, or audio-related model workflows.",
    "plugins.installed.family.speech.category": "Speech",
    "plugins.installed.family.memory.displayName": "%@ Memory",
    "plugins.installed.family.memory.description": "Memory storage capability for retaining reusable context across OpenClaw sessions.",
    "plugins.installed.family.memory.category": "Memory",
    "plugins.installed.family.proxy.displayName": "%@ Proxy",
    "plugins.installed.family.proxy.description": "Proxy capability for routing model requests through a compatible provider or local service.",
    "plugins.installed.family.proxy.category": "Proxy",
    "plugins.installed.family.runtime.displayName": "%@",
    "plugins.installed.family.runtime.description": "Core runtime capability used by OpenClaw to provide built-in plugin behavior.",
    "plugins.installed.family.runtime.category": "Runtime",
    "plugins.installed.family.plugin.displayName": "%@",
    "plugins.installed.family.plugin.description": "Installed OpenClaw plugin.",
    "plugins.installed.family.plugin.category": "Plugin",
    "plugins.installed.detail.pluginId": "**Plugin ID:** `%@`",
    "plugins.installed.detail.status": "**Status:** %@",
    "plugins.installed.detail.version": "**Version:** %@"
}

PLUGINS_UI_ZH_HANS = {
    "plugins.title": "插件",
    "plugins.subtitle": "从 GetClowHub 目录安装精选 OpenClaw 插件",
    "plugins.search.placeholder": "搜索插件",
    "plugins.help.updateInstalled": "更新已安装插件",
    "plugins.help.installCustom": "安装自定义插件",
    "plugins.help.refresh": "刷新插件",
    "plugins.loading.catalog": "正在加载插件目录...",
    "plugins.loading.installed": "正在加载已安装插件...",
    "plugins.empty.catalogLoadFailed": "无法加载插件目录",
    "plugins.empty.noRecommended": "暂无推荐插件",
    "plugins.empty.noMatchingRecommended": "没有匹配的推荐插件",
    "plugins.empty.noPlugins": "没有找到插件",
    "plugins.empty.noMatchingPlugins": "没有匹配的插件",
    "plugins.empty.noInstalled": "暂无已安装插件",
    "plugins.empty.noMatchingInstalled": "没有匹配的已安装插件",
    "plugins.alert.uninstallTitle": "卸载插件",
    "plugins.alert.uninstallMessage": "确定要卸载“%@”吗？",
    "plugins.install.title": "安装插件",
    "plugins.install.method": "安装方式",
    "plugins.install.method.npm": "npm",
    "plugins.install.method.file": "文件",
    "plugins.install.method.link": "链接",
    "plugins.install.quickSelect": "快速选择",
    "plugins.install.preset.custom": "自定义",
    "plugins.install.packageName": "包名",
    "plugins.install.packagePlaceholder": "例如 @openclaw/discord",
    "plugins.install.presetAlreadyInstalled": "%@ 插件已安装",
    "plugins.install.pluginFile": "插件文件",
    "plugins.install.filePlaceholder": "选择插件文件...",
    "plugins.install.browse": "浏览",
    "plugins.install.supportedFileTypes": "支持：.ts .js .zip .tgz .tar.gz",
    "plugins.install.pluginLink": "插件链接",
    "plugins.install.linkPlaceholder": "https://github.com/owner/repo",
    "plugins.install.linkHelp": "输入插件 URL、GitHub 仓库、归档地址或远程包规格",
    "plugins.install.installing": "安装中...",
    "plugins.toast.notInstallable": "%@ 不能由 OpenClaw 安装。",
    "plugins.toast.installed": "已安装插件 %@",
    "plugins.toast.installFailed": "安装 %@ 失败：%@",
    "plugins.toast.enableFailed": "启用 %@ 失败：%@",
    "plugins.toast.enabled": "%@ 已启用",
    "plugins.toast.disableFailed": "停用 %@ 失败：%@",
    "plugins.toast.disabled": "%@ 已停用",
    "plugins.toast.customInstallFailed": "安装插件失败：%@",
    "plugins.toast.customInstalled": "插件安装成功",
    "plugins.toast.weixinInstallFailed": "安装微信插件失败：%@",
    "plugins.toast.weixinInstalled": "微信插件安装成功",
    "plugins.toast.builtInUninstall": "内置插件不能卸载，请使用停用。",
    "plugins.toast.uninstallFailed": "卸载 %@ 失败：%@",
    "plugins.toast.uninstalled": "%@ 已卸载",
    "plugins.toast.removeFilesFailed": "移除 %@ 文件失败：%@",
    "plugins.toast.updateFailed": "更新 %@ 失败：%@",
    "plugins.toast.updated": "%@ 已更新",
    "plugins.toast.updateAllFailed": "更新插件失败：%@",
    "plugins.toast.allUpdated": "全部插件已更新",
    "plugins.fallback.installedPlugin": "已安装 OpenClaw 插件",
    "plugins.fallback.openClawPlugin": "OpenClaw 插件",
    "plugins.installed.family.provider.displayName": "%@ 提供商",
    "plugins.installed.family.provider.description": "用于将 OpenClaw 连接到 %@ 模型的模型提供商。",
    "plugins.installed.family.provider.category": "模型提供商",
    "plugins.installed.family.browser.displayName": "%@ 浏览器",
    "plugins.installed.family.browser.description": "用于打开网页、检查内容并与网站交互的浏览器自动化能力。",
    "plugins.installed.family.browser.category": "浏览器",
    "plugins.installed.family.speech.displayName": "%@ 语音",
    "plugins.installed.family.speech.description": "用于转录、语音或音频模型工作流的语音能力。",
    "plugins.installed.family.speech.category": "语音",
    "plugins.installed.family.memory.displayName": "%@ 记忆",
    "plugins.installed.family.memory.description": "用于在 OpenClaw 会话之间保留可复用上下文的记忆存储能力。",
    "plugins.installed.family.memory.category": "记忆",
    "plugins.installed.family.proxy.displayName": "%@ 代理",
    "plugins.installed.family.proxy.description": "用于通过兼容提供商或本地服务路由模型请求的代理能力。",
    "plugins.installed.family.proxy.category": "代理",
    "plugins.installed.family.runtime.displayName": "%@",
    "plugins.installed.family.runtime.description": "OpenClaw 用来提供内置插件行为的核心运行时能力。",
    "plugins.installed.family.runtime.category": "运行时",
    "plugins.installed.family.plugin.displayName": "%@",
    "plugins.installed.family.plugin.description": "已安装的 OpenClaw 插件。",
    "plugins.installed.family.plugin.category": "插件",
    "plugins.installed.detail.pluginId": "**插件 ID：** `%@`",
    "plugins.installed.detail.status": "**状态：** %@",
    "plugins.installed.detail.version": "**版本：** %@"
}

PLUGINS_UI_ZH_HANT = {
    "plugins.title": "外掛",
    "plugins.subtitle": "從 GetClowHub 目錄安裝精選 OpenClaw 外掛",
    "plugins.search.placeholder": "搜尋外掛",
    "plugins.help.updateInstalled": "更新已安裝外掛",
    "plugins.help.installCustom": "安裝自訂外掛",
    "plugins.help.refresh": "重新整理外掛",
    "plugins.loading.catalog": "正在載入外掛目錄...",
    "plugins.loading.installed": "正在載入已安裝外掛...",
    "plugins.empty.catalogLoadFailed": "無法載入外掛目錄",
    "plugins.empty.noRecommended": "暫無推薦外掛",
    "plugins.empty.noMatchingRecommended": "沒有符合的推薦外掛",
    "plugins.empty.noPlugins": "沒有找到外掛",
    "plugins.empty.noMatchingPlugins": "沒有符合的外掛",
    "plugins.empty.noInstalled": "暫無已安裝外掛",
    "plugins.empty.noMatchingInstalled": "沒有符合的已安裝外掛",
    "plugins.alert.uninstallTitle": "解除安裝外掛",
    "plugins.alert.uninstallMessage": "確定要解除安裝「%@」嗎？",
    "plugins.install.title": "安裝外掛",
    "plugins.install.method": "安裝方式",
    "plugins.install.method.npm": "npm",
    "plugins.install.method.file": "檔案",
    "plugins.install.method.link": "連結",
    "plugins.install.quickSelect": "快速選擇",
    "plugins.install.preset.custom": "自訂",
    "plugins.install.packageName": "套件名稱",
    "plugins.install.packagePlaceholder": "例如 @openclaw/discord",
    "plugins.install.presetAlreadyInstalled": "%@ 外掛已安裝",
    "plugins.install.pluginFile": "外掛檔案",
    "plugins.install.filePlaceholder": "選擇外掛檔案...",
    "plugins.install.browse": "瀏覽",
    "plugins.install.supportedFileTypes": "支援：.ts .js .zip .tgz .tar.gz",
    "plugins.install.pluginLink": "外掛連結",
    "plugins.install.linkPlaceholder": "https://github.com/owner/repo",
    "plugins.install.linkHelp": "輸入外掛 URL、GitHub 倉庫、封存檔地址或遠端套件規格",
    "plugins.install.installing": "安裝中...",
    "plugins.toast.notInstallable": "%@ 不能由 OpenClaw 安裝。",
    "plugins.toast.installed": "已安裝外掛 %@",
    "plugins.toast.installFailed": "安裝 %@ 失敗：%@",
    "plugins.toast.enableFailed": "啟用 %@ 失敗：%@",
    "plugins.toast.enabled": "%@ 已啟用",
    "plugins.toast.disableFailed": "停用 %@ 失敗：%@",
    "plugins.toast.disabled": "%@ 已停用",
    "plugins.toast.customInstallFailed": "安裝外掛失敗：%@",
    "plugins.toast.customInstalled": "外掛安裝成功",
    "plugins.toast.weixinInstallFailed": "安裝微信外掛失敗：%@",
    "plugins.toast.weixinInstalled": "微信外掛安裝成功",
    "plugins.toast.builtInUninstall": "內建外掛不能解除安裝，請使用停用。",
    "plugins.toast.uninstallFailed": "解除安裝 %@ 失敗：%@",
    "plugins.toast.uninstalled": "%@ 已解除安裝",
    "plugins.toast.removeFilesFailed": "移除 %@ 檔案失敗：%@",
    "plugins.toast.updateFailed": "更新 %@ 失敗：%@",
    "plugins.toast.updated": "%@ 已更新",
    "plugins.toast.updateAllFailed": "更新外掛失敗：%@",
    "plugins.toast.allUpdated": "全部外掛已更新",
    "plugins.fallback.installedPlugin": "已安裝 OpenClaw 外掛",
    "plugins.fallback.openClawPlugin": "OpenClaw 外掛",
    "plugins.installed.family.provider.displayName": "%@ 提供商",
    "plugins.installed.family.provider.description": "用於將 OpenClaw 連接到 %@ 模型的模型提供商。",
    "plugins.installed.family.provider.category": "模型提供商",
    "plugins.installed.family.browser.displayName": "%@ 瀏覽器",
    "plugins.installed.family.browser.description": "用於開啟網頁、檢查內容並與網站互動的瀏覽器自動化能力。",
    "plugins.installed.family.browser.category": "瀏覽器",
    "plugins.installed.family.speech.displayName": "%@ 語音",
    "plugins.installed.family.speech.description": "用於轉錄、語音或音訊模型工作流程的語音能力。",
    "plugins.installed.family.speech.category": "語音",
    "plugins.installed.family.memory.displayName": "%@ 記憶",
    "plugins.installed.family.memory.description": "用於在 OpenClaw 會話之間保留可重用上下文的記憶儲存能力。",
    "plugins.installed.family.memory.category": "記憶",
    "plugins.installed.family.proxy.displayName": "%@ 代理",
    "plugins.installed.family.proxy.description": "用於透過相容提供商或本地服務路由模型請求的代理能力。",
    "plugins.installed.family.proxy.category": "代理",
    "plugins.installed.family.runtime.displayName": "%@",
    "plugins.installed.family.runtime.description": "OpenClaw 用來提供內建外掛行為的核心執行階段能力。",
    "plugins.installed.family.runtime.category": "執行階段",
    "plugins.installed.family.plugin.displayName": "%@",
    "plugins.installed.family.plugin.description": "已安裝的 OpenClaw 外掛。",
    "plugins.installed.family.plugin.category": "外掛",
    "plugins.installed.detail.pluginId": "**外掛 ID：** `%@`",
    "plugins.installed.detail.status": "**狀態：** %@",
    "plugins.installed.detail.version": "**版本：** %@"
}

SETTINGS = {
    "settings.i18n.placeholder": "Settings translations are provided by Localizable.xcstrings.",
    "budget.action.resetAgentSession": "Reset agent session",
    "billing.expires": "Expires %@",
    "settings.shell.backToApp": "Back to app",
    "settings.shell.searchPlaceholder": "Search settings...",
    "settings.refreshing": "Refreshing...",
    "settings.updating": "Updating...",
    "settings.group.account": "Account",
    "settings.group.system": "System",
    "settings.group.configuration": "Configuration",
    "settings.group.advanced": "Advanced",
    "All settings": "All settings",
    "Local user": "Local user",
    "Add Provider": "Add Provider",
    "Delete Provider": "Delete Provider",
    "Choose Provider": "Choose Provider",
    "Custom Providers": "Custom Providers",
    "settings.provider.custom.addTitle": "Add Custom Provider",
    "settings.provider.custom.addSubtitle": "Enter a base URL directly. API key is optional for local providers.",
    "settings.provider.custom.apiKeyOptional": "API Key Optional",
    "settings.provider.custom.confirmDelete": "Click again to delete provider",
    "settings.provider.custom.needsSetup": "Needs setup",
    "settings.provider.custom.emptyTitle": "No custom providers yet",
    "settings.provider.custom.emptyDetail": "Add a provider above with its base URL and API key.",
    "settings.provider.custom.showModelList": "Show model list",
    "settings.provider.custom.hideModelList": "Hide model list",
    "settings.provider.custom.removeModel": "Remove Model",
    "settings.provider.custom.addModelSubtitle": "Register a model ID exposed by this provider.",
    "settings.provider.custom.supportsImageInput": "Supports image input",
    "settings.provider.custom.supportsReasoning": "Supports reasoning",
    "No custom providers yet": "No custom providers yet",
    "Use the plus button to add a provider and API key.": "Use the plus button to add a provider and API key.",
    "All preset providers are already added.": "All preset providers are already added.",
    "Needs key": "Needs key",
    "Selected": "Selected",
    "Editing": "Editing",
    "Use": "Use",
    "Provider details": "Provider details",
}
SETTINGS_ZH_HANS = {
    "settings.i18n.placeholder": "设置翻译由 Localizable.xcstrings 提供。",
    "budget.action.resetAgentSession": "重置 Agent 会话",
    "billing.expires": "过期时间：%@",
    "settings.shell.backToApp": "返回应用",
    "settings.shell.searchPlaceholder": "搜索设置...",
    "settings.refreshing": "正在刷新...",
    "settings.updating": "正在更新...",
    "settings.group.account": "账户",
    "settings.group.system": "系统",
    "settings.group.configuration": "配置",
    "settings.group.advanced": "高级",
    "All settings": "全部设置",
    "Local user": "本地用户",
    "Add Provider": "添加提供商",
    "Delete Provider": "删除提供商",
    "Choose Provider": "选择提供商",
    "Custom Providers": "自定义提供商",
    "settings.provider.custom.addTitle": "添加自定义提供商",
    "settings.provider.custom.addSubtitle": "直接输入 Base URL。本地提供商可以不填写 API Key。",
    "settings.provider.custom.apiKeyOptional": "API Key（可选）",
    "settings.provider.custom.confirmDelete": "再次点击删除提供商",
    "settings.provider.custom.needsSetup": "需要设置",
    "settings.provider.custom.emptyTitle": "还没有自定义提供商",
    "settings.provider.custom.emptyDetail": "在上方添加提供商，并填写 Base URL 和 API Key。",
    "settings.provider.custom.showModelList": "显示模型列表",
    "settings.provider.custom.hideModelList": "隐藏模型列表",
    "settings.provider.custom.removeModel": "移除模型",
    "settings.provider.custom.addModelSubtitle": "注册该提供商暴露的模型 ID。",
    "settings.provider.custom.supportsImageInput": "支持图像输入",
    "settings.provider.custom.supportsReasoning": "支持推理",
    "No custom providers yet": "还没有自定义提供商",
    "Use the plus button to add a provider and API key.": "点击加号添加提供商并填写 API Key。",
    "All preset providers are already added.": "所有预设提供商都已添加。",
    "Needs key": "需要密钥",
    "Selected": "已选择",
    "Editing": "正在编辑",
    "Use": "使用",
    "Provider details": "提供商详情",
}
SETTINGS_ZH_HANT = {
    "settings.i18n.placeholder": "設定翻譯由 Localizable.xcstrings 提供。",
    "budget.action.resetAgentSession": "重置 Agent 會話",
    "billing.expires": "到期時間：%@",
    "settings.shell.backToApp": "返回應用程式",
    "settings.shell.searchPlaceholder": "搜尋設定...",
    "settings.refreshing": "正在重新整理...",
    "settings.updating": "正在更新...",
    "settings.group.account": "帳戶",
    "settings.group.system": "系統",
    "settings.group.configuration": "設定",
    "settings.group.advanced": "進階",
    "All settings": "全部設定",
    "Local user": "本機使用者",
    "Add Provider": "新增提供商",
    "Delete Provider": "刪除提供商",
    "Choose Provider": "選擇提供商",
    "Custom Providers": "自訂提供商",
    "settings.provider.custom.addTitle": "新增自訂提供商",
    "settings.provider.custom.addSubtitle": "直接輸入 Base URL。本機提供商可以不填 API Key。",
    "settings.provider.custom.apiKeyOptional": "API Key（可選）",
    "settings.provider.custom.confirmDelete": "再次點擊刪除提供商",
    "settings.provider.custom.needsSetup": "需要設定",
    "settings.provider.custom.emptyTitle": "尚無自訂提供商",
    "settings.provider.custom.emptyDetail": "在上方新增提供商，並填寫 Base URL 和 API Key。",
    "settings.provider.custom.showModelList": "顯示模型列表",
    "settings.provider.custom.hideModelList": "隱藏模型列表",
    "settings.provider.custom.removeModel": "移除模型",
    "settings.provider.custom.addModelSubtitle": "註冊該提供商暴露的模型 ID。",
    "settings.provider.custom.supportsImageInput": "支援圖像輸入",
    "settings.provider.custom.supportsReasoning": "支援推理",
    "No custom providers yet": "尚無自訂提供商",
    "Use the plus button to add a provider and API key.": "點擊加號新增提供商並填寫 API Key。",
    "All preset providers are already added.": "所有預設提供商都已新增。",
    "Needs key": "需要密鑰",
    "Selected": "已選取",
    "Editing": "正在編輯",
    "Use": "使用",
    "Provider details": "提供商詳情",
}

AGENTS_UI = {
    "agents.search.placeholder": "Search agents...",
    "agents.empty.noMatching": "No matching agents",
    "agents.detail.vibe": "Vibe",
    "agents.detail.personaContent": "Persona Content",
    "agents.action.recruit": "Recruit",
    "agents.action.recruiting": "Recruiting...",
    "agents.action.recruited": "Recruited",
    "agents.alert.recruitFailed": "Recruit Failed",
    "agents.alert.ok": "OK",
}

AGENTS_UI_ZH_HANS = {
    "agents.search.placeholder": "搜索助手...",
    "agents.empty.noMatching": "没有匹配的助手",
    "agents.detail.vibe": "风格",
    "agents.detail.personaContent": "人设内容",
    "agents.action.recruit": "招募",
    "agents.action.recruiting": "招募中...",
    "agents.action.recruited": "已招募",
    "agents.alert.recruitFailed": "招募失败",
    "agents.alert.ok": "确定",
}

AGENTS_UI_ZH_HANT = {
    "agents.search.placeholder": "搜尋助手...",
    "agents.empty.noMatching": "沒有符合的助手",
    "agents.detail.vibe": "風格",
    "agents.detail.personaContent": "人設內容",
    "agents.action.recruit": "招募",
    "agents.action.recruiting": "招募中...",
    "agents.action.recruited": "已招募",
    "agents.alert.recruitFailed": "招募失敗",
    "agents.alert.ok": "確定",
}


def supported_languages():
    text = LANGUAGE_MANAGER.read_text(encoding="utf-8")
    return [m.group(1) for m in re.finditer(r'Language\(id:\s*"([^"]+)"', text) if m.group(1) != "system"]


def slug(value):
    return re.sub(r"[^a-z0-9]+", ".", value.lower()).strip(".") or "item"


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def frontmatter_and_body(markdown):
    text = markdown.replace("\r\n", "\n")
    if not text.startswith("---\n"):
        return {}, text.strip()
    end = text.find("\n---", 4)
    if end < 0:
        return {}, text.strip()
    fm = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        fm[k.strip()] = v.strip().strip('"\'')
    return fm, text[end + 4:].strip()


def first_paragraph(body):
    for line in body.splitlines():
        t = line.strip()
        if t and not t.startswith("#") and not t.startswith("```"):
            return t
    return ""


def display_name(identifier):
    return " ".join(part[:1].upper() + part[1:] for part in re.split(r"[-_]+", identifier) if part)


PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?(?:[-+#0]*)?(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]")


def placeholder_signature(value):
    tokens = []
    for match in PLACEHOLDER_PATTERN.finditer(value or ""):
        token = match.group(0)
        if token == "%%":
            continue
        tokens.append(re.sub(r"^%(\d+\$)", "%", token))
    return tokens


def zh_skill_name(name):
    mapping = {
        "playwright": "Playwright 浏览器自动化",
        "openai-docs": "OpenAI 文档",
        "agent-reach": "互联网调研",
        "skill-creator": "技能创建器",
        "plugin-creator": "插件创建器",
        "imagegen": "图像生成",
        "pdf": "PDF 处理",
        "dws": "钉钉工作台",
        "figma": "Figma",
    }
    return mapping.get(name, display_name(name))


def zh_skill_description(name, english):
    return f"{zh_skill_name(name)}技能：{english}" if english else f"{zh_skill_name(name)}技能，适合处理相关任务。"


def zh_plugin_name(name, display):
    mapping = {
        "dingtalk": "钉钉",
        "wechat": "微信",
        "weixin": "微信",
        "telegram": "Telegram",
        "discord": "Discord",
        "slack": "Slack",
        "context-mode": "Context Mode",
    }
    key = name.lower()
    return mapping.get(key, display)


PLUGIN_CATALOG_PROFILES_PATH = ROOT / "scripts" / "i18n_plugin_catalog_profiles.json"


def load_plugin_catalog_profiles():
    profiles = read_json(PLUGIN_CATALOG_PROFILES_PATH, {})
    if not isinstance(profiles, dict):
        return {}
    return profiles


PLUGIN_CATALOG_PROFILES = load_plugin_catalog_profiles()


def validate_plugin_catalog_profiles(languages):
    required_fields = {
        "agent",
        "plugin",
        "skill",
        "separator",
        "featurePrefix",
        "capabilitiesDefault",
        "description",
        "longDescription",
        "categories",
        "capabilities",
        "features",
    }
    required_category_keys = {
        "Business & Operations",
        "Communication",
        "Creativity",
        "Data & Analytics",
        "Developer Tools",
        "Education & Research",
        "Finance",
        "Other",
        "Productivity",
        "Security",
        "Travel",
    }
    required_capability_keys = {
        "analysis",
        "auth",
        "backend",
        "companyData",
        "database",
        "file",
        "finance",
        "general",
        "interactive",
        "mcp",
        "monitoring",
        "read",
        "realtime",
        "research",
        "scheduling",
        "search",
        "storage",
        "write",
    }
    required_feature_keys = {
        "codeReview",
        "dataViz",
        "issueEvents",
        "mcp",
        "mobileApps",
        "papers",
        "research",
        "webApps",
    }
    missing = []
    for lang in languages:
        if lang == "en":
            continue
        profile = PLUGIN_CATALOG_PROFILES.get(lang)
        if not isinstance(profile, dict):
            missing.append(f"{lang}: profile")
            continue
        missing_fields = required_fields - set(profile)
        if missing_fields:
            missing.append(f"{lang}: fields {sorted(missing_fields)}")
            continue
        for field, required_keys in [
            ("categories", required_category_keys),
            ("capabilities", required_capability_keys),
            ("features", required_feature_keys),
        ]:
            values = profile.get(field, {})
            if not isinstance(values, dict):
                missing.append(f"{lang}: {field} is not an object")
                continue
            missing_keys = required_keys - set(values)
            if missing_keys:
                missing.append(f"{lang}: {field} {sorted(missing_keys)}")
    if missing:
        raise SystemExit("Invalid plugin catalog i18n profiles:\n" + "\n".join(missing))


def plugin_catalog_profile(lang):
    return PLUGIN_CATALOG_PROFILES.get(lang)


def catalog_noun(lang, kind):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return kind
    return profile.get(kind, profile.get("plugin", kind))


def localized_plugin_category(category, lang):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return category
    return profile.get("categories", {}).get(category, profile.get("categories", {}).get("Other", profile["plugin"]))


def plugin_capability_kind(capability):
    lower = capability.lower()
    if lower in {"read"}:
        return "read"
    if lower in {"write", "writes"}:
        return "write"
    if lower == "interactive":
        return "interactive"
    if lower == "mcp":
        return "mcp"
    if "auth" in lower or "role" in lower or "permission" in lower:
        return "auth"
    if "analysis" in lower or "analytics" in lower or "analyze" in lower:
        return "analysis"
    if "backend" in lower or "server" in lower:
        return "backend"
    if "database" in lower or "schema" in lower:
        return "database"
    if "file generation" in lower:
        return "file"
    if "file storage" in lower or "folder" in lower:
        return "storage"
    if any(token in lower for token in ["finance", "financial", "credit", "rating", "earnings", "market"]):
        return "finance"
    if any(token in lower for token in ["company", "ownership", "officer", "firmographic", "entity"]):
        return "companyData"
    if "mobile" in lower:
        return "mobile"
    if any(token in lower for token in ["monitoring", "outlook", "trigger"]):
        return "monitoring"
    if "realtime" in lower or "reactive" in lower:
        return "realtime"
    if "research" in lower or "document" in lower:
        return "research"
    if "scheduled" in lower:
        return "scheduling"
    if any(token in lower for token in ["search", "summarization", "resolution", "identification"]):
        return "search"
    if "scaling" in lower:
        return "backend"
    return "general"


def localized_plugin_capability(capability, lang):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return capability
    kind = plugin_capability_kind(capability)
    return profile.get("capabilities", {}).get(kind, profile["capabilitiesDefault"])


def localized_join(values, profile):
    values = [v for v in values if v]
    if not values:
        return ""
    if len(values) == 1:
        return values[0]
    return profile["separator"].join(values)


def plugin_feature_keys(name, description, long_description):
    text = f"{name} {description}".lower()
    extended = f"{text} {long_description}".lower()
    keys = []
    if re.search(r"\bmcp\b", extended):
        keys.append("mcp")
    if "issue" in extended and "event" in extended:
        keys.append("issueEvents")
    if re.search(r"\b(ios|android|expo|react native|mobile)\b", text):
        keys.append("mobileApps")
    if re.search(r"\b(web app|web apps|frontend|browser testing)\b", text):
        keys.append("webApps")
    if "code review" in text:
        keys.append("codeReview")
    if re.search(r"\b(paper|papers|citation|citations|zotero)\b", text):
        keys.append("papers")
    if re.search(r"\b(life-science|life sciences|research|evidence synthesis)\b", text):
        keys.append("research")
    if re.search(r"\b(visualization|visualisation|visualizations|visualisations)\b", text):
        keys.append("dataViz")
    return list(dict.fromkeys(keys[:2]))


def localized_catalog_features(name, description, long_description, lang):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return ""
    features = [
        profile.get("features", {}).get(key)
        for key in plugin_feature_keys(name, description, long_description)
    ]
    features = [feature for feature in features if feature]
    if not features:
        return ""
    return profile["featurePrefix"] + localized_join(features, profile)


def localized_plugin_features(name, description, long_description, lang):
    return localized_catalog_features(name, description, long_description, lang)


def localized_plugin_capabilities(capabilities, lang):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return capabilities
    localized = [localized_plugin_capability(cap, lang) for cap in capabilities]
    deduped = list(dict.fromkeys(localized))
    return deduped or [profile["capabilitiesDefault"]]


def localized_plugin_catalog_text(lang, display, category, capabilities, description, long_description, field, noun=None):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return None
    localized_category = localized_plugin_category(category, lang)
    localized_caps = localized_join(localized_plugin_capabilities(capabilities, lang), profile)
    features = localized_catalog_features(display, description, long_description, lang)
    template = profile[field]
    return template.format(
        display=display,
        plugin=noun or profile["plugin"],
        category=localized_category,
        capabilities=localized_caps,
        features=features,
    )


def contains_cjk(value):
    return any("\u3400" <= char <= "\u9fff" for char in value)


def english_tokens(value):
    ignored = {"ai", "api", "app", "apps", "ios", "macos", "mcp", "openclaw", "swiftui", "ui", "web"}
    return {
        token.lower()
        for token in re.findall(r"[A-Za-z][A-Za-z0-9.+-]{2,}", value or "")
        if token.lower() not in ignored
    }


def has_high_english_source_overlap(localized, english):
    source = english_tokens(english)
    if len(source) < 3:
        return False
    localized_tokens = english_tokens(localized)
    if not localized_tokens:
        return False
    return len(source.intersection(localized_tokens)) / len(source) >= 0.6


def usable_localized_overlay(lang, value, english):
    if not isinstance(value, str) or not value.strip():
        return False
    if lang in {"zh-Hans", "zh-Hant"}:
        return contains_cjk(value) and not has_high_english_source_overlap(value, english or "")
    return value.strip() != (english or "").strip()


def division_category(division):
    mapping = {
        "Academic": "Education & Research",
        "Design": "Creativity",
        "Engineering": "Developer Tools",
        "Game Development": "Creativity",
        "Marketing": "Business & Operations",
        "Paid Media": "Business & Operations",
        "Product": "Productivity",
        "Project Management": "Productivity",
        "Sales": "Business & Operations",
        "Spatial Computing": "Developer Tools",
        "Specialized": "Other",
        "Support": "Business & Operations",
        "Testing": "Developer Tools",
    }
    return mapping.get(division, "Other")


def text_category(name, description, content="", default="Other"):
    text = f"{name} {description}".lower()
    extended = f"{text} {content}".lower()
    if re.search(r"\b(security|auth|permission|compliance|privacy)\b", text):
        return "Security"
    if re.search(r"\b(finance|market|stock|tax|accounting|credit)\b", text):
        return "Finance"
    if re.search(r"\b(design|figma|image|visual|creative|writing|story|brand)\b", text):
        return "Creativity"
    if re.search(r"\b(data|analytics|database|spreadsheet|chart|visualization)\b", text):
        return "Data & Analytics"
    if re.search(r"\b(research|paper|academic|citation|anthropolog|history|geograph|psycholog)\b", text):
        return "Education & Research"
    if re.search(r"\b(slack|telegram|discord|dingtalk|wechat|email|message|communication)\b", text):
        return "Communication"
    if re.search(r"\b(schedule|calendar|task|productivity|workflow|automation)\b", text):
        return "Productivity"
    if re.search(r"\b(travel|hotel|flight|trip)\b", text):
        return "Travel"
    if re.search(r"\b(test|qa|debug|playwright|browser|frontend|backend|swift|python|code|github|git)\b", text):
        return "Developer Tools"
    if re.search(r"\b(css|component|layout|accessibility|responsive)\b", extended):
        return "Creativity"
    return default


def text_capabilities(name, description, content=""):
    text = f"{name} {description}".lower()
    extended = f"{text} {content}".lower()
    capabilities = []
    if re.search(r"\b(read|inspect|review|audit|auditor|assess|assessment|evidence|compliance|analy[sz]e|analysis|diagnos)\b", text):
        capabilities.append("analysis")
    if re.search(r"\b(write|create|generate|build|implement|edit|fix|refactor)\b", text):
        capabilities.append("write")
    if re.search(r"\b(search|research|lookup|find|browse)\b", text):
        capabilities.append("search")
    if re.search(r"\b(file|document|markdown|pdf|spreadsheet|slide)\b", text):
        capabilities.append("file generation")
    if re.search(r"\b(database|schema|sql|postgres|prisma)\b", text):
        capabilities.append("database")
    if re.search(r"\b(mcp|tool|plugin|api)\b", extended):
        capabilities.append("mcp")
    if re.search(r"\b(schedule|calendar|cron|automation)\b", text):
        capabilities.append("scheduled tasks")
    return list(dict.fromkeys(capabilities[:3])) or ["task-specific guidance"]


def localized_catalog_summary(lang, display, kind, category, capabilities, description, content, field):
    return localized_plugin_catalog_text(
        lang,
        display,
        category,
        capabilities,
        description,
        content,
        field,
        noun=catalog_noun(lang, kind),
    )


def localized_catalog_markdown(lang, display, kind, category, capabilities, description, content):
    short_text = localized_catalog_summary(lang, display, kind, category, capabilities, description, content, "description")
    long_text = localized_catalog_summary(lang, display, kind, category, capabilities, description, content, "longDescription")
    parts = [short_text, long_text]
    return "\n\n".join(dict.fromkeys(part for part in parts if part))


def generic_common_localizations(lang):
    profile = plugin_catalog_profile(lang)
    if not profile:
        return {}
    agent = catalog_noun(lang, "agent")
    skill = catalog_noun(lang, "skill")
    plugin = catalog_noun(lang, "plugin")
    productivity = localized_plugin_category("Productivity", lang)
    developer_tools = localized_plugin_category("Developer Tools", lang)
    other = localized_plugin_category("Other", lang)
    search = localized_plugin_capability("search", lang)
    read = localized_plugin_capability("read", lang)
    write = localized_plugin_capability("write", lang)
    return {
        "common.action.create": profile.get("actions", {}).get("create", write),
        "common.action.save": profile.get("actions", {}).get("save", write),
        "common.action.send": profile.get("actions", {}).get("send", write),
        "common.action.refresh": profile.get("actions", {}).get("refresh", read),
        "common.toast.copied": read,
        "common.empty.parenthesized": profile.get("empty", "(empty)"),
        "help.status.online": write,
        "help.status.offline": "offline",
        "help.welcome.title": localized_catalog_summary(lang, "GetClowHub", "agent", "Productivity", ["task-specific guidance"], "", "", "description"),
        "help.welcome.subtitle": localized_catalog_summary(lang, "GetClowHub", "agent", "Productivity", ["search"], "", "", "longDescription"),
        "help.status.typing": localized_catalog_summary(lang, "GetClowHub", "agent", "Communication", ["write"], "", "", "description"),
        "help.status.offlineFaq": localized_catalog_summary(lang, "FAQ", "agent", "Education & Research", ["read"], "", "", "description"),
        "help.input.placeholder": localized_catalog_summary(lang, "GetClowHub", "agent", "Communication", ["search"], "", "", "description"),
        "help.quick.status.start": localized_catalog_summary(lang, "service start", "agent", "Developer Tools", ["analysis"], "", "", "description"),
        "help.quick.status.restart": localized_catalog_summary(lang, "service restart", "agent", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.status.systemInfo": localized_catalog_summary(lang, "system information", "agent", "Developer Tools", ["read"], "", "", "description"),
        "help.quick.config.models": localized_catalog_summary(lang, "model configuration", "agent", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.config.port": localized_catalog_summary(lang, "port configuration", "agent", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.config.provider": localized_catalog_summary(lang, "provider switching", "agent", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.chat.slash": localized_catalog_summary(lang, "slash commands", "agent", "Productivity", ["read"], "", "", "description"),
        "help.quick.chat.switchAssistant": localized_catalog_summary(lang, f"{agent} switching", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.chat.history": localized_catalog_summary(lang, "message history", "agent", "Productivity", ["read"], "", "", "description"),
        "help.quick.cron.create": localized_catalog_summary(lang, "cron job creation", "agent", "Productivity", ["scheduled tasks"], "", "", "description"),
        "help.quick.cron.expression": localized_catalog_summary(lang, "cron expressions", "agent", "Productivity", ["scheduled tasks"], "", "", "description"),
        "help.quick.cron.pause": localized_catalog_summary(lang, "task pause", "agent", "Productivity", ["scheduled tasks"], "", "", "description"),
        "help.quick.persona.edit": localized_catalog_summary(lang, "AI personality editing", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.persona.files": localized_catalog_summary(lang, "persona files", "agent", "Productivity", ["read"], "", "", "description"),
        "help.quick.persona.preview": localized_catalog_summary(lang, "persona preview", "agent", "Productivity", ["read"], "", "", "description"),
        "help.quick.subAgents.create": localized_catalog_summary(lang, f"{agent} creation", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.subAgents.switch": localized_catalog_summary(lang, f"{agent} switching", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.subAgents.delete": localized_catalog_summary(lang, f"{agent} deletion", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.skills.install": localized_catalog_summary(lang, f"{skill} installation", "skill", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.skills.status": localized_catalog_summary(lang, f"{skill} status", "skill", "Developer Tools", ["read"], "", "", "description"),
        "help.quick.skills.findMore": localized_catalog_summary(lang, f"{skill} catalog", "skill", "Developer Tools", ["search"], "", "", "description"),
        "help.quick.models.default": localized_catalog_summary(lang, "default model", "agent", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.models.fallback": localized_catalog_summary(lang, "fallback model", "agent", "Developer Tools", ["read"], "", "", "description"),
        "help.quick.models.image": localized_catalog_summary(lang, "image model", "agent", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.channels.telegram": localized_catalog_summary(lang, "Telegram channel", "plugin", "Communication", ["write"], "", "", "description"),
        "help.quick.channels.status": localized_catalog_summary(lang, "channel status", "plugin", "Communication", ["read"], "", "", "description"),
        "help.quick.channels.remove": localized_catalog_summary(lang, "channel removal", "plugin", "Communication", ["write"], "", "", "description"),
        "help.quick.plugins.enable": localized_catalog_summary(lang, f"{plugin} enable", "plugin", "Developer Tools", ["write"], "", "", "description"),
        "help.quick.plugins.available": localized_catalog_summary(lang, f"{plugin} catalog", "plugin", "Developer Tools", ["search"], "", "", "description"),
        "help.quick.plugins.status": localized_catalog_summary(lang, f"{plugin} status", "plugin", "Developer Tools", ["read"], "", "", "description"),
        "help.quick.logs.search": localized_catalog_summary(lang, "log search", "agent", "Developer Tools", ["search"], "", "", "description"),
        "help.quick.logs.colors": localized_catalog_summary(lang, "log colors", "agent", "Developer Tools", ["read"], "", "", "description"),
        "help.quick.logs.export": localized_catalog_summary(lang, "log export", "agent", "Developer Tools", ["file generation"], "", "", "description"),
        "help.quick.budget.set": localized_catalog_summary(lang, "budget settings", "agent", "Finance", ["write"], "", "", "description"),
        "help.quick.budget.alerts": localized_catalog_summary(lang, "budget alerts", "agent", "Finance", ["monitoring"], "", "", "description"),
        "help.quick.budget.costs": localized_catalog_summary(lang, "cost view", "agent", "Finance", ["read"], "", "", "description"),
        "help.quick.billing.view": localized_catalog_summary(lang, "billing view", "agent", "Finance", ["read"], "", "", "description"),
        "help.quick.billing.limit": localized_catalog_summary(lang, "spend limit", "agent", "Finance", ["read"], "", "", "description"),
        "help.quick.billing.reset": localized_catalog_summary(lang, "budget reset", "agent", "Finance", ["read"], "", "", "description"),
        "help.quick.market.install": localized_catalog_summary(lang, f"{agent} installation", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.market.contents": localized_catalog_summary(lang, "marketplace catalog", "agent", "Productivity", ["search"], "", "", "description"),
        "help.quick.market.uninstall": localized_catalog_summary(lang, f"{agent} uninstall", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.tasks.create": localized_catalog_summary(lang, "automation creation", "agent", "Productivity", ["scheduled tasks"], "", "", "description"),
        "help.quick.tasks.pause": localized_catalog_summary(lang, "automation pause", "agent", "Productivity", ["scheduled tasks"], "", "", "description"),
        "help.quick.tasks.edit": localized_catalog_summary(lang, "automation edit", "agent", "Productivity", ["write"], "", "", "description"),
        "help.quick.outputs.what": localized_catalog_summary(lang, "outputs", "agent", "Productivity", ["read"], "", "", "description"),
        "help.quick.outputs.hidden": localized_catalog_summary(lang, "hidden config files", "agent", "Developer Tools", ["read"], "", "", "description"),
        "help.quick.outputs.open": localized_catalog_summary(lang, "generated files", "agent", "Productivity", ["file generation"], "", "", "description"),
        "subAgents.title": f"Multi-{agent}",
        "subAgents.count.agents": f"(%lld {agent})",
        "subAgents.action.new": f"{agent} +",
        "subAgents.action.openWorkspace": localized_plugin_category("Productivity", lang),
        "subAgents.loading.agents": f"{agent}...",
        "subAgents.loading.models": "models...",
        "subAgents.empty.title": f"{agent}: 0",
        "subAgents.empty.detail": localized_catalog_summary(lang, agent, "agent", "Productivity", ["write"], "", "", "description"),
        "subAgents.toast.fileSaved": "%@ %@",
        "subAgents.toast.deleted": f"{agent} \"%@\"",
        "subAgents.toast.modelChanged": "%@ → %@",
        "subAgents.alert.deleteTitle": f"{agent}",
        "subAgents.alert.deleteMessage": f"{agent} \"%@\"?",
        "subAgents.model.label": "Model:",
        "subAgents.model.default": "Default",
        "subAgents.model.defaultInherit": "Default",
        "subAgents.model.defaultFromConfig": "Default",
        "subAgents.model.defaultTag": "(default)",
        "subAgents.create.title": f"{agent}",
        "subAgents.create.agentId": "Agent ID",
        "subAgents.create.agentIdPlaceholder": "news-helper",
        "subAgents.create.agentIdHelp": localized_catalog_summary(lang, "Agent ID", "agent", "Developer Tools", ["read"], "", "", "description"),
        "subAgents.create.displayName": "Display Name",
        "subAgents.create.displayNamePlaceholder": "News Helper",
        "subAgents.create.displayNameHelp": localized_catalog_summary(lang, "IDENTITY.md", "agent", "Developer Tools", ["file generation"], "", "", "description"),
        "subAgents.create.model": "Model",
        "subAgents.create.division": other,
        "subAgents.create.divisionHelp": localized_catalog_summary(lang, agent, "agent", "Productivity", ["read"], "", "", "description"),
        "collab.title": localized_catalog_summary(lang, "collaboration tasks", "agent", "Productivity", ["scheduled tasks"], "", "", "description"),
        "collab.empty.title": f"0 {agent}",
        "collab.empty.detail": localized_catalog_summary(lang, "Commander", "agent", "Productivity", ["write"], "", "", "description"),
        "collab.history.help": f"%lld {read}",
        "collab.history.title": read,
        "collab.history.records": f"%lld {read}",
        "collab.history.subtasks": "%lld/%lld",
        "collab.commander.settings": "Commander",
        "collab.panel.collapse": "−",
        "collab.panel.close": "×",
        "collab.progress.label": "%@",
        "collab.phase.understanding": localized_catalog_summary(lang, "requirements", "agent", "Productivity", ["analysis"], "", "", "description"),
        "collab.phase.researching": localized_catalog_summary(lang, "research", "agent", "Education & Research", ["research"], "", "", "description"),
        "collab.phase.decomposing": localized_catalog_summary(lang, "task decomposition", "agent", "Productivity", ["analysis"], "", "", "description"),
        "collab.phase.awaitingApproval": localized_catalog_summary(lang, "approval", "agent", "Productivity", ["read"], "", "", "description"),
        "collab.phase.running": localized_catalog_summary(lang, "running", "agent", "Productivity", ["write"], "", "", "description"),
        "collab.phase.verifying": localized_catalog_summary(lang, "verification", "agent", "Developer Tools", ["analysis"], "", "", "description"),
        "collab.phase.summarizing": localized_catalog_summary(lang, "summary", "agent", "Productivity", ["write"], "", "", "description"),
        "collab.phase.done": profile.get("done", "Done"),
        "collab.phase.runningPlain": write,
        "collab.phase.verifyingPlain": read,
        "collab.phase.summarizingPlain": write,
        "collab.phase.preparing": productivity,
        "collab.requirements.gathering": localized_catalog_summary(lang, "requirements", "agent", "Productivity", ["analysis"], "", "", "description"),
        "collab.final.summary": localized_catalog_summary(lang, "final summary", "agent", "Productivity", ["write"], "", "", "description"),
        "collab.settings.agentTimeout": f"{agent} timeout",
        "collab.settings.custom": other,
        "collab.settings.hours": "h",
        "collab.settings.timeoutHelp": "%@",
        "collab.settings.maxConcurrency": localized_catalog_summary(lang, "concurrency", "agent", "Developer Tools", ["analysis"], "", "", "description"),
        "collab.settings.unlimited": "∞",
        "collab.settings.maxConcurrencyHelp": localized_catalog_summary(lang, "concurrency", "agent", "Developer Tools", ["read"], "", "", "description"),
        "collab.settings.retryContextLength": localized_catalog_summary(lang, "retry context", "agent", "Developer Tools", ["read"], "", "", "description"),
        "collab.settings.chars": "chars",
        "collab.settings.retryContextHelp": localized_catalog_summary(lang, "retry history", "agent", "Developer Tools", ["read"], "", "", "description"),
        "collab.settings.resetDefaults": "Default",
        "collab.action.cancelAll": "Cancel",
        "collab.task.retry": localized_catalog_summary(lang, "retry", "agent", "Developer Tools", ["write"], "", "", "description"),
        "collab.task.forceComplete": localized_catalog_summary(lang, "force complete", "agent", "Developer Tools", ["write"], "", "", "description"),
        "collab.task.skip": localized_catalog_summary(lang, "skip", "agent", "Productivity", ["write"], "", "", "description"),
        "collab.task.dependsOn": "#%@",
        "collab.task.error": "%@",
        "collab.process.running": write,
        "collab.process.ended": "ended",
        "collab.process.lines": "%lld",
        "collab.process.files": "%lld",
        "collab.process.longRunning": localized_catalog_summary(lang, "long running", "agent", "Developer Tools", ["monitoring"], "", "", "description"),
        "collab.output.files": localized_catalog_summary(lang, "output files", "agent", "Productivity", ["file generation"], "", "", "description"),
        "collab.agent.running": write,
    }


def localized_string_catalog_label(settings_catalog, lang, source_key, fallback=None):
    fallback = fallback or source_key
    if lang == "en":
        return fallback
    value = settings_catalog.get(lang, {}).get(source_key)
    if isinstance(value, str) and value.strip() and value != source_key:
        return value
    return fallback


def has_string_catalog_translation(settings_catalog, lang, source_key):
    if lang == "en":
        return True
    value = settings_catalog.get(lang, {}).get(source_key)
    return isinstance(value, str) and value.strip() and value != source_key


def localized_composite_label(settings_catalog, lang, action_key, action_fallback, object_key, object_fallback):
    action = localized_string_catalog_label(settings_catalog, lang, action_key, action_fallback)
    object_label = localized_string_catalog_label(settings_catalog, lang, object_key, object_fallback)
    return f"{action} {object_label}".strip()


def common_short_label_overrides(lang, settings_catalog, current_common):
    overrides = {
        "common.action.refresh": localized_string_catalog_label(settings_catalog, lang, "Refresh", "Refresh"),
        "common.action.delete": localized_string_catalog_label(settings_catalog, lang, "Delete", "Delete"),
        "catalog.action.enable": localized_string_catalog_label(settings_catalog, lang, "Enable", "Enable"),
        "catalog.action.disable": localized_string_catalog_label(settings_catalog, lang, "Disable", "Disable"),
        "catalog.action.close": localized_string_catalog_label(settings_catalog, lang, "Close", "Close"),
        "subAgents.action.new": localized_string_catalog_label(settings_catalog, lang, "New Agent", "New Agent"),
        "dashboard.session.newChat": localized_string_catalog_label(settings_catalog, lang, "New chat", "New chat"),
        "dashboard.tooltip.attachFile": localized_string_catalog_label(settings_catalog, lang, "Attach File", "Attach File"),
        "dashboard.tooltip.searchChats": localized_string_catalog_label(settings_catalog, lang, "Search chats", "Search chats"),
        "dashboard.tooltip.taskRunning": localized_string_catalog_label(
            settings_catalog,
            lang,
            "Task running",
            localized_string_catalog_label(settings_catalog, lang, "Running", "Task running"),
        ),
    }
    if has_string_catalog_translation(settings_catalog, lang, "Edit"):
        overrides["common.action.edit"] = localized_string_catalog_label(settings_catalog, lang, "Edit", "Edit")

    for object_key, object_fallback, hide_key, show_key in [
        ("Terminal", "Terminal", "dashboard.tooltip.hideTerminal", "dashboard.tooltip.showTerminal"),
        ("Outputs", "Outputs", "dashboard.tooltip.hideOutputs", "dashboard.tooltip.showOutputs"),
    ]:
        if lang == "en" or has_string_catalog_translation(settings_catalog, lang, object_key):
            overrides[hide_key] = localized_composite_label(settings_catalog, lang, "Hide", "Hide", object_key, object_fallback)
            overrides[show_key] = localized_composite_label(settings_catalog, lang, "Show", "Show", object_key, object_fallback)
        else:
            if hide_key not in current_common:
                overrides[hide_key] = current_common.get(hide_key, COMMON[hide_key])
            if show_key not in current_common:
                overrides[show_key] = current_common.get(show_key, COMMON[show_key])
    return overrides


def settings_short_label_overrides(lang, settings_catalog, settings):
    overrides = {}
    billing_refresh = localized_string_catalog_label(settings_catalog, lang, "billing.refresh", "Refresh Billing")
    if settings.get("billing.refresh") in {None, "billing.refresh"} or billing_refresh != "Refresh Billing":
        overrides["billing.refresh"] = billing_refresh

    if lang == "zh-Hans":
        overrides["billing.expires"] = SETTINGS_ZH_HANS["billing.expires"]
    elif lang == "zh-Hant":
        overrides["billing.expires"] = SETTINGS_ZH_HANT["billing.expires"]
    else:
        overrides["billing.expires"] = localized_string_catalog_label(settings_catalog, lang, "Expires %@", SETTINGS["billing.expires"])

    current_reset = settings.get("budget.action.resetAgentSession")
    if current_reset and current_reset != SETTINGS["budget.action.resetAgentSession"]:
        return overrides

    if has_string_catalog_translation(settings_catalog, lang, "Reset agent session"):
        reset_label = localized_string_catalog_label(settings_catalog, lang, "Reset agent session", "")
        overrides["budget.action.resetAgentSession"] = reset_label
    else:
        overrides["budget.action.resetAgentSession"] = localized_composite_label(
            settings_catalog,
            lang,
            "Reset",
            "Reset",
            "Agent",
            "Agent session",
        )
    return overrides


def build_agents_base():
    agents = read_json(RESOURCES / "marketplace_agents.json", [])
    old_i18n = read_json(RESOURCES / "marketplace_agents.i18n.json", {})
    result = {}
    localized = {lang: {} for lang in supported_languages()}
    agent_sources = []
    for agent in agents:
        aid = agent.get("id", "")
        if not aid:
            continue
        prefix = f"agents.{slug(aid)}"
        content = agent.get("content") or ""
        fields = {
            f"{prefix}.name": agent.get("name", ""),
            f"{prefix}.division": agent.get("division", ""),
            f"{prefix}.description": agent.get("description", ""),
            f"{prefix}.vibe": agent.get("vibe", ""),
            f"{prefix}.specialty": agent.get("specialty") or "",
            f"{prefix}.whenToUse": agent.get("whenToUse") or "",
            f"{prefix}.content": content,
        }
        agent_sources.append({
            "id": aid,
            "prefix": prefix,
            "name": agent.get("name", ""),
            "division": agent.get("division", ""),
            "description": agent.get("description", ""),
            "vibe": agent.get("vibe", ""),
            "specialty": agent.get("specialty") or "",
            "whenToUse": agent.get("whenToUse") or "",
            "content": content,
        })
        result.update(fields)
        for lang in localized:
            localized[lang].update(fields)
        for lang, entry in old_i18n.get(aid, {}).items():
            if lang not in localized:
                continue
            for field in ["name", "division", "description", "vibe", "specialty", "whenToUse"]:
                original = fields.get(f"{prefix}.{field}", "")
                if usable_localized_overlay(lang, entry.get(field), original):
                    localized[lang][f"{prefix}.{field}"] = entry[field]
    for lang in supported_languages():
        if lang == "en" or not plugin_catalog_profile(lang):
            continue
        for source in agent_sources:
            prefix = source["prefix"]
            display = localized[lang].get(f"{prefix}.name") or source["name"]
            category = division_category(source["division"])
            capabilities = text_capabilities(
                source["name"],
                source["description"],
                " ".join([source["vibe"], source["specialty"], source["whenToUse"], source["content"]]),
            )
            summary = localized_catalog_summary(
                lang,
                display,
                "agent",
                category,
                capabilities,
                source["description"],
                source["content"],
                "description",
            )
            long_summary = localized_catalog_summary(
                lang,
                display,
                "agent",
                category,
                capabilities,
                source["description"],
                source["content"],
                "longDescription",
            )
            localized[lang][f"{prefix}.division"] = localized_plugin_category(category, lang)
            if not usable_localized_overlay(lang, localized[lang].get(f"{prefix}.description"), source["description"]):
                localized[lang][f"{prefix}.description"] = summary
            if not usable_localized_overlay(lang, localized[lang].get(f"{prefix}.vibe"), source["vibe"]):
                localized[lang][f"{prefix}.vibe"] = long_summary
            if source["specialty"] and not usable_localized_overlay(lang, localized[lang].get(f"{prefix}.specialty"), source["specialty"]):
                localized[lang][f"{prefix}.specialty"] = localized_join(localized_plugin_capabilities(capabilities, lang), plugin_catalog_profile(lang))
            if source["whenToUse"] and not usable_localized_overlay(lang, localized[lang].get(f"{prefix}.whenToUse"), source["whenToUse"]):
                localized[lang][f"{prefix}.whenToUse"] = long_summary
            localized[lang][f"{prefix}.content"] = "\n\n".join(
                dict.fromkeys(
                    value for value in [
                        localized[lang].get(f"{prefix}.description", ""),
                        localized[lang].get(f"{prefix}.vibe", ""),
                        localized[lang].get(f"{prefix}.whenToUse", ""),
                        localized[lang].get(f"{prefix}.specialty", ""),
                    ]
                    if value
                )
            )
    localized["en"] = result.copy()
    return localized


def build_skills_base():
    skills_dir = SKILLS_ROOT / "skills"
    entries = {}
    skill_sources = []
    if skills_dir.exists():
        for path in sorted(skills_dir.iterdir(), key=lambda p: p.name.lower()):
            skill_file = path / "SKILL.md"
            if not skill_file.exists():
                continue
            markdown = skill_file.read_text(encoding="utf-8", errors="replace")
            fm, body = frontmatter_and_body(markdown)
            name = fm.get("name") or path.name
            desc = fm.get("description") or first_paragraph(body)
            prefix = f"skills.catalog.{slug(name)}"
            display = display_name(name)
            skill_sources.append({
                "prefix": prefix,
                "name": name,
                "display": display,
                "description": desc,
                "content": body or desc,
                "category": text_category(name, desc, body, default="Productivity"),
                "capabilities": text_capabilities(name, desc, body),
            })
            entries[f"{prefix}.displayName"] = display
            entries[f"{prefix}.description"] = desc
            entries[f"{prefix}.content"] = body or desc
    localized = {lang: entries.copy() for lang in supported_languages()}
    for lang in supported_languages():
        if lang == "en" or not plugin_catalog_profile(lang):
            continue
        for source in skill_sources:
            prefix = source["prefix"]
            display = source["display"]
            if lang in ["zh-Hans", "zh-Hant"]:
                display = zh_skill_name(source["name"])
            localized[lang][f"{prefix}.displayName"] = display
            localized[lang][f"{prefix}.description"] = localized_catalog_summary(
                lang,
                display,
                "skill",
                source["category"],
                source["capabilities"],
                source["description"],
                source["content"],
                "description",
            )
            localized[lang][f"{prefix}.content"] = localized_catalog_markdown(
                lang,
                display,
                "skill",
                source["category"],
                source["capabilities"],
                source["description"],
                source["content"],
            )
    localized["en"] = entries.copy()
    return localized


def installed_skill_roots():
    candidates = [
        OPENCLAW_PACKAGE_ROOT / "skills",
        Path.home() / ".openclaw" / "skills",
        Path.home() / ".agents" / "skills",
        Path.home() / ".codex" / "skills",
        Path.home() / ".codex" / "skills" / ".system",
    ]
    seen = set()
    roots = []
    for candidate in candidates:
        resolved = str(candidate.expanduser())
        if resolved in seen or not candidate.exists():
            continue
        seen.add(resolved)
        roots.append(candidate)
    return roots


def installed_skill_sources():
    by_name = {}
    for root in installed_skill_roots():
        for path in sorted(root.iterdir(), key=lambda p: p.name.lower()):
            skill_file = path / "SKILL.md"
            if not skill_file.exists():
                continue
            markdown = skill_file.read_text(encoding="utf-8", errors="replace")
            fm, body = frontmatter_and_body(markdown)
            name = fm.get("name") or path.name
            if not name or name in by_name:
                continue
            desc = fm.get("description") or first_paragraph(body)
            by_name[name] = {
                "name": name,
                "display": display_name(name),
                "description": desc,
                "content": body or desc,
                "category": text_category(name, desc, body, default="Productivity"),
                "capabilities": text_capabilities(name, desc, body),
            }
    return list(by_name.values())


def build_installed_skills_base():
    entries = {
        "skills.installed.fallback.description": "%@ skill is installed and ready to use.",
        "skills.installed.fallback.content": "%@\n\n%@",
    }
    sources = installed_skill_sources()
    for source in sources:
        prefix = f"skills.installed.{slug(source['name'])}"
        entries[f"{prefix}.displayName"] = source["display"]
        entries[f"{prefix}.description"] = source["description"]
        entries[f"{prefix}.content"] = source["content"]

    localized = {lang: entries.copy() for lang in supported_languages()}
    for lang in supported_languages():
        if lang == "en" or not plugin_catalog_profile(lang):
            continue
        localized[lang]["skills.installed.fallback.description"] = localized_catalog_summary(
            lang,
            "%@",
            "skill",
            "Developer Tools",
            ["task-specific guidance"],
            "",
            "",
            "description",
        )
        localized[lang]["skills.installed.fallback.content"] = "%@\n\n%@"
        for source in sources:
            prefix = f"skills.installed.{slug(source['name'])}"
            display = source["display"]
            if lang in ["zh-Hans", "zh-Hant"]:
                display = zh_skill_name(source["name"])
            localized[lang][f"{prefix}.displayName"] = display
            localized[lang][f"{prefix}.description"] = localized_catalog_summary(
                lang,
                display,
                "skill",
                source["category"],
                source["capabilities"],
                source["description"],
                source["content"],
                "description",
            )
            localized[lang][f"{prefix}.content"] = localized_catalog_markdown(
                lang,
                display,
                "skill",
                source["category"],
                source["capabilities"],
                source["description"],
                source["content"],
            )

    localized["en"] = entries.copy()
    return localized


def plugin_catalog_paths():
    marketplace = PLUGINS_ROOT / ".agents" / "plugins" / "marketplace.json"
    data = read_json(marketplace, {})
    plugins = data.get("plugins", [])
    paths = []
    for item in plugins:
        rel = item.get("path") or (item.get("source") or {}).get("path") or ("plugins/" + (item.get("name") or item.get("id") or ""))
        if rel:
            paths.append(PLUGINS_ROOT / rel)
    if not paths and (PLUGINS_ROOT / "plugins").exists():
        paths = [p for p in (PLUGINS_ROOT / "plugins").iterdir() if p.is_dir()]
    return paths


def build_plugins_base():
    entries = {}
    plugin_sources = []
    for plugin_dir in sorted(plugin_catalog_paths(), key=lambda p: p.name.lower()):
        openclaw = read_json(plugin_dir / "openclaw.plugin.json", {})
        package = read_json(plugin_dir / "package.json", {})
        package_name = package.get("name") or ""
        unscoped = package_name.split("/")[-1] if package_name else ""
        name = openclaw.get("id") or unscoped or plugin_dir.name
        display = openclaw.get("displayName") or openclaw.get("name") or display_name(name)
        desc = openclaw.get("description") or package.get("description") or "OpenClaw plugin"
        readme = ""
        for candidate in ["README.md", "readme.md"]:
            p = plugin_dir / candidate
            if p.exists():
                readme = p.read_text(encoding="utf-8", errors="replace").strip()
                break
        long_desc = openclaw.get("longDescription") or readme or desc
        category = openclaw.get("category") or ("Communication" if openclaw.get("channels") else "Productivity")
        prefix = f"plugins.catalog.{slug(name)}"
        plugin_sources.append({
            "prefix": prefix,
            "name": name,
            "display": display,
            "description": desc,
            "longDescription": long_desc,
            "category": category,
            "capabilities": openclaw.get("capabilities") or [],
        })
        entries[f"{prefix}.displayName"] = display
        entries[f"{prefix}.description"] = desc
        entries[f"{prefix}.longDescription"] = long_desc
        entries[f"{prefix}.category"] = category
        caps = openclaw.get("capabilities") or []
        for idx, cap in enumerate(caps):
            entries[f"{prefix}.capabilities.{idx}"] = cap
    localized = {lang: entries.copy() for lang in supported_languages()}
    for lang in supported_languages():
        if lang == "en" or not plugin_catalog_profile(lang):
            continue
        for source in plugin_sources:
            prefix = source["prefix"]
            display = source["display"]
            if lang in ["zh-Hans", "zh-Hant"]:
                display = zh_plugin_name(source["name"], display)
            localized[lang][f"{prefix}.displayName"] = display
            localized[lang][f"{prefix}.description"] = localized_plugin_catalog_text(
                lang,
                display,
                source["category"],
                source["capabilities"],
                source["description"],
                source["longDescription"],
                "description",
            )
            localized[lang][f"{prefix}.longDescription"] = localized_plugin_catalog_text(
                lang,
                display,
                source["category"],
                source["capabilities"],
                source["description"],
                source["longDescription"],
                "longDescription",
            )
            localized[lang][f"{prefix}.category"] = localized_plugin_category(source["category"], lang)
            for idx, cap in enumerate(source["capabilities"]):
                localized[lang][f"{prefix}.capabilities.{idx}"] = localized_plugin_capability(cap, lang)
    localized["en"] = entries.copy()
    return localized


def build_installed_plugins_base():
    entries = {
        "plugins.installed.family.provider.displayName": "%@ Provider",
        "plugins.installed.family.provider.description": "Model provider for connecting OpenClaw to %@ models.",
        "plugins.installed.family.provider.category": "Provider",
        "plugins.installed.family.browser.displayName": "%@ Browser",
        "plugins.installed.family.browser.description": "Browser automation capability for opening pages, inspecting content, and interacting with websites.",
        "plugins.installed.family.browser.category": "Browser",
        "plugins.installed.family.speech.displayName": "%@ Speech",
        "plugins.installed.family.speech.description": "Speech capability for transcription, voice, or audio-related model workflows.",
        "plugins.installed.family.speech.category": "Speech",
        "plugins.installed.family.memory.displayName": "%@ Memory",
        "plugins.installed.family.memory.description": "Memory storage capability for retaining reusable context across OpenClaw sessions.",
        "plugins.installed.family.memory.category": "Memory",
        "plugins.installed.family.proxy.displayName": "%@ Proxy",
        "plugins.installed.family.proxy.description": "Proxy capability for routing model requests through a compatible provider or local service.",
        "plugins.installed.family.proxy.category": "Proxy",
        "plugins.installed.family.runtime.displayName": "%@",
        "plugins.installed.family.runtime.description": "Core runtime capability used by OpenClaw to provide built-in plugin behavior.",
        "plugins.installed.family.runtime.category": "Runtime",
        "plugins.installed.family.plugin.displayName": "%@",
        "plugins.installed.family.plugin.description": "Installed OpenClaw plugin.",
        "plugins.installed.family.plugin.category": "Plugin",
        "plugins.installed.detail.pluginId": "**Plugin ID:** `%@`",
        "plugins.installed.detail.status": "**Status:** %@",
        "plugins.installed.detail.version": "**Version:** %@",
    }
    localized = {lang: entries.copy() for lang in supported_languages()}
    for lang in supported_languages():
        if lang == "en" or not plugin_catalog_profile(lang):
            continue
        profile = plugin_catalog_profile(lang)
        plugin = catalog_noun(lang, "plugin")
        read_action = localized_plugin_capability("read", lang)
        provider = localized_plugin_category("Developer Tools", lang)
        browser = localized_plugin_capability("interactive", lang)
        speech = localized_plugin_capability("write", lang)
        memory = localized_plugin_category("Memory", lang)
        proxy = localized_plugin_capability("backend", lang)
        runtime = localized_plugin_capability("general", lang)
        localized[lang].update({
            "plugins.installed.family.provider.displayName": f"%@ {provider}",
            "plugins.installed.family.provider.description": localized_catalog_summary(lang, "%@", "plugin", "Developer Tools", ["backend"], "", "", "description"),
            "plugins.installed.family.provider.category": provider,
            "plugins.installed.family.browser.displayName": f"%@ {browser}",
            "plugins.installed.family.browser.description": localized_catalog_summary(lang, "browser automation", "plugin", "Developer Tools", ["interactive"], "", "", "description"),
            "plugins.installed.family.browser.category": browser,
            "plugins.installed.family.speech.displayName": f"%@ {speech}",
            "plugins.installed.family.speech.description": localized_catalog_summary(lang, "speech", "plugin", "Communication", ["write"], "", "", "description"),
            "plugins.installed.family.speech.category": speech,
            "plugins.installed.family.memory.displayName": f"%@ {memory}",
            "plugins.installed.family.memory.description": localized_catalog_summary(lang, "memory", "plugin", "Memory", ["storage"], "", "", "description"),
            "plugins.installed.family.memory.category": memory,
            "plugins.installed.family.proxy.displayName": f"%@ {proxy}",
            "plugins.installed.family.proxy.description": localized_catalog_summary(lang, "proxy", "plugin", "Developer Tools", ["backend"], "", "", "description"),
            "plugins.installed.family.proxy.category": proxy,
            "plugins.installed.family.runtime.displayName": "%@",
            "plugins.installed.family.runtime.description": localized_catalog_summary(lang, "runtime", "plugin", "Developer Tools", ["general"], "", "", "description"),
            "plugins.installed.family.runtime.category": runtime,
            "plugins.installed.family.plugin.displayName": "%@",
            "plugins.installed.family.plugin.description": localized_catalog_summary(lang, plugin, "plugin", "Productivity", ["general"], "", "", "description"),
            "plugins.installed.family.plugin.category": plugin,
            "plugins.installed.detail.pluginId": f"**{plugin} ID:** `%@`",
            "plugins.installed.detail.status": f"**{read_action}:** %@",
            "plugins.installed.detail.version": f"**{localized_plugin_capability('monitoring', lang)}:** %@",
        })
    localized["en"] = entries.copy()
    return localized


def build_settings_base():
    catalog = read_json(LOCALIZABLE, {})
    strings = catalog.get("strings", {})
    localized = {lang: {} for lang in supported_languages()}
    for key, entry in strings.items():
        if not isinstance(key, str):
            continue
        localized["en"][key] = key
        localizations = entry.get("localizations", {}) if isinstance(entry, dict) else {}
        for lang in localized:
            if lang == "en":
                continue
            value = (
                localizations.get(lang, {})
                .get("stringUnit", {})
                .get("value")
            )
            if not isinstance(value, str) or not value.strip():
                localized[lang][key] = key
            elif placeholder_signature(value) != placeholder_signature(key):
                localized[lang][key] = key
            else:
                localized[lang][key] = value
    return localized


def write_namespace(language, namespace, values):
    directory = I18N_ROOT / language
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{namespace}.json"
    path.write_text(json.dumps(dict(sorted(values.items())), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    langs = supported_languages()
    validate_plugin_catalog_profiles(langs)
    agents = build_agents_base()
    skills_catalog = build_skills_base()
    installed_skills_catalog = build_installed_skills_base()
    plugins_catalog = build_plugins_base()
    installed_plugins_catalog = build_installed_plugins_base()
    settings_catalog = build_settings_base()
    for lang in langs:
        common = COMMON.copy()
        skills = SKILLS_UI.copy()
        plugins = PLUGINS_UI.copy()
        settings = SETTINGS.copy()
        agent_ui = AGENTS_UI.copy()
        if lang != "en":
            common.update(generic_common_localizations(lang))
        if lang == "zh-Hans":
            common.update(COMMON_ZH_HANS); skills.update(SKILLS_UI_ZH_HANS); plugins.update(PLUGINS_UI_ZH_HANS); settings.update(SETTINGS_ZH_HANS); agent_ui.update(AGENTS_UI_ZH_HANS)
        elif lang == "zh-Hant":
            common.update(COMMON_ZH_HANT); skills.update(SKILLS_UI_ZH_HANT); plugins.update(PLUGINS_UI_ZH_HANT); settings.update(SETTINGS_ZH_HANT); agent_ui.update(AGENTS_UI_ZH_HANT)
        settings.update(settings_catalog.get(lang, settings_catalog.get("en", {})))
        common.update(common_short_label_overrides(lang, settings_catalog, common))
        settings.update(settings_short_label_overrides(lang, settings_catalog, settings))
        skills.update(skills_catalog.get(lang, {}))
        skills.update(installed_skills_catalog.get(lang, {}))
        plugins.update(plugins_catalog.get(lang, {}))
        plugins.update(installed_plugins_catalog.get(lang, {}))
        write_namespace(lang, "common", common)
        write_namespace(lang, "settings", settings)
        agent_ui.update(agents.get(lang, agents.get("en", {})))
        write_namespace(lang, "agents", agent_ui)
        write_namespace(lang, "skills", skills)
        write_namespace(lang, "plugins", plugins)
    print(f"Generated unified i18n resources for {len(langs)} languages")

if __name__ == "__main__":
    main()
