import SwiftUI

/// What the share sheet shows: the title, editable, and what will go in the
/// note under it.
///
/// **The title is editable and that is the whole point of having a sheet.** A
/// no-UI extension is one tap faster and gets the title wrong constantly —
/// shared pages are called "Home | Acme Corp — Official Site" and shared
/// selections start mid-sentence. Fixing that here costs a moment; fixing it
/// later means finding the card again in an app you were not going to open.
///
/// It wears the user's theme by reading the widgets' digest, which is already in
/// the App Group and already carries `themes` and `appearance`. No board is
/// opened to do it — see ``CaptureInbox`` for why the extension must not — and
/// with no digest yet written it falls back to the shipping preset, which is
/// what a widget does in the same position.
struct CaptureSheet: View {
    @Environment(\.palette) private var palette

    let note: String
    /// Returns the sentence to show when the capture could not be written, or
    /// `nil` when it worked. A closure rather than a thrown error because the
    /// host is what owns the extension context and decides what "it worked"
    /// means — see ``ShareViewController``.
    var add: (String) -> String?
    var cancel: () -> Void

    @State private var title: String
    @State private var failure: String?
    @FocusState private var isEditingTitle: Bool

    init(draft: PendingCapture, add: @escaping (String) -> String?, cancel: @escaping () -> Void) {
        _title = State(initialValue: draft.title)
        note = draft.note
        self.add = add
        self.cancel = cancel
    }

    /// A share carrying nothing usable cannot become a card, and the button says
    /// so by being unavailable rather than by making an untitled one: an
    /// untitled card is quick capture's, and it comes with a field waiting to be
    /// typed in, which this is not.
    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to Inbox", comment: "Title of the share sheet that captures into Cardstock")
                .font(palette.ui(17, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)

            VStack(alignment: .leading, spacing: 6) {
                Text("Title", comment: "Field label on the share sheet")
                    .sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                TextField("Title", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .font(palette.ui(15, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.ink)
                    .focused($isEditingTitle)
                    .padding(10)
                    .background(palette.ink(0.06), in: .rect(cornerRadius: 9))
            }

            if !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Note", comment: "Field label on the share sheet, above the read-only note")
                        .sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                    // Read-only: the note is the URL and whatever else was
                    // shared, and this sheet is open for as long as it takes to
                    // fix a title. Editing a note belongs in the app, where
                    // there is room for it.
                    Text(note)
                        .font(palette.ui(12.5, .regular, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.55))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(palette.wash, in: .rect(cornerRadius: 9))
                }
            }

            if let failure {
                Text(failure)
                    .font(palette.ui(12.5, .semibold, relativeTo: .footnote))
                    .foregroundStyle(palette.dueTone(urgency: .overdue, isDone: false).foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(role: .cancel) { cancel() } label: {
                    Text("Cancel", comment: "Dismisses the share sheet without capturing")
                }
                Button {
                    failure = add(title.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Text("Add", comment: "Captures the shared item into the Inbox")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(18)
        .frame(minWidth: 320, idealWidth: 380)
        .background(palette.card)
        .onAppear { isEditingTitle = true }
    }
}
