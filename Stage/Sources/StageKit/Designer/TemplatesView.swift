import SwiftUI
import HatchCore
import HatchComponentKit

// Templates compared (CD47): this app with any template, or any two templates, cell by cell of the role table, drawn
// side by side. "Only differences" hides what already matches; on this app's side, Use This Look tries the other side's
// look on the app's role (previewed everywhere, kept with Keep).

struct TemplatesView: View {
    @ObservedObject var model: DesignerModel
    @State private var left = "app"
    @State private var right = ""
    @State private var onlyDifferences = true

    /// "app" is this app's system; anything else is a template id.
    private func system(_ id: String) -> ComponentSystem? {
        if id == "app" {
            var s = model.system
            // Previews show on the app's side, so trying a look is seen here too.
            for i in s.roles.indices { s.roles[i].recipe = model.look(of: s.roles[i]); s.roles[i].draft = nil
                if model.previews[s.roles[i].id]?.follow == true { s.roles[i].followsMacOS = true } }
            return s
        }
        return model.template(id)?.system(name: model.appName)
    }

    private func name(_ id: String) -> String { id == "app" ? model.appName : model.template(id)?.title ?? id }

    var body: some View {
        let rightId = right.isEmpty ? (model.system.template.flatMap { model.template($0) == nil ? nil : $0 } ?? model.recommendedTemplate.id) : right
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                picker("Compare", $left)
                Text("with").foregroundStyle(.secondary)
                picker("With", Binding(get: { rightId }, set: { right = $0 }))
                Spacer()
                Toggle("Only Differences", isOn: $onlyDifferences).toggleStyle(.checkbox)
            }
            if let a = system(left), let b = system(rightId) {
                let c = ComponentComparison(a, b)
                Text(c.differences == 0 ? "They draw every role the same." : "\(c.differences) of \(c.rows.count) cells are drawn differently.")
                    .font(.callout).foregroundStyle(.secondary)
                comparison(c, a: a, b: b, rightId: rightId)
            }
        }
    }

    private func picker(_ title: String, _ selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("\(model.appName) (this app)").tag("app")
            Divider()
            ForEach(model.templates) { t in
                Text(t.isShipped ? t.title : "\(t.title) (yours)").tag(t.id)
            }
        }
        .labelsHidden().fixedSize()
    }

    @ViewBuilder private func comparison(_ c: ComponentComparison, a: ComponentSystem, b: ComponentSystem, rightId: String) -> some View {
        let rows = c.rows.filter { !onlyDifferences || $0.differs }
        let places = rows.map(\.place).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("")
                Text(name(left)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(name(rightId)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("")
            }
            ForEach(places, id: \.self) { place in
                GridRow {
                    Text(ComponentPlace.title(place)).font(.headline).gridCellColumns(4).padding(.top, 8)
                }
                ForEach(rows.filter { $0.place == place }) { row in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ComponentElement.named(row.element)?.plural ?? row.element)
                            Text(row.importance.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 120, alignment: .leading)
                        cell(row.left, a, place)
                        cell(row.right, b, place)
                        if left == "app", row.differs, let mine = row.left, let theirs = row.right {
                            Button("Use This Look") {
                                model.tryLook(DesignerPreview(role: mine.id, recipe: theirs.draft ?? theirs.recipe, follow: theirs.followsMacOS,
                                                              label: "\(name(rightId))'s look"))
                            }
                            .help("Try \(name(rightId))'s look on \(mine.title) everywhere it sits; Keep saves it")
                        } else {
                            Text("")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ role: ComponentRole?, _ system: ComponentSystem, _ place: String) -> some View {
        if let role {
            VStack(alignment: .leading, spacing: 4) {
                RecipeControl(element: role.element, recipe: role.draft ?? role.recipe, system: system, importance: role.importance,
                              sample: SampleWords.content(role.importance, place: place, base: model.sample))
                    .allowsHitTesting(false)
                Text(role.followsMacOS ? "\(role.title), follows macOS" : role.title).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 160, alignment: .leading)
        } else {
            Text("No role").font(.caption).foregroundStyle(.tertiary).frame(minWidth: 160, alignment: .leading)
        }
    }
}

/// The templates: which one new projects start from, the owner's own, and saving this app's system as one (CD46, CD47).
struct TemplatesInspector: View {
    @ObservedObject var model: DesignerModel
    @State private var saving = false
    @State private var title = ""
    @State private var summary = ""

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            InspectorSection(footer: "New projects start from the marked template; with none marked, macOS Native.") {
                ForEach(model.templates) { t in
                    let marked = model.recommendedTemplate.id == t.id
                    HStack(alignment: .top) {
                        Image(systemName: marked ? "checkmark.circle.fill" : "circle").foregroundStyle(marked ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.callout.weight(.medium))
                            Text(detail(t)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Spacer()
                        Menu {
                            Button("Use for New Projects") { model.setDefaultTemplate(t.id == "native" ? nil : t.id) }.disabled(marked)
                            if !t.isShipped { Button("Remove", role: .destructive) { model.removeTemplate(t.id) } }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
                            .disabled(model.source.isLocal)
                    }
                }
            }
            InspectorSection(footer: "Saves \(model.appName)'s looks, rules and foundations under a name, for any project. Saving again under the same name makes the next version.") {
                Button("Save as Template…") { title = ""; summary = ""; saving = true }
                    .disabled(model.source.isLocal)
                    .help(model.source.isLocal ? "Open the Designer from Hatch to save templates" : "")
            }
        }
        .padding(14) }
        .popover(isPresented: $saving) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save as Template").font(.headline)
                TextField("Name", text: $title).frame(width: 280)
                TextField("What it is, one line", text: $summary, axis: .vertical).lineLimit(1...3).frame(width: 280)
                HStack {
                    Spacer()
                    Button("Save") { model.saveTemplate(title: title, summary: summary); saving = false }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
        }
    }

    private func detail(_ t: ComponentTemplate) -> String {
        guard let saved = model.savedTemplates.first(where: { $0.id == t.id }) else { return t.summary }
        let from = saved.from.map { ", from \($0)" } ?? ""
        return "Yours, version \(saved.version)\(from)" + (saved.summary.isEmpty ? "" : ". \(saved.summary)")
    }
}
