import SwiftUI
import UniformTypeIdentifiers
import HatchCore
import HatchComponentKit

// The app's own components (concept `design-review/components-own-concept.html`, CM16 to CM20): a family's page with
// one box per group, titled above it with what Hatch thinks and whether it waits for the owner; inside, today's views
// that would become it. Selecting a group or a view fills the inspector with its details and its decision. A view is
// moved by right-clicking it, by its Group pop-up, or by dragging it onto another box; a whole group merges the same way.

// MARK: The page

struct OwnFamilyView: View {
    @ObservedObject var model: DesignerModel
    let family: String
    @State private var naming: NamingRequest?

    var body: some View {
        let groups = model.ownGroups(family)
        let views = groups.reduce(0) { $0 + $1.views.count }, toDecide = groups.filter { !$0.decided }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(views) view\(views == 1 ? "" : "s") · Hatch suggests \(groups.count) component\(groups.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                Text(toDecide == 0 ? "All decided" : "\(toDecide) to decide").foregroundStyle(.secondary)
            }
            ForEach(groups) { entry in
                OwnGroupBox(model: model, entry: entry, others: model.ownEntries.filter { $0.id != entry.id }) { views in
                    naming = NamingRequest(views: views, from: entry.id)
                }
            }
            if let notice = model.ownNotice {
                HStack {
                    Text(notice)
                    Spacer()
                    if model.ownNoticeCanUndo { Button("Undo") { model.undo(); model.ownNotice = nil }.buttonStyle(.link) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
            }
            OwnPicturesFooter(model: model, ids: groups.flatMap(\.views))
        }
        .onChange(of: family) { _, _ in model.ownPick = nil; model.ownNotice = nil }
        .sheet(item: $naming) { req in
            NewComponentSheet(views: req.views) { title in
                if let from = model.ownEntry(req.from) { model.newComponent(req.views, from: from, title: title) }
                naming = nil
            } cancel: { naming = nil }
        }
    }
}

/// Whether the app has drawn these views, and the two things that change it: a ticket for an agent to draw the missing
/// ones, and drawing the app's screens again (CM21).
struct OwnPicturesFooter: View {
    @ObservedObject var model: DesignerModel
    let ids: [String]

    var body: some View {
        let missing = ids.filter { model.ownPicture($0, dark: false) == nil }.count, n = ids.count
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(missing == 0 ? (n == 1 ? "Drawn by the app." : "All \(n) views drawn by the app.")
                     : missing == n ? (n == 1 ? "The app doesn't draw this view yet, so Hatch can't show it." : "The app doesn't draw these views yet, so Hatch can't show them.")
                     : "\(missing) of \(n) views aren't drawn by the app yet, so Hatch can't show \(missing == 1 ? "it" : "them").")
                if missing > 0 { Button("Draw Them…") { model.drawMissing() }.buttonStyle(.link).help("Files a ticket for an agent to make the app draw them") }
            }
            HStack(spacing: 10) {
                if model.captureState?.running == true {
                    ProgressView().controlSize(.small)
                    Text(model.captureState?.message ?? "")
                } else {
                    Text(model.captureState?.message.isEmpty == false ? model.captureState!.message : capturedWhen)
                    Button("Capture Again") { model.captureAgain() }.buttonStyle(.link).help("Hatch runs the app's snapshots and keeps the new pictures")
                }
            }
        }
        .font(.callout).foregroundStyle(.secondary)
        .hatchMark("OwnPicturesFooter")
    }

    private var capturedWhen: String {
        // When Hatch kept them: the screens folder's marker is written by each capture.
        guard let screens = model.captures?.screens, !screens.isEmpty, let folder = model.capturesFolder,
              let date = try? folder.appendingPathComponent("\(ComponentCaptures.screensFolder)/.gitignore").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return "No pictures of the app yet." }
        let n = Set(screens.filter { !$0.isGallery }.map(\.name)).count
        return "Pictures from \(n) screens of the app, drawn \(date.formatted(date: .abbreviated, time: .shortened))."
    }
}

struct NamingRequest: Identifiable { var views: [String]; var from: String; var id: String { views.joined(separator: ",") } }

/// One group: its title above its own box, never a row in it.
struct OwnGroupBox: View {
    @ObservedObject var model: DesignerModel
    let entry: OwnEntry
    let others: [OwnEntry]
    let newComponent: ([String]) -> Void
    @State private var targeted = false

