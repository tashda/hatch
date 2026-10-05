import SwiftUI
import HatchCore
import HatchComponentKit

/// What an answer about the design system looks like, drawn (owner's request after CP5: "I need it visualized").
/// A design system question or a change Proposal in Decide carries one per option: the role drawn with that option's
/// look in its places, beside the roles it sits with. Drawn by HatchComponentKit, so no model call and no project code.
struct ComponentOptionSample: Hashable {
    let id: String
    let role: ComponentRole
    /// The look this option gives the role; nil draws the role as it is today (Not sure yet, Keep today's look).
    let recipe: [String: String]?
    let places: [String]
    let system: ComponentSystem

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.recipe == b.recipe }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Adds a drawing to each answer of a design system question or change Proposal, and says each look in plain words.
    /// Other tickets come back unchanged.
    @MainActor
    static func attach(_ choices: [AnswerOption], ticket: Ticket, state: AppState) -> [AnswerOption] {
        guard ticket.area == ComponentsSetup.area,
              let notebook = state.project(id: ticket.projectId)?.config?.repo(.notebook)?.localPath,
              let system = (try? ComponentSystem.load(notebook: notebook)) ?? nil else { return choices }
        let qid = ComponentsSetup.componentQuestionId(inBody: ticket.body)
            ?? (ComponentsSetup.changedRole(inBody: ticket.body) != nil ? ComponentsSetup.changeQuestionId(ticketId: ticket.id) : nil)
        guard let qid, let q = system.questions.first(where: { $0.id == qid }),
              let role = q.role.flatMap({ system.role($0) }), let element = ComponentElement.named(role.element) else { return choices }
        let places = Array((q.place.map { [$0] } ?? role.places).prefix(2))
        return choices.map { c in
            guard let i = Int(c.id), q.options.indices.contains(i) else { return c }
            let o = q.options[i]
            var out = c
            // Following macOS draws the control with no look of its own: what SwiftUI does by default.
            let recipe = o.follow == true ? [:] : o.recipe.map { element.look($0) }
            if let recipe { out.title = ComponentWords.look(element: role.element, recipe: recipe) + (o.custom.map { " (\($0))" } ?? "") }
            out.sample = ComponentOptionSample(id: "\(qid).\(i)", role: role, recipe: recipe, places: places, system: system)
            return out
        }
    }
}

/// The places of one option, side by side, small. Wraps when the card is narrow.
struct ComponentOptionPreview: View {
    let sample: ComponentOptionSample

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(sample.places, id: \.self) { place in
                VStack(alignment: .leading, spacing: 4) {
                    RecipePlaceSample(place: place, role: sample.role, recipe: sample.recipe, system: sample.system)
                    Text(ComponentPlace.title(place)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 4)
    }
}
