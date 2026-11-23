import SwiftUI

/// What just happened, with a button to take it back: `Dismissed 3 tabs · Undo`. A few words, past tense, no full
/// stop, as Typecase's toasts say it; not called a toast here, which would muddle it with a Tab, which stays.
struct UndoNotice: Identifiable {
    let id = UUID()
    let text: String
    let undo: () -> Void

    init(_ text: String, undo: @escaping () -> Void) {
        self.text = text
        self.undo = undo
    }
}

/// Shows a notice at the bottom of the view it's laid over, for five seconds, but not while the pointer's on it.
/// Undo runs its undo and takes it away; a newer notice takes its place.
struct UndoBar: View {
    @Binding var notice: UndoNotice?
    @State private var hovering = false

    static let shownFor: Duration = .seconds(5)

    var body: some View {
        ZStack {
            if let notice {
                HStack(spacing: 10) {
                    Text(notice.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Undo") {
                        notice.undo()
                        withAnimation { self.notice = nil }
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Undo: \(notice.text)")
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(.horizontal, 12)
                .onHover { hovering = $0 }
                .id(notice.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: "\(notice.id)\(hovering)") {
                    guard !hovering else { return }
                    try? await Task.sleep(for: Self.shownFor)
                    guard !Task.isCancelled, self.notice?.id == notice.id else { return }
                    withAnimation { self.notice = nil }
                }
                .onAppear {
                    AccessibilityNotification.Announcement(notice.text).post()
                }
            }
        }
        .animation(.spring(duration: 0.3), value: notice?.id)
    }
}
