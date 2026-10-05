import SwiftUI
import HatchCore
import HatchComponentKit

// The app's own components (CM8 to CM15): what Hatch found in the app's code, grouped as it proposes, each view drawn by
// the app itself, where it is used, and what SwiftUI offers instead. Nothing here is a guess: a view without a picture
// says so, and a view Hatch could not place is a question.

/// One of the app's own components: Hatch's proposal or the agreed component, the native option, then each size with
/// its views. Views are selected on their tiles; the bar above them offers only what applies to the selection (CM17).
struct OwnComponentView: View {
    @ObservedObject var model: DesignerModel
    let entry: OwnEntry
    @State private var selected: Set<String> = []
    @State private var splitting = false
    @State private var newSize = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(counts).foregroundStyle(.secondary)
                if !entry.agreed {
                    HStack(alignment: .center, spacing: 12) {
                        Label(summary, systemImage: "lightbulb").frame(maxWidth: .infinity, alignment: .leading)
                        Button("Accept as Proposed") { model.changeOwn(entry, [:], label: "") }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let native = entry.component?.native {
                    Label("Replaced by SwiftUI's \(ComponentElement.named(native)?.title.lowercased() ?? native): agents use it instead of these views.", systemImage: "applelogo")
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            NativeOption(model: model, family: entry.family)
            selectionBar
            ForEach(Array(entry.sizes.enumerated()), id: \.offset) { _, size in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.sizes.count == 1 && !entry.agreed ? "One size" : size.name.capitalized).font(.headline)
                        Text("\(size.views.count) view\(size.views.count == 1 ? "" : "s")").font(.callout).foregroundStyle(.secondary)
                        if let note = size.note {
                            Text(note).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Color.orange.opacity(0.12), in: Capsule())
                        }
                        if size.setting != nil {
                            Text("a setting").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Button(allSelected(size) ? "Deselect" : "Select All") {
                            if allSelected(size) { selected.subtract(size.views) } else { selected.formUnion(size.views) }
                        }
                        .buttonStyle(.link).font(.callout)
                    }
                    if !size.use.isEmpty { Text("Used for: \(size.use)").font(.callout).foregroundStyle(.secondary) }
                    TileGrid(minWidth: 280) {
                        ForEach(size.views, id: \.self) { id in
                            OwnViewTile(model: model, id: id, selected: Binding(
                                get: { selected.contains(id) },
                                set: { if $0 { selected.insert(id) } else { selected.remove(id) } }))
                        }
                    }
                }
            }
        }
        .onChange(of: entry.id) { _, _ in selected = [] }
        .popover(isPresented: $splitting) { namePopover(title: "Split Into a New Component", field: "Name", action: "Split") {
            model.changeOwn(entry, ["op": .string("split"), "title": .string(name), "views": .array(selected.sorted().map { .string($0) })], label: "Split into \(name)")
            selected = []
        } }
        .popover(isPresented: $newSize) { namePopover(title: "Move to a New Size", field: "Size name", action: "Move") {
            move(to: name)
        } }
    }

    /// Only what applies to the selection, as one bar: move to a size, split out, clear.
    @ViewBuilder private var selectionBar: some View {
        if !selected.isEmpty {
            HStack(spacing: 10) {
                Text("\(selected.count) selected").font(.callout.weight(.semibold))
                Menu("Move to Size") {
                    ForEach(entry.sizes.map(\.name), id: \.self) { n in
                        Button(n.capitalized) { move(to: n) }.disabled(entry.sizes.first { $0.name == n }.map { Set($0.views).isSuperset(of: selected) } ?? false)
                    }
                    Divider()
                    Button("New Size…") { name = ""; newSize = true }
                }
                .fixedSize()
                .help("Consolidate: these views become this size of \(entry.title)")
                Button("Split Into New Component…") { name = ""; splitting = true }
                    .disabled(selected.count == entry.views.count)
                    .help(selected.count == entry.views.count ? "Every view is selected: rename the component instead" : "These views become a component of their own")
                Spacer()
                Button("Clear") { selected = [] }.buttonStyle(.link)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func allSelected(_ size: OwnEntry.Size) -> Bool { !size.views.isEmpty && Set(size.views).isSubset(of: selected) }

    private func move(to size: String) {
        model.changeOwn(entry, ["op": .string("move"), "variant": .string(size), "views": .array(selected.sorted().map { .string($0) })],
                        label: "Move \(selected.count) to \(size)")
        selected = []
    }

    private func namePopover(title: String, field: String, action: String, _ run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField(field, text: $name).frame(width: 260)
            HStack {
                Spacer()
                Button(action) { run(); splitting = false; newSize = false }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    private var counts: String {
        let n = entry.views.count
        let uses = entry.views.compactMap { model.ownView($0)?.uses }.reduce(0, +)
        return "\(n) view\(n == 1 ? "" : "s") in the app · \(uses) use\(uses == 1 ? "" : "s") · " + (entry.agreed ? "\(entry.component?.status.title ?? "")" : "proposed by Hatch")
    }

    private var summary: String {
        guard let p = entry.proposal else { return "" }
        let n = p.members.count, forms = p.variants.count, sizes = p.sizes.count
        if forms == 1 { return n == 1 ? "One view with a look of its own: a component, even used once." : "\(n) views draw the same \(p.family): already one component." }
        if sizes < forms { return "\(n) views in \(forms) forms. Hatch proposes \(sizes == 1 ? "one size" : "\(sizes) sizes"): each view moves to the nearest." }
        return "\(n) views in \(forms) forms: one component with \(forms) variants."
    }
}

/// What SwiftUI offers for this kind of component, drawn by SwiftUI, or said plainly when there is nothing.
struct NativeOption: View {
    @ObservedObject var model: DesignerModel
    let family: String

    var body: some View {
        let native = AppViewScanner.nativeOption(family: family)
        HStack(alignment: .center, spacing: 16) {
            if let e = native.element {
                RecipeControl(element: e, recipe: [:], system: model.system, importance: .other,
                              sample: SampleWords.content(.other, place: "page", base: model.sample))
                    .allowsHitTesting(false)
                    .fitted(1, maxHeight: 90)
                    .frame(width: 220)
            } else {
                Image(systemName: "applelogo").font(.title2).foregroundStyle(.tertiary).frame(width: 60)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("The native option").font(.callout.weight(.semibold))
                Text(native.words).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
    }
}

/// One of the app's views: its picture as the app draws it, its name, its form, where it is used. Clicking the tile
/// selects it for the component's actions.
struct OwnViewTile: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var selected: Binding<Bool>? = nil

    var body: some View {
        let view = model.ownView(id)
        let on = selected?.wrappedValue == true
        VStack(alignment: .leading, spacing: 10) {
            OwnPicture(model: model, id: id)
            HStack(alignment: .top, spacing: 8) {
                if let selected {
                    Image(systemName: selected.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(selected.wrappedValue ? Color.accentColor : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(id).font(.callout.monospaced().weight(.medium))
                    if let view, !view.style.form.isEmpty { Text(view.style.form).font(.caption).foregroundStyle(.secondary) }
                    if let view {
                        Text(view.uses == 0 ? "Not used outside its file" : "Used \(view.uses) time\(view.uses == 1 ? "" : "s") in " + view.usedIn.prefix(3).joined(separator: ", ")
                             + (view.usedIn.count > 3 ? " and \(view.usedIn.count - 3) more" : ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("Open " + (view.file as NSString).lastPathComponent + ":" + String(view.line)) { model.openInXcode(view.file, line: view.line) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(on ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: on ? 2 : 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { selected?.wrappedValue.toggle() }
    }
}

/// A view's picture in the Designer's appearance (both side by side in Both), or an honest gap.
struct OwnPicture: View {
    @ObservedObject var model: DesignerModel
    let id: String

    var body: some View {
        let schemes: [Bool] = model.appearance == .both ? [false, true] : [model.appearance == .dark]
        let images = schemes.compactMap { model.ownPicture(id, dark: $0) }
        Group {
            if images.isEmpty {
                // Not drawn yet: Hatch asks the gallery for it; nothing is drawn from memory.
                Label("Not in the app's gallery yet", systemImage: "photo.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(.tertiary) }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .frame(maxWidth: min(image.size.width, 520), maxHeight: 180, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The views Hatch could not place: each with Hatch's reason and its picture, to be answered once.
struct OwnQuestionsView: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hatch read these views but can't tell what they are from their code. Each answer is kept, so it is asked once.")
                .foregroundStyle(.secondary)
            TileGrid(minWidth: 320) {
                ForEach(model.ownQuestions) { v in
                    VStack(alignment: .leading, spacing: 8) {
                        OwnPicture(model: model, id: v.id)
                        Text(v.id).font(.callout.monospaced().weight(.medium))
                        Text(v.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Open " + (v.file as NSString).lastPathComponent + ":" + String(v.line)) { model.openInXcode(v.file, line: v.line) }
                            .buttonStyle(.link).font(.caption)
                    }
                    .padding(14)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
                }
            }
        }
    }
}

/// The inspector for the app's own components: how much of the app is accounted for, then the component's own
/// actions (native option, where each size is used, a setting, a redesign, agree), only those that apply.
struct OwnInspector: View {
    @ObservedObject var model: DesignerModel
    let entry: OwnEntry?
    @State private var redesigning = false
    @State private var what = ""

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            if let views = model.appViews {
                InspectorSection {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int((views.covered * 100).rounded()))% of the app accounted for").font(.title3.weight(.semibold))
                        Text("\(views.views.count) views: \(views.count(.component)) components, \(views.count(.screen)) screens, \(views.count(.unknown)) questions")
                            .font(.callout).foregroundStyle(.secondary)
                        let pictured = views.views.filter { $0.kind == .component && model.ownPicture($0.id, dark: false) != nil }.count
                        Text("\(pictured) of \(views.count(.component)) components drawn by the app so far").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let entry {
                let native = AppViewScanner.nativeOption(family: entry.family)
                if let element = native.element {
                InspectorSection(title: "Instead of these views", footer: "Agents use the native element; the views are replaced when their screens are next changed.") {
                        Toggle("Use SwiftUI's \(ComponentElement.named(element)?.title.lowercased() ?? element)", isOn: Binding(
                            get: { entry.component?.native == element },
                            set: { model.changeOwn(entry, ["op": .string("native"), "element": $0 ? .string(element) : .null], label: $0 ? "Use the native \(element)" : "Keep own views") }))
                }
                }
                InspectorSection(title: "Where Each Size Is Used", footer: "Agents read these to pick a size for a new screen.") {
                    ForEach(entry.sizes, id: \.name) { size in
                        UseField(model: model, entry: entry, size: size)
                    }
                }
                InspectorSection(footer: "A setting lets the app's users choose; a redesign asks an agent to build options to pick from.") {
                    // Only with sizes to choose between.
                    if entry.sizes.count > 1 {
                        Menu("Make a Size a Setting…") {
                            ForEach(entry.sizes, id: \.name) { size in
                                Button(size.name.capitalized) { model.ownSetting(entry, variant: size.name) }.disabled(size.setting != nil)
                            }
                        }
                        .help("Let people choose the size, with the one picked as the default")
                    }
                    if let ticket = entry.component?.redesign {
                        Label("Redesign asked: \(ticket)", systemImage: "paintbrush").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Button("Redesign…") { what = ""; redesigning = true }
                            .popover(isPresented: $redesigning) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Redesign \(entry.title)").font(.headline)
                                    Text("An agent builds two or three options and the native one as specimens; you pick.").font(.callout).foregroundStyle(.secondary)
                                    TextField("What should change?", text: $what, axis: .vertical).lineLimit(2...5).frame(width: 300)
                                    HStack { Spacer(); Button("Ask for Options") { model.ownRedesign(entry, what: what); redesigning = false }
                                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                                        .disabled(what.trimmingCharacters(in: .whitespaces).isEmpty) }
                                }
                                .padding(14)
                            }
                    }
                }
                if entry.agreed, entry.component?.status != .agreed {
                    InspectorSection {
                        Button("Agree \(entry.title)") { model.changeOwn(entry, ["op": .string("agree")], label: "Agree \(entry.title)") }
                            .help("Agents treat it as decided")
                    }
                }
            }
        }
        .padding(14) }
    }
}

/// Where one size is used, saved when the field is left.
private struct UseField: View {
    @ObservedObject var model: DesignerModel
    let entry: OwnEntry
    let size: OwnEntry.Size
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(size.name.capitalized).font(.callout.weight(.medium))
            TextField("Used for…", text: $text, axis: .vertical).lineLimit(1...3)
                .onSubmit(save)
        }
        .onAppear { text = size.use }
        .onChange(of: size.use) { _, new in text = new }
        .onDisappear(perform: save)
    }

    private func save() {
        guard text != size.use else { return }
        model.changeOwn(entry, ["op": .string("use"), "variant": .string(size.name), "text": .string(text)], label: "Where \(entry.title) \(size.name) is used")
    }
}
