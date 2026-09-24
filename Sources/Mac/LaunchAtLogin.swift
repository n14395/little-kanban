// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)

import Foundation
import ServiceManagement
import os

/// The "start Little Kanban when I log in" switch.
///
/// `SMAppService.mainApp` rather than a login-item helper or a
/// `LaunchAgents` plist: it is the only route a sandboxed, notarized app has,
/// it needs no helper bundle, and macOS shows the registration in **Login
/// Items** where a person can turn it off without finding this setting again.
///
/// **The system is the truth, not the preference.** A registration can be
/// revoked from System Settings, and a stored `true` would then be a switch
/// that reads on while nothing happens at login. So `isOn` asks the service for
/// its status and the stored key is only what the last *attempt* was — which is
/// what a failed registration needs, so the row can go back to off instead of
/// lying.
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.n14395.LittleKanban", category: "login")

    /// What the system says, which is what the switch shows.
    static var isOn: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters, and reports whether it took. A refusal is
    /// worth showing rather than swallowing: `.requiresApproval` means the
    /// switch is on in this app and off in System Settings, which is exactly
    /// the state a silent failure would leave unexplained.
    @discardableResult
    static func set(_ wanted: Bool) -> Bool {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Preferences.defaults.set(wanted, forKey: Preferences.launchAtLoginKey)
            return true
        } catch {
            logger.error("Could not \(wanted ? "register" : "unregister") for login: \(error.localizedDescription)")
            Preferences.defaults.set(isOn, forKey: Preferences.launchAtLoginKey)
            return false
        }
    }

    /// Whether the registration exists but is switched off in System Settings —
    /// the one state the switch alone cannot explain.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}

#endif