    private var selected: Bool { model.ownPick == .group(entry.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.decided {
                    Label("Decided", systemImage: "checkmark").font(.callout.weight(.semibold)).foregroundStyle(.green)
                } else {
                    Text("To decide").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture { model.ownPick = .group(entry.id) }
            .draggable("group:" + entry.id)
            .contextMenu { groupMenu }
            VStack(spacing: 0) {
                ForEach(Array(entry.views.enumerated()), id: \.element) { i, id in
                    if i > 0 { Divider().padding(.leading, 14) }
                    OwnRow(model: model, id: id, entry: entry, others: others, newComponent: newComponent)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected || targeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected || targeted ? 2 : 0.5)
            }
            // Drop a view to move it here, or a group's title to merge that group in.
            .dropDestination(for: String.self) { items, _ in
                for item in items {
                    if item.hasPrefix("group:"), let from = model.ownEntry(String(item.dropFirst(6))) { model.merge(from, into: entry) }
                    else if !entry.views.contains(item) { model.move([item], to: entry) }
                }
                return true
            } isTargeted: { targeted = $0 }
        }
        .hatchMark("OwnGroupBox")
    }

    private var subtitle: String {
        if entry.decided, let c = entry.component {
            return (c.codeName.map { "\($0) · " } ?? "") + (c.ticket == nil ? "decided" : "a ticket makes it so in the code")
        }
        // What they are for, when Hatch could read it (CM22): "…one thing: they show a state".
        let purpose = entry.proposal?.purpose
        return entry.views.count > 1 ? "Hatch thinks these \(entry.views.count) views are one thing" + (purpose.map { ": they \($0)" } ?? "")
            : "Hatch thinks this is a component of its own" + (purpose.map { ": it \(AppViewScanner.thirdPerson($0))" } ?? "")
    }

    @ViewBuilder private var groupMenu: some View {
        let targets = others.filter { $0.family == entry.family }
        if !targets.isEmpty {
            Menu("Merge Into") { ForEach(targets) { t in Button(t.title) { model.merge(entry, into: t) } } }
        }
        if entry.views.count > 1 { Button("Keep Them Apart") { model.keepApart(entry) } }
    }
}

/// One view in a group: its picture, its name in the code with what it shows, and how much it is used.
struct OwnRow: View {
    @ObservedObject var model: DesignerModel
    let id: String
    let entry: OwnEntry
    let others: [OwnEntry]
    let newComponent: ([String]) -> Void

