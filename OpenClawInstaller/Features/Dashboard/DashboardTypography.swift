import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import AppKit
import WebKit
import os.log

// Split from DashboardView.swift — file move only, no behavior change.

enum DashboardTypography {
    static let sidebarRow = Font.system(size: 14, weight: .regular)
    static let sidebarSectionTitle = Font.system(size: 14, weight: .regular)
    static let sidebarAgentName = Font.system(size: 14, weight: .regular)
    static let sidebarAgentNameActive = Font.system(size: 14, weight: .regular)
    static let sidebarSessionTitle = Font.system(size: 13.5, weight: .regular)
    static let sidebarSessionMeta = Font.system(size: 11, weight: .regular)
    static let composer = Font.system(size: 14, weight: .regular)
    static let composerPlaceholder = Font.system(size: 14, weight: .regular)
    static let message = Font.system(size: 14, weight: .regular)
    static let userMessage = Font.system(size: 14, weight: .regular)
    static let messageMeta = Font.system(size: 11, weight: .regular)

    static func sidebarAgent(active: Bool) -> Font {
        active ? sidebarAgentNameActive : sidebarAgentName
    }
}

enum DashboardSidebarMetrics {
    static let sidebarIconSlotWidth: CGFloat = 18
    static let agentAvatarSize: CGFloat = 22
    static let agentTitleSpacing: CGFloat = 10
    static let disclosureChevronWidth: CGFloat = 12
    static let disclosureChevronHeight: CGFloat = 20
    /// Session-title leading inset: matches the bullet block on session rows
    /// (4pt inset + 6pt dot + 8pt gap) so "show more" text aligns with titles.
    static let sessionTitleLeadingSpacer: CGFloat = 18
    static let sessionRowContentHeight: CGFloat = 36
    static let sessionRowActionSize: CGFloat = 20
    static let sessionRowActionAreaWidth: CGFloat = sessionRowActionSize * 2 + 2
    static let sessionRowVerticalPadding: CGFloat = 4
}
