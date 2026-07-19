import Foundation

/// Installs and removes a `brightsync` symlink on the user's PATH so the app's
/// argv mode (--list, --set-external, ...) is reachable from a terminal. The
/// link points at this bundle's own executable, so it follows wherever the app
/// lives. Everything happens in a user-writable directory: no administrator
/// password, no privileged helper. The Homebrew cask ships the same link and
/// self-cleans on uninstall; this is the equivalent for a drag-installed app.
enum CommandLineTool {
    static let linkName = "brightsync"

    struct CLIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// This bundle's executable, canonicalised so it compares exactly against
    /// an existing link's resolved target.
    private static var binaryURL: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath()
    }

    /// `/opt/homebrew/bin` is on the default PATH on Apple Silicon and is where
    /// a Homebrew cask places the link; `~/.local/bin` is the user-writable
    /// fallback we create. `/usr/local/bin` is deliberately absent: it needs
    /// root and is off PATH by default here.
    private static var homebrewBin: URL { URL(fileURLWithPath: "/opt/homebrew/bin") }
    private static var localBin: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
    }
    private static var searchDirs: [URL] { [homebrewBin, localBin] }

    /// The `brightsync` link that resolves to this executable, or nil if the
    /// CLI is not installed. A same-named link pointing elsewhere is not ours
    /// and is ignored.
    static func installedLink() -> URL? {
        for dir in searchDirs {
            let link = dir.appendingPathComponent(linkName)
            if resolvedTarget(of: link) == binaryURL.path { return link }
        }
        return nil
    }

    /// Creates the link and returns its path; a no-op if it already points at
    /// this executable. Refuses to clobber an unrelated file of the same name.
    @discardableResult
    static func install() throws -> URL {
        if let existing = installedLink() { return existing }
        let fm = FileManager.default
        let dir = try installDirectory()
        let link = dir.appendingPathComponent(linkName)
        if fm.fileExists(atPath: link.path) || resolvedTarget(of: link) != nil {
            throw CLIError(message:
                "A different '\(linkName)' already exists at \(link.path). Remove it and try again.")
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: binaryURL)
        return link
    }

    /// Removes every `brightsync` link pointing at this executable from the
    /// search directories, leaving unrelated same-named links untouched.
    static func uninstall() throws {
        let fm = FileManager.default
        for dir in searchDirs {
            let link = dir.appendingPathComponent(linkName)
            if resolvedTarget(of: link) == binaryURL.path {
                try fm.removeItem(at: link)
            }
        }
    }

    /// Prefers an existing, writable `/opt/homebrew/bin`; otherwise creates and
    /// uses `~/.local/bin`.
    private static func installDirectory() throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: homebrewBin.path), fm.isWritableFile(atPath: homebrewBin.path) {
            return homebrewBin
        }
        try fm.createDirectory(at: localBin, withIntermediateDirectories: true)
        return localBin
    }

    /// The canonical path a symlink resolves to, or nil if `link` is not a
    /// symlink. A relative target is resolved against the link's directory.
    private static func resolvedTarget(of link: URL) -> String? {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        else { return nil }
        return URL(fileURLWithPath: dest, relativeTo: link.deletingLastPathComponent())
            .resolvingSymlinksInPath().path
    }
}
