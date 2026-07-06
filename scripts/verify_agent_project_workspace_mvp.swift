#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("Missing file: \(path)\n", stderr)
        exit(1)
    }
    return content
}

func require(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let sessionModel = read("OpenClawInstaller/Features/Sessions/Models/ChatSession.swift")
let projectModels = read("OpenClawInstaller/Features/Workspace/Models/ProjectWorkspace.swift")
let projectContextModel = read("OpenClawInstaller/Features/Workspace/Models/ProjectWorkspaceContext.swift")
let repoMapService = read("OpenClawInstaller/Features/Workspace/SemanticRepoMapService.swift")
let registryStore = read("OpenClawInstaller/Features/Workspace/ProjectRegistryStore.swift")
let workspaceService = read("OpenClawInstaller/Features/Workspace/ProjectWorkspaceService.swift")
let sessionContextBuilder = read("OpenClawInstaller/Features/Workspace/ProjectSessionContextBuilder.swift")
let gatewayWorkspaceContext = read("OpenClawInstaller/Features/Workspace/GatewayWorkspaceContext.swift")
let workspacePicker = read("OpenClawInstaller/Features/Workspace/Views/ProjectWorkspace/ProjectWorkspacePicker.swift")
let projectFolderRow = read("OpenClawInstaller/Features/Workspace/Views/ProjectWorkspace/AgentProjectFolderRow.swift")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let projectFile = read("OpenClawInstaller.xcodeproj/project.pbxproj")

require(sessionModel.contains("var projectId: String?"), "ChatSession should persist optional projectId")
require(sessionModel.contains("var projectRoot: String?"), "ChatSession should persist optional projectRoot")
require(sessionModel.contains("var projectDisplayName: String?"), "ChatSession should persist optional projectDisplayName")
require(sessionModel.contains("self.projectId = session.projectId"), "ChatSessionMetadata should mirror projectId")

require(projectModels.contains("struct ProjectRecord"), "ProjectRecord model should exist")
require(projectModels.contains("struct AgentProjectBinding"), "AgentProjectBinding model should exist")
require(projectModels.contains("var sortKey: String"), "ProjectRecord should expose a stable sort key")
require(projectContextModel.contains("struct ProjectWorkspaceContext"), "project workspace context model should exist")

require(repoMapService.contains("final class SemanticRepoMapService"), "SemanticRepoMapService should exist")
require(repoMapService.contains("Application Support"), "repo map manifest should be app-owned, not stored inside projects")
require(repoMapService.contains("bootstrapProject"), "repo map service should expose a non-blocking bootstrapProject entry")
require(!repoMapService.contains("FSEventStreamCreate"), "MVP must not create FSEvents watchers")
require(!repoMapService.localizedCaseInsensitiveContains("tree-sitter"), "MVP must not launch tree-sitter indexing")
require(!repoMapService.localizedCaseInsensitiveContains("sourcekit"), "MVP must not launch SourceKit indexing")
require(!repoMapService.contains("enumerator(at:"), "MVP must not recursively enumerate project files")
require(registryStore.contains("final class ProjectRegistryStore"), "project registry persistence should live outside DashboardViewModel")
require(workspaceService.contains("final class ProjectWorkspaceService"), "project attach/remove logic should live in ProjectWorkspaceService")
require(sessionContextBuilder.contains("struct ProjectSessionContextBuilder"), "project prompt context should live in ProjectSessionContextBuilder")
require(gatewayWorkspaceContext.contains("struct GatewayWorkspaceContext"), "gateway workspace context type should exist for structured cwd handoff")
require(workspacePicker.contains("struct ProjectWorkspacePicker"), "folder picker helper should live outside DashboardViewModel")
require(!workspacePicker.contains("panel.title"), "folder picker should use the system default title")
require(!workspacePicker.contains("panel.message"), "folder picker should not add custom explanatory copy")
require(!workspacePicker.contains("panel.prompt"), "folder picker should use the system default confirmation button")
require(!workspacePicker.contains("panel.nameFieldLabel"), "folder picker should use the system default field label")
require(!workspacePicker.contains("Work Folder"), "folder picker should not expose work-folder wording")
require(projectFolderRow.contains("struct AgentProjectFolderRow"), "project folder sidebar row should live outside DashboardView")
require(projectFolderRow.contains("workspace.project.newChat"), "project folder row should own localized project new-chat menu copy")

require(viewModel.contains("@Published var projectBindingsByAgent"), "view model should publish project bindings grouped by agent")
require(viewModel.contains("@Published var projectSessionsByAgent"), "view model should publish project sessions grouped under projects")
require(viewModel.contains("@Published var generalSessionsByAgent"), "view model should publish project-less sessions separately")
require(viewModel.contains("func openProject(forAgent agentId: String)"), "view model should expose an Open Project action")
require(viewModel.contains("func createNewSession(forAgent agentId: String, projectId: String?)"), "view model should create sessions scoped to projects")
require(viewModel.contains("ProjectSessionContextBuilder.message"), "sendChatMessage should use the extracted project context builder")
require(!viewModel.contains("private var projectRegistryURL"), "DashboardViewModel should not own project registry file paths")
require(!viewModel.contains("private struct ProjectRegistrySnapshot"), "DashboardViewModel should not own project registry persistence models")
require(!viewModel.contains("private func projectContextMessage"), "DashboardViewModel should not own project prompt context generation")
require(!viewModel.contains("contentsOfDirectory(atPath: projectRoot"), "view model should not scan project roots")

require(dashboard.contains("projectFoldersSectionContent(for: agent)"), "sidebar should render project folders before general sessions")
require(dashboard.contains("generalSessionsSectionContent(for: agent)"), "sidebar should render project-less sessions separately")
require(dashboard.range(of: "projectFoldersSectionContent(for: agent)")!.lowerBound < dashboard.range(of: "generalSessionsSectionContent(for: agent)")!.lowerBound, "project folders should render before general sessions")
require(dashboard.contains("dashboard.agent.addWorkFolder"), "sidebar should keep the existing add-folder action key")
require(dashboard.contains("folder.badge.plus"), "Agent rows should expose a direct work-folder action")
require(projectFolderRow.contains(#"Image(systemName: isExpanded ? "book" : "book.closed")"#), "project folders should use book/book.closed system icons")
require(dashboard.contains("struct SidebarCollapsibleRow"), "sidebar collapse behavior should live in a whole-row collapsible container")
require(dashboard.contains("private static var expansionAnimation"), "collapsible row should own the shared expand/collapse animation")
require(dashboard.contains(".transition(Self.childTransition)"), "collapsible row should own the child transition")
require(dashboard.contains(".clipped()"), "collapsible row should clip collapsing children to avoid visual overlap")
require(dashboard.contains("SidebarCollapsibleRow("), "agent/project rows should use the whole-row collapsible container")
require(dashboard.components(separatedBy: "SidebarCollapsibleRow(").count >= 3, "agent and project rows should both use SidebarCollapsibleRow")
require(!dashboard.contains("struct SidebarDisclosureChevron"), "standalone chevron component should be folded into the collapsible row")
require(!dashboard.contains("if expandedAgentIds.contains(agent.id) {\n                                VStack"), "agent session children should be rendered by SidebarCollapsibleRow")
require(!dashboard.contains("sessionRows(group.sessions, for: agent)\n                    .padding(.leading, 14)"), "project child sessions should align with other agent-level session rows")

require(projectFile.contains("ProjectWorkspace.swift in Sources"), "ProjectWorkspace.swift should be in the app target")
require(projectFile.contains("ProjectWorkspaceContext.swift in Sources"), "ProjectWorkspaceContext.swift should be in the app target")
require(projectFile.contains("SemanticRepoMapService.swift in Sources"), "SemanticRepoMapService.swift should be in the app target")
require(projectFile.contains("ProjectRegistryStore.swift in Sources"), "ProjectRegistryStore.swift should be in the app target")
require(projectFile.contains("ProjectWorkspaceService.swift in Sources"), "ProjectWorkspaceService.swift should be in the app target")
require(projectFile.contains("ProjectSessionContextBuilder.swift in Sources"), "ProjectSessionContextBuilder.swift should be in the app target")
require(projectFile.contains("GatewayWorkspaceContext.swift in Sources"), "GatewayWorkspaceContext.swift should be in the app target")
require(projectFile.contains("ProjectWorkspacePicker.swift in Sources"), "ProjectWorkspacePicker.swift should be in the app target")
require(projectFile.contains("AgentProjectFolderRow.swift in Sources"), "AgentProjectFolderRow.swift should be in the app target")

print("Agent project workspace MVP verification passed")
