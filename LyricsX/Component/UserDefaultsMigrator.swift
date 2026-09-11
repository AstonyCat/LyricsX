import Foundation
import os
import LyricsXFoundation

/// One-shot migration of UserDefaults from the sandbox container into the
/// non-sandbox preferences domain after the app drops `com.apple.security.app-sandbox`.
///
/// Sandbox stores prefs at:
///   ~/Library/Containers/<bundleID>/Data/Library/Preferences/<bundleID>.plist
/// Non-sandbox stores prefs at:
///   ~/Library/Preferences/<bundleID>.plist
///
/// `cfprefsd` resolves which file `UserDefaults.standard` reads from based on
/// the running process's sandbox state, so flipping the entitlement makes the
/// container plist invisible. This class copies the values across and records
/// completion in the destination domain so it never runs twice.
@Loggable(subsystem: "com.JH.LyricsX.diagnostics")
final class UserDefaultsMigrator {
    static let shared = UserDefaultsMigrator()

    private static let migrationCompletionKey = "Migration.SandboxToNonSandbox.v1"
    private static let layerSettingsCompletionKey = "Migration.LyricsLayerSettings.v1"

    private let bundleIdentifier: String
    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.JH.LyricsX",
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    /// Idempotent. Must be called before any other UserDefaults read or
    /// `register(defaults:)` happens — i.e. at the very top of
    /// `applicationDidFinishLaunching(_:)`.
    func migrateFromSandboxIfNeeded() {
        guard !userDefaults.bool(forKey: Self.migrationCompletionKey) else { return }

        let sourceURL = sandboxContainerPlistURL
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            markCompleted()
            #log(.info, "No sandbox container plist found at \(sourceURL.path, privacy: .public); nothing to migrate")
            return
        }

        do {
            let data = try Data(contentsOf: sourceURL)
            guard let dictionary = try PropertyListSerialization
                .propertyList(from: data, options: [], format: nil) as? [String: Any]
            else {
                #log(.error, "Sandbox plist is not a top-level dictionary at \(sourceURL.path, privacy: .public)")
                return
            }

            var migratedKeyCount = 0
            for (key, value) in dictionary where !isSystemKey(key) {
                userDefaults.set(value, forKey: key)
                migratedKeyCount += 1
            }

            markCompleted()
            #log(.info, "Migrated \(migratedKeyCount, privacy: .public) keys from sandbox container at \(sourceURL.path, privacy: .public)")
        } catch {
            #log(.error, "Migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 把旧的单开关设置迁到分层设置。只有用户显式设置过的旧值才迁移，
    /// 没设过就让新键保持注册的默认值——翻译开关的默认值由
    /// `AppDelegate.registerUserDefaults()` 按系统语言推导，与旧版行为一致。
    func migrateLyricsLayerSettingsIfNeeded() {
        guard !userDefaults.bool(forKey: Self.layerSettingsCompletionKey) else { return }

        let moves: [(old: String, new: [String])] = [
            ("DesktopLyricsEnableFurigana", ["DesktopLyricsShowFurigana"]),
            ("DesktopLyricsEnableRomajin", ["DesktopLyricsShowRomaji"]),
        ]

        var migratedCount = 0
        for (old, newKeys) in moves {
            guard let value = userDefaults.object(forKey: old) as? Bool else { continue }
            for newKey in newKeys {
                userDefaults.set(value, forKey: newKey)
                migratedCount += 1
            }
        }

        // `PreferBilingualLyrics` 曾经注册过按系统语言推导的默认值，`object(forKey:)`
        // 会把注册值当成用户选择读出来，所以这里只认持久域里的值；
        // `register(defaults:)` 从不写入持久域，读到了就一定是用户显式设置。
        let persistent = userDefaults.persistentDomain(forName: bundleIdentifier) ?? [:]
        if let preferBilingual = persistent["PreferBilingualLyrics"] as? Bool {
            userDefaults.set(preferBilingual, forKey: "DesktopLyricsShowTranslation")
            userDefaults.set(preferBilingual, forKey: "LyricsWindowShowTranslation")
            migratedCount += 2
        }
        userDefaults.set(true, forKey: Self.layerSettingsCompletionKey)
        #log(.info, "Migrated \(migratedCount, privacy: .public) lyrics layer settings from legacy keys")
    }

    private var sandboxContainerPlistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Preferences/\(bundleIdentifier).plist")
    }

    /// Skip framework-internal namespaces. `AppleLanguages` is intentionally
    /// allowed through — it's the user's locale choice and we want to keep it.
    private func isSystemKey(_ key: String) -> Bool {
        key.hasPrefix("NS") || key.hasPrefix("com.apple.")
    }

    private func markCompleted() {
        userDefaults.set(true, forKey: Self.migrationCompletionKey)
    }
}
