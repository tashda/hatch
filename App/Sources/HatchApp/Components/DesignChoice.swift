import SwiftUI
import AppKit
import HatchCore
import HatchComponentKit

// "There is a design to choose from" (owner's request after CP5): one way to show any decision about a look, so every
// such decision in Decide looks the same and its look is set once, in the Decide Lab. A decision gives its options as
// pictures (a design system answer drawn by HatchComponentKit now; a Stage specimen or a sketch later) and this view
// lays them out in the chosen style. DR8 chose "large with a filmstrip, chosen by picture" as the default.

/// The options of a decision about a look, each with a picture.
struct DesignChoice {
    struct Option: Identifiable {
        /// The answer's key in Decide ("0", "1"…); "today" for the look as it is.
        let id: String
        var name: String
        var note: String? = nil
        var recommended = false
        var isToday = false
        /// The option where it lives, large; `allPlaces` false draws only its main place.
        var large: (_ allPlaces: Bool) -> AnyView
        /// The option on its own, small, for a filmstrip.
        var small: () -> AnyView
    }

    var options: [Option]
    /// Where to judge it in depth (the Designer, the Stage), for the Stage card layout.
    var openTitle: String? = nil
    var open: (() -> Void)? = nil

    var today: Option? { options.first(where: \.isToday) }
    var choices: [Option] { options.filter { !$0.isToday } }
}

