// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The facts this build states about itself, read back out of the bundle
/// rather than baked in — so the About surface cannot say one thing while the
/// build settings say another.
enum AppInfo {
    /// The version this build calls itself, from `MARKETING_VERSION` by way of
    /// the plist.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }
}
