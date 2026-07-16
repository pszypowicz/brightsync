import ArgumentParser
import Foundation
import ServiceManagement

enum AutostartAction: String, CaseIterable, ExpressibleByArgument {
    case enable, disable, status
}

/// Launch-at-login management. The launchd agent plist ships inside the app
/// bundle (Contents/Library/LaunchAgents), so registration only works when
/// the binary runs from the installed brightsync.app; SMAppService then
/// surfaces the entry under System Settings > General > Login Items.
enum Autostart {
    /// Bundle identifier, launchd label, and unified-log subsystem.
    static let label = "cz.szypowi.brightsync"

    private static var service: SMAppService {
        SMAppService.agent(plistName: "\(label).plist")
    }

    static func run(_ action: AutostartAction) throws {
        guard Bundle.main.bundleIdentifier == label else {
            throw ValidationError(
                "autostart is managed through the app bundle; run Brightsync.app/Contents/MacOS/brightsync")
        }
        switch action {
        case .status:
            print(describe(service.status))
        case .enable:
            // Always re-register from scratch: Background Task Management
            // pins a bookmark and launch constraint to the binary that
            // registered, so enabling on top of an existing registration
            // after the bundle changed leaves launchd unable to spawn the
            // agent (SIGKILL: launch constraint violation, then EX_CONFIG).
            // The completion handler signals when the unregistration has
            // been processed; the timeout keeps a hung callback from
            // wedging the CLI.
            if service.status != .notRegistered {
                let done = DispatchSemaphore(value: 0)
                service.unregister { _ in done.signal() }
                _ = done.wait(timeout: .now() + 10)
            }
            try service.register()
            print(
                service.status == .requiresApproval
                    ? "autostart registered; approve brightsync in System Settings > General > Login Items"
                    : "autostart enabled")
        case .disable:
            guard service.status != .notRegistered else {
                print("autostart not registered")
                return
            }
            try service.unregister()
            print("autostart disabled")
        }
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .requiresApproval: return "requires approval in System Settings > General > Login Items"
        case .notFound: return "not found (is the app installed?)"
        @unknown default: return "unknown (\(status.rawValue))"
        }
    }
}
