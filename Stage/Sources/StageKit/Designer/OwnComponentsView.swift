import SwiftUI
import HatchCore
import HatchComponentKit

// The app's own components (CM8 to CM15): what Hatch found in the app's code, grouped as it proposes, each view drawn by
// the app itself, where it is used, and what SwiftUI offers instead. Nothing here is a guess: a view without a picture
// says so, and a view Hatch could not place is a question.

/// One proposed component: Hatch's proposal, the native option, then every form with its views.
struct OwnComponentView: View {
    @ObservedObject var model: DesignerModel
    let proposal: AppComponentProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(proposal.members.count) view\(proposal.members.count == 1 ? "" : "s") in the app · \(proposal.uses) use\(proposal.uses == 1 ? "" : "s") · \(proposal.variants.count) form\(proposal.variants.count == 1 ? "" : "s") today")
                    .foregroundStyle(.secondary)
                Label(summary, systemImage: "lightbulb")
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            NativeOption(model: model, family: proposal.family)
            // Grouped as Hatch proposes them: what the owner decides on, each view with its own form today.
            ForEach(Array(proposal.sizes.enumerated()), id: \.offset) { _, size in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(proposal.sizes.count == 1 ? "One size" : size.name.capitalized).font(.headline)
                        Text("\(size.members.count) view\(size.members.count == 1 ? "" : "s")").font(.callout).foregroundStyle(.secondary)
                        if let note = size.note {
                            Text(note).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                    TileGrid(minWidth: 280) {
                        ForEach(size.members, id: \.self) { id in OwnViewTile(model: model, id: id) }
                    }
                }
            }
        }
    }

    /// The proposal in one sentence; the sizes below carry the detail.
    private var summary: String {
        let n = proposal.members.count, forms = proposal.variants.count, sizes = proposal.sizes.count
        if forms == 1 { return n == 1 ? "One view with a look of its own: a component, even used once." : "\(n) views draw the same \(proposal.family): already one component." }
        if sizes < forms { return "\(n) views in \(forms) forms. Hatch proposes \(sizes == 1 ? "one size" : "\(sizes) sizes"), below: each view moves to the nearest." }
        return "\(n) views in \(forms) forms: one component with \(forms) variants, below."
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

/// One of the app's views: its picture as the app draws it, its name, where it is used.
struct OwnViewTile: View {
    @ObservedObject var model: DesignerModel
    let id: String

    var body: some View {
        let view = model.ownView(id)
        VStack(alignment: .leading, spacing: 10) {
            OwnPicture(model: model, id: id)
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
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
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

/// The inspector for the app's own components: how much of the app is accounted for, and this component's views.
struct OwnInspector: View {
    @ObservedObject var model: DesignerModel
    let proposal: AppComponentProposal?

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
            if let proposal {
                InspectorSection(title: "Views in \(proposal.title)", footer: "Each one's look is read from its code; the picture is the app's own drawing.") {
                    ForEach(proposal.members, id: \.self) { id in
                        HStack {
                            Text(id).font(.callout.monospaced())
                            Spacer()
                            if let v = model.ownView(id) { Text("\(v.uses)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                        }
                    }
                }
            }
        }
        .padding(14) }
    }
}