    var body: some View {
        let view = model.ownView(id)
        let selected = model.ownPick == .view(id)
        HStack(spacing: 14) {
            OwnThumb(model: model, id: id).frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(id).fontWeight(.medium)
                Text(shows(view)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(view?.uses ?? 0) use\(view?.uses == 1 ? "" : "s")")
                Text("\(view?.usedOn.count ?? 0) screen\(view?.usedOn.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.ownPick = .view(id) }
        .draggable(id)
        .contextMenu {
            Menu("Move To") {
                ForEach(others.filter { $0.family == entry.family }) { t in Button(t.title) { model.move([id], to: t) } }
                Divider()
                Button("New Component…") { newComponent([id]) }
            }
            Button("Not a Component") { model.notComponent([id]) }
            Divider()
            if let view { Button("Open \((view.file as NSString).lastPathComponent):\(view.line)") { model.openInXcode(view.file, line: view.line) } }
        }
        .hatchMark("OwnRow")
    }

    private func shows(_ v: AppView?) -> String {
        guard let v else { return "" }
        if !v.shows.isEmpty { return "Shows " + v.shows.prefix(3).map { "“\($0)”" }.joined(separator: ", ") }
        return v.usedOn.first.map { "On \($0.name)" } ?? "Not used outside its file"
    }
}

/// A view's picture from the app's gallery, blended into whatever is behind it; or a plain note when it isn't drawn.
struct OwnThumb: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var height: CGFloat = 22
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let image = model.ownPicture(id, dark: scheme == .dark) {
                // Always the same height, so a wide view is cut at the column (and fades) rather than shrunk to nothing.
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: image.size.height > 0 ? height * image.size.width / image.size.height : height, height: height)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
                    // A view wider than the column fades out instead of being cut.
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                    // Last, so the gallery's own background melts into the box behind it (a mask applied after would isolate it).
                    .blendMode(scheme == .dark ? .lighten : .multiply)
            } else {
                Text("Not drawn yet").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .hatchMark("OwnThumb")
    }
}

/// Name a component made from views of another.
struct NewComponentSheet: View {
    let views: [String]
    let create: (String) -> Void
    let cancel: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Component").font(.headline)
            Text("\(views.joined(separator: ", ")) leaves this group and becomes a component of its own, listed in the sidebar. Nothing in your app changes.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name, prompt: Text("Footer status"))
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Create") { create(name.trimmingCharacters(in: .whitespaces)) }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 400)
    }
}

// MARK: The inspector

struct OwnInspector: View {
    @ObservedObject var model: DesignerModel
    let family: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.ownPick {
                case .group(let id)?:
                    if let entry = model.ownEntry(id) { OwnGroupInspector(model: model, entry: entry).id(entry.id + entry.views.joined()) }
                case .view(let id)?:
                    if let view = model.ownView(id) { OwnViewInspector(model: model, view: view) }
                case nil:
                    let groups = model.ownGroups(family)
                    Text(DesignerModel.familyTitle(family)).font(.title3.weight(.semibold))
                    Text("\(groups.filter { !$0.decided }.count) to decide").foregroundStyle(.secondary).padding(.top, 2)
                    InspectorHeading("Next")
                    Text("Select a group to decide it, or a view to see where it's used. Right-click a view to move it; drag a group's title onto another to merge them.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InspectorHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 16).padding(.bottom, 6).hatchMark("InspectorHeading") }
}

/// The decision for one group: today's views, the one component after, whether the look changes, what happens.
struct OwnGroupInspector: View {
    @ObservedObject var model: DesignerModel
    let entry: OwnEntry
    @State private var name = ""
    @State private var codeName = ""
    @State private var codeEdited = false
    @State private var look: String?
    @State private var redesigning = false
    @State private var what = ""

    var body: some View {
        let views = entry.views
        let compare = model.compare(entry)
        let changesCode = views.count > 1 || codeName != views.first
        VStack(alignment: .leading, spacing: 0) {
            if entry.decided, let c = entry.component {
                Text(c.title).font(.title3.weight(.semibold))
                Text("Decided · \(views.count) view\(views.count == 1 ? "" : "s") today").foregroundStyle(.secondary).padding(.top, 2)
                InspectorHeading("In the code")
                Text(c.ticket.map { "“\($0)”: an agent makes it so; you review it in Decide." } ?? "\(c.codeName ?? c.title), as it is.")
                    .fixedSize(horizontal: false, vertical: true)
                InspectorHeading("For agents")
                Text("Use \(c.codeName ?? c.title) wherever this is shown. The README says so.").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack { Button("Redesign…") { what = ""; redesigning = true }.popover(isPresented: $redesigning) { redesignPopover } }.padding(.top, 18)
            } else {
                Text(views.count > 1 ? "Make \(list(views)) one component?" : "Make \(views[0]) a component?")
                    .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                InspectorHeading("Today · \(views.count) view\(views.count == 1 ? "" : "s")")
                OwnPictureList(model: model, ids: views)
                if !compare.same {
                    InspectorHeading("The look")
                    Text(compare.words + " Which one does it keep?").fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(views, id: \.self) { id in
                            Button { look = id } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: look == id ? "largecircle.fill.circle" : "circle").foregroundStyle(look == id ? Color.accentColor : .secondary)
                                    OwnThumb(model: model, id: id, height: 18)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
                InspectorHeading("After · 1 component")
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow { Text("Name").foregroundStyle(.secondary); TextField("Name", text: $name) }
                    GridRow { Text("In code").foregroundStyle(.secondary)
                        TextField("Code name", text: Binding(get: { codeName }, set: { codeName = $0; codeEdited = true })).font(.body.monospaced()) }
                }
                Text(compare.same ? (views.count > 1 ? "The look doesn't change: they're drawn alike today." : "Its look stays as it is.")
                     : (look == nil ? "Choose the look it keeps above." : "It keeps the look of \(look!)."))
                    .foregroundStyle(.secondary).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                InspectorHeading("What happens")
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Agents use \(name.isEmpty ? "it" : name) wherever this is shown.")
                    Text(changesCode ? "2. Hatch files a ticket: the code gets one \(codeName.isEmpty ? "view" : codeName) and every use moves to it. You review it in Decide."
                         : "2. Nothing in the code changes: \(codeName) stays as it is.")
                    if changesCode { Text("3. Your app doesn't change until that ticket is done.") }
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    Button { model.decide(entry, title: name, codeName: codeName, look: compare.same ? nil : look) } label: {
                        Text(views.count > 1 ? "Make One \(name.isEmpty ? "Component" : name)" : "Make It a Component").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || codeName.isEmpty || (!compare.same && look == nil))
                    if views.count > 1 {
                        Button { model.keepApart(entry) } label: { Text("Keep Them Apart").frame(maxWidth: .infinity) }.controlSize(.large)
                    } else {
                        Button { model.notComponent(views) } label: { Text("Not a Component").frame(maxWidth: .infinity) }.controlSize(.large)
                    }
                }
                .padding(.top, 18)
                let targets = model.ownEntries.filter { $0.family == entry.family && $0.id != entry.id }
                if !targets.isEmpty {
                    Menu("Merge Into Another Group") { ForEach(targets) { t in Button(t.title) { model.merge(entry, into: t) } } }
                        .menuStyle(.borderlessButton).fixedSize().padding(.top, 12)
                }
            }
        }
        .onAppear {
            name = entry.component?.title ?? entry.title
            codeName = entry.component?.codeName ?? (entry.views.count == 1 ? entry.views[0] : Self.typeName(name))
            look = entry.component?.look
        }
        .onChange(of: name) { _, new in if !codeEdited && entry.views.count > 1 { codeName = Self.typeName(new) } }
    }

    private var redesignPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Redesign \(entry.title)").font(.headline)
            Text("An agent builds two or three options, and the native one where SwiftUI has it, as specimens; you pick.").font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("What should change?", text: $what, axis: .vertical).lineLimit(2...5).frame(width: 300)
            HStack { Spacer(); Button("Ask for Options") { model.ownRedesign(entry, what: what); redesigning = false }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(what.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(14)
    }

    private func list(_ views: [String]) -> String {
        let names = views
        return names.count <= 2 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// "Status chip" → StatusChip.
    static func typeName(_ title: String) -> String {
        title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}

/// A few views as a list: the picture, and the name in the code at the end.
struct OwnPictureList: View {
    @ObservedObject var model: DesignerModel
    let ids: [String]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                if i > 0 { Divider() }
                HStack(spacing: 10) {
                    OwnThumb(model: model, id: id, height: 18)
                    Text(id).font(.callout).foregroundStyle(.secondary).fixedSize()
                }
                .padding(.horizontal, 10).frame(minHeight: 36)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
        .hatchMark("OwnPictureList")
    }
}

/// One view: its pictures, its group, what it shows, every screen it is used on.
struct OwnViewInspector: View {
    @ObservedObject var model: DesignerModel
    let view: AppView

    var body: some View {
        let entry = model.ownEntries.first { $0.views.contains(view.id) }
        VStack(alignment: .leading, spacing: 0) {
            Text(view.id).font(.title3.weight(.semibold))
            Text("\(view.uses) use\(view.uses == 1 ? "" : "s") on \(view.usedOn.count) screen\(view.usedOn.count == 1 ? "" : "s")").foregroundStyle(.secondary).padding(.top, 2)
            VStack(spacing: 6) {
                ForEach([false, true], id: \.self) { dark in
                    if let image = model.ownPicture(view.id, dark: dark) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 24, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
                    }
                }
            }
            .padding(.top, 12)
            if let entry {
                InspectorHeading("Group")
                Picker("Group", selection: Binding(get: { entry.id }, set: { id in
                    if let t = model.ownEntry(id) { model.move([view.id], to: t) }
                })) {
                    ForEach(model.ownEntries.filter { $0.family == entry.family }) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
            }
            if !view.shows.isEmpty {
                InspectorHeading("Shows")
                Text(view.shows.map { "“\($0)”" }.joined(separator: ", ")).fixedSize(horizontal: false, vertical: true)
            }
            OwnPlacesList(model: model, id: view.id)
            // What was measured about it on the app's screens (CM23); a click shows it on Checks on Screen.
            let found = model.findings.filter { $0.views.contains(view.id) }
            if !found.isEmpty {
                InspectorHeading("Measured")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(found.prefix(6).enumerated()), id: \.offset) { _, f in
                        Button { model.selection = .checks; model.checkPick = f } label: {
                            Text((f.problem ? "Problem: " : "Note: ") + f.words).frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(f.problem ? Color.primary : Color.secondary)
                    }
                    if found.count > 6 { Text("And \(found.count - 6) more on Checks on Screen.").foregroundStyle(.secondary) }
                }
            }
            InspectorHeading("In the code")
            if view.usedOn.isEmpty {
                Text("Not used outside its file.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(view.usedOn.enumerated()), id: \.offset) { i, screen in
                        if i > 0 { Divider() }
                        Button { model.openInXcode(screen.file, line: screen.line) } label: {
                            HStack { Text(screen.name); Spacer(); Text("\(screen.count)").foregroundStyle(.secondary).monospacedDigit() }
                                .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open the first use on \(screen.name) in Xcode")
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
            }
            Button("Open \((view.file as NSString).lastPathComponent):\(view.line)") { model.openInXcode(view.file, line: view.line) }
                .buttonStyle(.link).padding(.top, 14)
        }
    }
}

/// Where the app draws a view: each screen it is on, cut around one use with the view outlined; a click shows the whole
/// screen with every use outlined (CM21).
struct OwnPlacesList: View {
    @ObservedObject var model: DesignerModel
    let id: String
    @Environment(\.colorScheme) private var scheme
    @State private var shown: CapturedScreen?

    var body: some View {
        let places = model.captures?.places(of: id, dark: scheme == .dark).filter { !$0.screen.isGallery } ?? []
        let byScreen = Dictionary(grouping: places, by: \.screen.name).sorted { ($1.value.count, $0.key) < ($0.value.count, $1.key) }
        Group {
            InspectorHeading("On screen")
            if byScreen.isEmpty {
                Text(model.ownPicture(id, dark: scheme == .dark) == nil ? "The app doesn't draw it yet." : "Only in the app's gallery: no screen it draws shows it.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(byScreen.prefix(8), id: \.key) { name, ps in
                        Button { shown = ps[0].screen } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                OwnPlaceThumb(model: model, place: ps.first(where: \.whole) ?? ps[0])
                                Text(ps[0].screen.title + (ps.count > 1 ? " · \(ps.count) times" : "")).font(.callout).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show the whole screen")
                    }
                    if byScreen.count > 8 { Text("And \(byScreen.count - 8) more screens.").font(.callout).foregroundStyle(.secondary) }
                }
                .sheet(item: $shown) { screen in OwnScreenSheet(model: model, screen: screen, id: id) { shown = nil } }
            }
        }
        .hatchMark("OwnPlacesList")
    }
}

extension CapturedScreen: Identifiable { public var id: String { picture.path } }

/// One use cut out with some of the screen around it, the view outlined in the accent colour.
struct OwnPlaceThumb: View {
    @ObservedObject var model: DesignerModel
    let place: ComponentCaptures.Place
    var height: CGFloat = 96

    var body: some View {
        // Wider than high, so the cut fills the inspector's width and shows what is beside the view.
        let f = place.frame, b = place.screen.bounds
        let mx = max(80, f.width * 0.6), my = max(24, f.height * 0.4)
        let x0 = max(b.x, f.x - mx), y0 = max(b.y, f.y - my)
        let around = CaptureRect(x: x0, y: y0, width: min(b.maxX, f.maxX + mx) - x0, height: min(b.maxY, f.maxY + my) - y0)
        Group {
            if let image = model.crop(place.screen, around) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { g in
                            let k = g.size.width / around.width
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: f.width * k + 6, height: f.height * k + 6)
                                .offset(x: (f.x - around.x) * k - 3, y: (f.y - around.y) * k - 3)
                        }
                    }
                    .frame(maxHeight: height, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
            }
        }
        .hatchMark("OwnPlaceThumb")
    }
}

/// A whole screen as the app drew it, every use of the view outlined.
struct OwnScreenSheet: View {
    @ObservedObject var model: DesignerModel
    let screen: CapturedScreen
    let id: String
    let close: () -> Void