/// How a design is shown; picked in the Decide Lab, used by every decision about a look.
struct DesignChoiceStyle: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case hero, gallery, compare, carousel, split, stageCard
        var id: String { rawValue }
        var title: String {
            ["hero": "Large with a filmstrip", "gallery": "Gallery", "compare": "Today beside the pick", "carousel": "One at a time",
             "split": "Large beside its words", "stageCard": "Open to judge"][rawValue]!
        }
        var about: String {
            switch self {
            case .hero: "The selected option large, every option small under it; pressing 1 to 4 flips the large one in place."
            case .gallery: "Every option large, side by side; click one to choose it."
            case .compare: "Today on the left, the selected option on the right, the options in a segmented control."
            case .carousel: "One large option with arrows and dots."
            case .split: "The selected option large, its words beside it."
            case .stageCard: "Small pictures and a button to judge them in the Designer or the Stage."
            }
        }
    }
    enum Frame: String, Codable, CaseIterable, Identifiable {
        case none, hairline, card
        var id: String { rawValue }
        var title: String { ["none": "No frame", "hairline": "Hairline", "card": "Raised card"][rawValue]! }
        var about: String { "Around each picture. No frame draws the place as the real thing on the canvas." }
    }
    enum Canvas: String, Codable, CaseIterable, Identifiable {
        case plain, grey
        var id: String { rawValue }
        var title: String { ["plain": "On the card", "grey": "Grey canvas"][rawValue]! }
        var about: String { "What the pictures sit on." }
    }
    enum Today: String, Codable, CaseIterable, Identifiable {
        case filmstrip, toggle, beside, hidden
        var id: String { rawValue }
        var title: String { ["filmstrip": "First in the filmstrip", "toggle": "Hold to see Today", "beside": "Beside the pick", "hidden": "Not shown"][rawValue]! }
        var about: String { "Where the look as it is today appears, when the decision has one." }
    }
    enum Places: String, Codable, CaseIterable, Identifiable {
        case main, all
        var id: String { rawValue }
        var title: String { ["main": "The main place", "all": "Every place"][rawValue]! }
        var about: String { "A design system answer in one place, or in each place its role is used." }
    }

    var layout = Layout.hero
    var frame = Frame.none
    var canvas = Canvas.grey
    var today = Today.filmstrip
    var places = Places.all

    static let key = "lab.decide.designChoice"

    /// The owner's pick from the Decide Lab, or DR8's default.
    static var current: DesignChoiceStyle {
        guard let data = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(DesignChoiceStyle.self, from: data) else { return .init() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - The view

/// A decision's design options, laid out in the chosen style. `selection` is Decide's: choosing a picture selects the
/// answer with the same key.
struct DesignChoiceView: View {
    let choice: DesignChoice
    @Binding var selection: String
    var style = DesignChoiceStyle.current
    @State private var showingToday = false

    private var selected: DesignChoice.Option? {
        choice.choices.first { $0.id == selection } ?? choice.choices.first(where: \.recommended) ?? choice.choices.first
    }
    private var shown: DesignChoice.Option? { showingToday ? (choice.today ?? selected) : selected }

    var body: some View {
        content
            .padding(style.canvas == .grey ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.canvas == .grey ? AnyShapeStyle(.quaternary.opacity(0.35)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch style.layout {
        case .hero:
            VStack(alignment: .leading, spacing: 14) {
                if style.today == .beside, let today = choice.today, let selected {
                    HStack(alignment: .top, spacing: 20) { labelled(today); labelled(selected) }
                } else if let shown {
                    picture(shown)
                }
                caption
                filmstrip
            }
        case .gallery:
            FlowLayout(spacing: 18) {
                ForEach(choice.options.filter { style.today != .hidden || !$0.isToday }) { o in
                    Button { if !o.isToday { selection = o.id } } label: { labelled(o, selectable: true) }.buttonStyle(.plain)
                }
            }
        case .compare:
            VStack(alignment: .leading, spacing: 12) {
                // A pop-up: option names are words, too long for a segmented control.
                Picker("Option", selection: $selection) { ForEach(choice.choices) { Text($0.name).tag($0.id) } }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                HStack(alignment: .top, spacing: 20) {
                    if let today = choice.today { labelled(today) }
                    if let selected { labelled(selected) }
                }
            }
        case .carousel:
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).buttonBorderShape(.circle)
                    if let shown { picture(shown) }
                    Button { step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).buttonBorderShape(.circle)
                }
                caption
                HStack(spacing: 6) {
                    ForEach(choice.choices) { o in Circle().fill(o.id == selected?.id ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 6, height: 6) }
                }
            }
            .frame(maxWidth: .infinity)
        case .split:
            HStack(alignment: .top, spacing: 20) {
                if let shown { picture(shown) }
                caption
            }
        case .stageCard:
            HStack(spacing: 16) {
                HStack(spacing: 10) { ForEach(choice.choices.prefix(4)) { $0.small() } }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(choice.choices.count) options, drawn in their places").font(.headline)
                    if let title = choice.openTitle, let open = choice.open {
                        Button(title, action: open).buttonStyle(.glass)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The selected option's name, the recommendation and its words; Today on demand.
    @ViewBuilder private var caption: some View {
        if let o = shown {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(o.isToday ? "Today" : o.name).font(.headline)
                if o.recommended && !o.isToday {
                    Text("Recommended").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
                }
                Spacer(minLength: 8)
                if style.today == .toggle, choice.today != nil {
                    Text(showingToday ? "Showing Today" : "Hold to see Today")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .onLongPressGesture(minimumDuration: 0, maximumDistance: 40, pressing: { showingToday = $0 }, perform: {})
                        .help("Hold to see the look as it is today in the same place")
                }
            }
        }
    }

    /// Every option small: a click selects it, and the selected one is outlined.
    private var filmstrip: some View {
        FlowLayout(spacing: 10) {
            ForEach(choice.options.filter { !$0.isToday || style.today == .filmstrip }) { o in
                let on = !o.isToday && o.id == selected?.id && !showingToday
                Button { if o.isToday { showingToday.toggle() } else { showingToday = false; selection = o.id } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        o.small()
                            .frame(minWidth: 90, minHeight: 40)
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Color.accentColor : Color(nsColor: .separatorColor),
                                                                                  lineWidth: on ? 2 : 0.5))
                        HStack(spacing: 4) {
                            Text(o.isToday ? "Today" : o.name).font(.caption).lineLimit(1)
                                .foregroundStyle(o.isToday ? Color.secondary : Color.primary)
                            if o.recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.accentColor) }
                        }
                        .frame(maxWidth: 160, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .help(o.note ?? o.name)
            }
        }
    }

    private func labelled(_ o: DesignChoice.Option, selectable: Bool = false) -> some View {
        let on = selectable && o.id == selected?.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(o.isToday ? "Today" : o.name).font(.caption.weight(.semibold))
                    .foregroundStyle(o.isToday ? Color.secondary : (on ? Color.accentColor : Color.primary))
                if o.recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.accentColor) }
            }
            picture(o)
                .overlay { if on { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2).padding(-5) } }
        }
    }

    @ViewBuilder private func picture(_ o: DesignChoice.Option) -> some View {
        let drawing = o.large(style.places == .all)
        switch style.frame {
        case .none:
            drawing
        case .hairline:
            drawing.padding(10).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        case .card:
            drawing.padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        }
    }

    private func step(_ by: Int) {
        let list = choice.choices
        guard let at = list.firstIndex(where: { $0.id == selected?.id }) else { return }
        selection = list[(at + by + list.count) % list.count].id
    }
}

