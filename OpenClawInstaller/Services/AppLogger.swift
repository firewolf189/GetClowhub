import Foundation
import os

enum AppLogger {
    private static let subsystem = "com.cc.OpenClawInstaller"

    static let installer = Logger(subsystem: subsystem, category: "installer")
    static let service   = Logger(subsystem: subsystem, category: "service")
    static let ui        = Logger(subsystem: subsystem, category: "ui")
    static let auth      = Logger(subsystem: subsystem, category: "auth")
}
