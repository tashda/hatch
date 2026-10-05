import SwiftUI
import HatchCore
import HatchComponentKit

// One look for many (CD24 to CD26): a sheet that lists every role a change touches, drawn before and after, says where
// else each role sits, and lets each change everywhere or only in the place (a variant with a reason). Preview puts the
// whole change on the canvas; nothing is saved until Keep.

struct BatchSheet: View {
    @ObservedObject var model: DesignerModel
    let request: DesignerModel.BatchRequest
    @State private var batch: DesignerBatch
    /// For "one look for every … here": the setting and its value.
    @State private var parameter: String
    @State private var value: String
    @Environment(\.dismiss) private var dismiss

    init(model: DesignerModel, request: DesignerModel.BatchRequest) {
        self.model = model
        self.request = request
        let b = model.batch(for: request) ?? DesignerBatch(title: "", items: [])
        _batch = State(initialValue: b)
        if case .setting(let e, _) = request, let p = ComponentElement.named(e)?.parameters.first(where: { $0.isLook }) {
            _parameter = State(initialValue: p.id)
            _value = State(initialValue: p.values.first ?? "")
        } else {
            _parameter = State(initialValue: "")
            _value = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(batch.title).font(.title3.weight(.semibold))
            if case .setting(let e, let place) = request, let element = ComponentElement.named(e) { settingPicker(element, place: place) }
            if batch.items.isEmpty {
                Text("Nothing changes: every role here already looks like this.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(batch.items) { item in row(item); Divider() }
                    }
                }
                .frame(minHeight: 120, maxHeight: 360)
            }
            if batch.items.contains(where: \.onlyHere) {
                TextField("Why is \(batch.place.map(ComponentPlace.title) ?? "this place") different?", text: $batch.reason)
                    .help("Agents read it when they build there (CD26)")
            }
            Text("Preview draws it everywhere on the canvas; Keep saves it as one change, and ⌘Z undoes it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Preview") { model.tryBatch(batch); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(batch.items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func row(_ item: DesignerBatch.Item) -> some View {
        let role = model.system.role(item.role)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(role?.title ?? item.role).font(.callout.weight(.medium))
                if !item.otherPlaces.isEmpty {
                    Text("Also in " + item.otherPlaces.map(ComponentPlace.title).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)
            if let role {
                drawn(role, role.draft ?? role.recipe)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                drawn(role, item.recipe)
            }
            Spacer(minLength: 0)
            if batch.place != nil, !item.otherPlaces.isEmpty {
                Picker("Where", selection: Binding(get: { item.onlyHere }, set: { v in
                    if let i = batch.items.firstIndex(where: { $0.role == item.role }) { batch.items[i].onlyHere = v }
                })) {
                    Text("Everywhere").tag(false)
                    Text("Only Here").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help(item.onlyHere ? "A variant for this place, with the reason below" : "The role changes in every place it sits")
            }
        }
        .padding(.vertical, 8)
    }

    private func drawn(_ role: ComponentRole, _ recipe: [String: String]) -> some View {
        RecipeControl(element: role.element, recipe: recipe, system: model.system, importance: role.importance,
                      sample: SampleWords.content(role.importance, place: batch.place ?? role.places.first ?? "page", base: SampleContent()))
            .allowsHitTesting(false)
            .frame(minWidth: 90)
    }

    @ViewBuilder private func settingPicker(_ element: ComponentElement, place: String?) -> some View {
        let params = element.parameters.filter(\.isLook)
        HStack {
            Picker("Setting", selection: $parameter) {
                ForEach(params, id: \.id) { Text($0.title).tag($0.id) }
            }
            .fixedSize()
            if let p = element.parameter(parameter) {
                Picker("Value", selection: $value) {
                    Text("macOS default").tag("")
                    ForEach(p.values.filter { $0 != p.systemDefault }, id: \.self) { v in
                        Text(ComponentWords.value(element: element.id, parameter: p.id, value: v)).tag(v)
                    }
                }
                .labelsHidden().fixedSize()
            }
        }
        .onChange(of: parameter) { _, id in value = element.parameter(id)?.values.first ?? ""; rebuild(element, place) }
        .onChange(of: value) { _, _ in rebuild(element, place) }
    }

    private func rebuild(_ element: ComponentElement, _ place: String?) {
        guard let p = element.parameter(parameter) else { return }
        let reason = batch.reason
        batch = model.batchSetting(p, value.isEmpty ? nil : value, element: element.id, place: place)
        batch.reason = reason
    }
}

/// While something is previewed outside a role's own view (a batch, or a look tried from Templates or the Matrix):
/// what it is, and Discard or Keep.
struct BatchBanner: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        if let b = model.batch {
            bar("Preview: \(b.title)", "\(b.items.count) role\(b.items.count == 1 ? "" : "s")" + (b.items.contains(where: \.onlyHere) ? ", some only here" : ""))
        } else if !model.focused, let p = model.previews.values.first, let role = model.system.role(p.role) {
            bar("Preview: \(role.title), \(p.label)", "in \(role.places.count) place\(role.places.count == 1 ? "" : "s")")
        }
    }

    private func bar(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "eye").foregroundStyle(.orange)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Discard") { model.discard() }
            Button("Keep") { model.keep() }.buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}

/// The scope menu items for an element, a place, or an element in a place (CD4, CD24).
struct BatchMenuItems: View {
    @ObservedObject var model: DesignerModel
    let element: String?
    let place: String?

    var body: some View {
        let what = element.flatMap { ComponentElement.named($0)?.plural } ?? "Everything"
        let scope = place.map { " in \(ComponentPlace.title($0))" } ?? ""
        if place == nil, let element, ["button", "menu"].contains(element) {
            Button("Use Glass Where It Fits…") { model.request = .glass(element: element) }
        }
        ForEach(model.templates) { t in
            Button("Match \(t.title) for \(place == nil ? "All " : "")\(what)\(scope)…") { model.request = .template(t.id, element: element, place: place) }
        }
        Button("Follow macOS for \(place == nil ? "All " : "")\(what)\(scope)") { model.request = .follow(element: element, place: place) }
        if let element {
            Button("One Look for Every \(ComponentElement.named(element)?.title ?? element)\(place == nil ? "" : " Here")…") {
                model.request = .setting(element: element, place: place)
            }
        }
    }
}
