import Foundation

/// `slaps` on the PATH: a link in ~/.local/bin to the app's own binary, which answers a command line before the app
/// starts (`Main` in SlapsApp.swift). A link rather than a copy, so it's always this Slaps, updated with it.
enum CommandLineLink {
    static var link: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/slaps")
    }

    /// Whether the link is there and leads to this app.
    static var isInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path),
              let binary = Bundle.main.executablePath else { return false }
        return target == binary
    }

    /// Makes the link, taking the place of an old one; why not, if it can't.
    static func install() -> String? {
        guard let binary = Bundle.main.executablePath else { return "Slaps can't find its own binary." }
        let files = FileManager.default
        do {
            try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? files.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try files.removeItem(at: link)
            } else if files.fileExists(atPath: link.path) {
                return "There's already a file at \(link.path) that isn't Slaps's; move it and try again."
            }
            try files.createSymbolicLink(atPath: link.path, withDestinationPath: binary)
            return nil
        } catch {
            return "Couldn't make \(link.path): \(error.localizedDescription)"
        }
    }
}