    var body: some View {
        let frames = screen.file.marks.indices.filter { screen.file.marks[$0].name == id }.compactMap { screen.frame($0) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(screen.title).font(.headline)
                Text("\(id), \(frames.count == 1 ? "once" : "\(frames.count) times")").foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            if let image = model.crop(screen, screen.bounds) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { g in
                            let k = g.size.width / max(1, screen.bounds.width)
                            ForEach(Array(frames.enumerated()), id: \.offset) { _, f in
                                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2)
                                    .frame(width: f.width * k + 6, height: f.height * k + 6)
                                    .offset(x: f.x * k - 3, y: f.y * k - 3)
                            }
                        }
                    }
                    .frame(width: 900)
            }
        }
        .padding(20)
    }
}

// MARK: Not Sure Yet

/// The views Hatch could not place: each with Hatch's reason and its picture, to be answered once.
struct OwnQuestionsView: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hatch read these views but can't tell what they are from their code.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(model.ownQuestions.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { Divider().padding(.leading, 14) }
                    HStack(alignment: .top, spacing: 14) {
                        OwnThumb(model: model, id: v.id).frame(width: 190, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.title).fontWeight(.medium)
                            Text(v.reason).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("Open") { model.openInXcode(v.file, line: v.line) }.buttonStyle(.link)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
        }
    }
}
