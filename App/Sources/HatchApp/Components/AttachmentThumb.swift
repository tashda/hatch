import SwiftUI
import AppKit
import HatchCore

/// A screenshot attached to a ticket. The path is relative to the Hatch folder unless it starts with "/".
struct AttachmentThumb: View {
    @EnvironmentObject var state: AppState
    let attachment: Attachment
    var size: CGFloat = 96

    private var url: URL {
        if attachment.path.hasPrefix("/") { return URL(fileURLWithPath: attachment.path) }
        return state.paths.root.appendingPathComponent(attachment.path)
    }

    @State private var markingUp = false
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            thumbnail
        }
        .buttonStyle(.plain)
        .help(attachment.caption ?? attachment.path)
        .overlay(alignment: .bottomTrailing) {
            // Mark up an attached screenshot afterwards (decision E3); the marks replace the file.
            if hovering, NSImage(contentsOf: url) != nil {
                Button { markingUp = true } label: { Image(systemName: "pencil.tip.crop.circle") }
                    .buttonStyle(.bordered).controlSize(.small).padding(4)
                    .help("Mark up: box, arrow or note")
            }
        }
        .overlay(alignment: .topTrailing) { uploadBadge.padding(4) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Mark Up…") { markingUp = true }
            Button("Open") { NSWorkspace.shared.open(url) }
        }
        .sheet(isPresented: $markingUp) {
            if let data = try? Data(contentsOf: url) {
                ScreenshotMarkupSheet(data: data) { png in
                    state.perform("Could not save the marked-up screenshot") { try TicketScreenshots.replace(attachment, with: png, state: state) }
                }
            }
        }
        .hatchMark("AttachmentThumb")
    }

    /// Whether the screenshot is in the tickets repository yet (decision M3). A failure is the only red one.
    @ViewBuilder private var uploadBadge: some View {
        if let error = attachment.uploadError, !attachment.isUploaded {
            Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(.white, Theme.critical)
                .help("Not uploaded: \(error). Hatch tries again at the next sync.")
        } else if attachment.isUploaded {
            Image(systemName: "checkmark.icloud.fill").foregroundStyle(.white, .secondary)
                .help("In the tickets repository: \(attachment.remotePath ?? "")")
        } else {
            Image(systemName: "icloud.and.arrow.up").foregroundStyle(.secondary)
                .padding(2).background(.regularMaterial, in: Circle())
                .help("Uploads to the tickets repository at the next sync, once the ticket has an issue")
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
