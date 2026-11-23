import AppKit
import SwiftUI

/// A terminal that shows how a command line is used, as Typecase's scripted terminal does: commands typed a key at a
/// time after a green prompt, each followed by what it printed. Over its corner, while the pointer's on it, are Skip
/// to the end, Replay, and Copy, which copies the commands. With reduced motion on, it shows the end at once.
struct TerminalScript {
    enum Line: Hashable {
        /// A dimmed `# …` line.
        case comment(String)
        /// Typed after the prompt, then Return.
        case run(String)
        /// What a command printed.
        case output(String)
        /// What a command printed as a mistake, in red.
        case error(String)
    }

    var lines: [Line]

    /// The commands alone, for Copy.
    var commands: String {
        lines.compactMap { if case .run(let command) = $0 { command } else { nil } }.joined(separator: "\n")
    }

    /// `slaps` itself prints nothing when it works, as a Unix tool doesn't; a mistake is said where it was made.
    static let slaps = TerminalScript(lines: [
        .comment("An alert in 5 minutes, with a Join button"),
        .run("slaps alert \"Standup\" --in 5 --link https://zoom.us/j/123 --from CI"),
        .comment("A tab on the edge of the screen; full screen in 30 minutes"),
        .run("slaps tab \"Reply to Bob\" --deadline 30 --color teal --from Mail --id bob"),
        .run("slaps dismiss --id bob"),
        .comment("A mistake is said here, not only in the log"),
        .run("slaps pause --minute 30"),
        .error("slaps: pause doesn't take --minute"),
        .run("slaps pause --minutes 30"),
    ])
}

struct ScriptedTerminal: View {
    let script: TerminalScript
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far it's got: whole lines shown, and the keys typed of the next if it's a command.
    @State private var shownLines = 0
    @State private var typed = 0
    @State private var hovering = false
    @State private var run = 0

    private static let typing: Duration = .milliseconds(28)
    private static let between: Duration = .milliseconds(450)

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(script.lines.prefix(shownLines).enumerated()), id: \.offset) { _, line in
                        text(line, typed: nil)
                    }
                    if shownLines < script.lines.count, case .run = script.lines[shownLines] {
                        text(script.lines[shownLines], typed: typed)
                    } else if shownLines == script.lines.count {
                        prompt + Text("▌").foregroundColor(.gray)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .onChange(of: shownLines) { scroller.scrollTo("end", anchor: .bottom) }
        }
        .background(Color(nsColor: NSColor(calibratedWhite: 0.1, alpha: 1)), in: .rect(cornerRadius: 8))
        .foregroundStyle(Color(nsColor: NSColor(calibratedWhite: 0.9, alpha: 1)))
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 2) {
                    control("forward.end", "Skip to the End", skip).disabled(shownLines == script.lines.count)
                    control("arrow.counterclockwise", "Replay") { run += 1 }
                    control("doc.on.doc", "Copy the Commands") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(script.commands, forType: .string)
                    }
                }
                .padding(4)
                .background(.thinMaterial, in: .rect(cornerRadius: 6))
                .padding(6)
            }
        }
        .onHover { hovering = $0 }
        .task(id: run) { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example commands")
        .accessibilityValue(script.commands)
    }

    private var prompt: Text { Text("$ ").foregroundColor(.green) }

    private func text(_ line: TerminalScript.Line, typed: Int?) -> Text {
        switch line {
        case .comment(let words): Text("# \(words)").foregroundColor(.gray)
        case .run(let command): prompt + Text(typed.map { String(command.prefix($0)) + "▌" } ?? command)
        case .output(let words): Text(words)
        case .error(let words): Text(words).foregroundColor(Color(nsColor: .systemRed))
        }
    }

    private func control(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 20, height: 18) }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
    }

    private func skip() {
        shownLines = script.lines.count
        typed = 0
    }

    private func play() async {
        shownLines = 0
        typed = 0
        guard !reduceMotion else { return skip() }
        do {
            // Skip shows the end without stopping this, so each wait checks it's still playing the same line.
            while shownLines < script.lines.count {
                let at = shownLines
                if case .run(let command) = script.lines[at] {
                    try await Task.sleep(for: Self.between)
                    for count in 1...max(command.count, 1) {
                        guard shownLines == at else { return }
                        typed = count
                        try await Task.sleep(for: Self.typing)
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
                guard shownLines == at else { return }
                typed = 0
                shownLines += 1
            }
        } catch {
            // Cancelled: Replay, or the page went away.
        }
    }
}