// MARK: - Design system answers

extension DesignChoice {
    /// A design system question or a change Proposal as a design to choose from: each option is its role drawn with that
    /// look in the role's places. Nil for any other ticket. Ids are the answers' keys, so a picture selects its answer.
    @MainActor
    static func component(ticket: Ticket, state: AppState) -> DesignChoice? {
        guard ticket.area == ComponentsSetup.area,
              let notebook = state.project(id: ticket.projectId)?.config?.repo(.notebook)?.localPath,
              let system = (try? ComponentSystem.load(notebook: notebook)) ?? nil else { return nil }
        let qid = ComponentsSetup.componentQuestionId(inBody: ticket.body)
            ?? (ComponentsSetup.changedRole(inBody: ticket.body) != nil ? ComponentsSetup.changeQuestionId(ticketId: ticket.id) : nil)
        guard let qid, let q = system.questions.first(where: { $0.id == qid }),
              let role = q.role.flatMap({ system.role($0) }), let element = ComponentElement.named(role.element) else { return nil }
        let places = Array((q.place.map { [$0] } ?? role.places).prefix(3))
        let project = state.project(id: ticket.projectId)

        func option(_ id: String, name: String, recipe: [String: String]?, recommended: Bool = false, isToday: Bool = false) -> Option {
            Option(id: id, name: name, recommended: recommended, isToday: isToday,
                   large: { all in
                       AnyView(FlowLayout(spacing: 16) {
                           ForEach(all ? places : Array(places.prefix(1)), id: \.self) { place in
                               VStack(alignment: .leading, spacing: 4) {
                                   RecipePlaceSample(place: place, role: role, recipe: recipe, system: system)
                                   Text(ComponentPlace.title(place)).font(.caption2).foregroundStyle(.secondary)
                               }
                           }
                       })
                   },
                   small: {
                       AnyView(RecipeControl(element: role.element, recipe: recipe ?? role.recipe, system: system, importance: role.importance,
                                             sample: SampleWords.content(role.importance, place: places.first ?? "page", base: SampleContent()))
                           .fixedSize().allowsHitTesting(false))
                   })
        }

        var options: [Option] = []
        // Today is the role's one look; a role whose looks still compete has none yet.
        if q.kind == .change { options.append(option("today", name: "Today", recipe: nil, isToday: true)) }
        for (i, o) in q.options.enumerated() {
            let recipe = o.follow == true ? [:] : o.recipe.map { element.look($0) }
            let name = o.follow == true ? "Follow macOS"
                : recipe.map { ComponentWords.look(element: role.element, recipe: $0) + (o.custom.map { " (\($0))" } ?? "") } ?? o.title
            options.append(option(String(i), name: name, recipe: recipe, recommended: i == q.recommended))
        }
        var choice = DesignChoice(options: options)
        if let project {
            choice.openTitle = "Open the Designer"
            choice.open = { StageLauncher.shared.openDesigner(project: project, state: state) }
        }
        return choice
    }
}

// MARK: - A look for snapshot runs

/// `--only design-choice`: the demo's design system question in every layout, in a window of its own, so the look can be
/// checked without opening Decide.
enum DesignChoiceHarness {
    @MainActor
    static func window(state: AppState, layout: DesignChoiceStyle.Layout) -> NSWindow? {
        guard let ticket = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.area == ComponentsSetup.area && $0.type == .question
                && ComponentsSetup.componentQuestionId(inBody: $0.body) != nil }),
              let choice = DesignChoice.component(ticket: ticket, state: state) else { return nil }
        var style = DesignChoiceStyle.current
        style.layout = layout
        let view = Harness(title: ticket.title, choice: choice, style: style)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        w.makeKeyAndOrderFront(nil)
        return w
    }

    private struct Harness: View {
        let title: String
        let choice: DesignChoice
        let style: DesignChoiceStyle
        @State private var selection = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("PICK ONE · \(style.layout.title.uppercased())").font(.caption.weight(.bold)).foregroundStyle(Theme.you)
                Text(title).font(.largeTitle.weight(.bold))
                DesignChoiceView(choice: choice, selection: $selection, style: style)
                Spacer(minLength: 0)
            }
            .padding(36)
            .frame(width: 900, height: 720, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
