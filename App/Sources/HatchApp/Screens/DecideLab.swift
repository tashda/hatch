import SwiftUI
import AppKit
import HatchCore
import HatchAgent

// Decide Lab (decision DR7): the owner picks how each part of a Decide card looks by switching between real, native
// versions of it, on the real queue or on hard cases (long answers, two questions, a design, an agent's long question).
// Nothing here decides anything; it only draws. The combination is kept and can be copied.

// MARK: - Choices

/// One part of the card that has several looks.
protocol LabChoice: CaseIterable, Identifiable, Hashable, Codable, RawRepresentable where RawValue == String, AllCases: RandomAccessCollection {
    var title: String { get }
    var about: String { get }
}

extension LabChoice { var id: String { rawValue } }

enum LabLayout: String, LabChoice {
    case focus, inbox, spotlight, stack, split, sheet
    var title: String { ["focus": "Focus", "inbox": "Inbox", "spotlight": "Spotlight", "stack": "Stack", "split": "Split", "sheet": "Sheet"][rawValue]! }
    var about: String {
        switch self {
        case .focus: "One decision in a page-wide panel."
        case .inbox: "Like Mail: the queue on the left, the decision on the right."
        case .spotlight: "A compact floating glass panel over the dimmed app."
        case .stack: "A card with the next ones peeking behind it."
        case .split: "The ask and answers on the left, the design or the facts large on the right."
        case .sheet: "A sheet sliding down from the toolbar over the page, like a save dialog."
        }
    }
}

enum LabWidth: String, LabChoice {
    case narrow, medium, wide, full
    var title: String { ["narrow": "Narrow (560)", "medium": "Medium (680)", "wide": "Wide (820)", "full": "Full width"][rawValue]! }
    var about: String { "How wide the text column is." }
    var points: CGFloat { ["narrow": 560, "medium": 680, "wide": 820, "full": 4000][rawValue]! }
}

enum LabPosition: String, LabChoice {
    case top, third, centre
    var title: String { ["top": "Top", "third": "Upper third", "centre": "Centre"][rawValue]! }
    var about: String { "Where the card sits when it is shorter than the panel." }
}

enum LabSurface: String, LabChoice {
    case panel, window, material, card
    var title: String { ["panel": "White panel", "window": "Window background", "material": "Frosted", "card": "Card on grey"][rawValue]! }
    var about: String {
        switch self {
        case .panel: "A white panel like the other pages."
        case .window: "No panel: the content sits straight on the window's grey."
        case .material: "A translucent panel; the window shows through."
        case .card: "A grey panel with the decision on a white card (the first build)."
        }
    }
}

enum LabDensity: String, LabChoice {
    case compact, regular, airy, veryAiry
    var title: String { ["compact": "Compact", "regular": "Regular", "airy": "Airy", "veryAiry": "Very airy"][rawValue]! }
    var about: String { "The space between every part." }
    var scale: CGFloat { ["compact": 0.65, "regular": 1, "airy": 1.4, "veryAiry": 1.85][rawValue]! }
}

enum LabTitleSize: String, LabChoice {
    case headline, title3, title2, title1, large
    var title: String { ["headline": "Headline", "title3": "Title 3", "title2": "Title 2", "title1": "Title", "large": "Large title"][rawValue]! }
    var about: String { "How big the ticket title is." }
    var font: Font {
        switch self {
        case .headline: .headline
        case .title3: .title3.weight(.semibold)
        case .title2: .title2.weight(.semibold)
        case .title1: .title.weight(.semibold)
        case .large: .largeTitle.weight(.bold)
        }
    }
}

enum LabHeader: String, LabChoice {
    case tokens, minimal, statement, eyebrow, tile, breadcrumb, factsLine, none
    var title: String {
        ["tokens": "Title and tokens", "minimal": "Minimal (ⓘ)", "statement": "What is asked", "eyebrow": "Coloured eyebrow", "tile": "Type tile",
         "breadcrumb": "Breadcrumb", "factsLine": "Facts as a line", "none": "No header"][rawValue]!
    }
    var about: String {
        switch self {
        case .tokens: "Turn line, title, then the token row."
        case .minimal: "Turn line and title; the facts behind an ⓘ button."
        case .statement: "A sentence first (“Iris has a question”), the ticket smaller under it."
        case .eyebrow: "The kind in small capitals above the title (IRIS ASKS), no turn line."
        case .tile: "A large type symbol in a tile beside the number and title, like a file in Finder."
        case .breadcrumb: "Project › area › number above the title, like a path."
        case .factsLine: "Title, then the facts as one quiet line of text."
        case .none: "Straight to the question; the ticket only in the top bar."
        }
    }
}

enum LabTokens: String, LabChoice {
    case bordered, filled, plain, icons
    var title: String { ["bordered": "Bordered capsules", "filled": "Filled capsules", "plain": "Plain text", "icons": "Icons only"][rawValue]! }
    var about: String {
        switch self {
        case .bordered: "Small bordered pop-up capsules (today)."
        case .filled: "Grey capsules without a border."
        case .plain: "Text separated by dots; click a value to change it."
        case .icons: "One symbol per fact with the value in its tooltip."
        }
    }
}

enum LabTurn: String, LabChoice {
    case dot, pill, none
    var title: String { ["dot": "Dot and text", "pill": "Tinted pill", "none": "None"][rawValue]! }
    var about: String { "How “Your turn” is shown." }
}

enum LabAsk: String, LabChoice {
    case bubble, bigText, notice, plain, callout, outline
    var title: String { ["bubble": "Chat bubble", "bigText": "Big text", "notice": "Notification", "plain": "Plain sentence", "callout": "Callout", "outline": "Outlined bubble"][rawValue]! }
    var about: String {
        switch self {
        case .bubble: "A grey bubble, like Messages."
        case .bigText: "No box: the question as large text, the asker above it."
        case .notice: "A raised card like a macOS notification."
        case .plain: "Body text: “Iris asks: …”."
        case .callout: "A light grey box with the mark at its left."
        case .outline: "A bubble with a thin outline and no fill."
        }
    }
}

enum LabAvatar: String, LabChoice {
    case circle, mark, large, none
    var title: String { ["circle": "Mark in a circle", "mark": "Mark only", "large": "Large", "none": "None"][rawValue]! }
    var about: String { "Who asks, as a picture." }
}

enum LabByline: String, LabChoice {
    case nameTime, asks, none
    var title: String { ["nameTime": "Name · time", "asks": "“Iris asks”", "none": "None"][rawValue]! }
    var about: String { "The line above the question." }
}

enum LabLongAsk: String, LabChoice {
    case digest, clamp, full
    var title: String { ["digest": "The ask, then More", "clamp": "Three lines, then More", "full": "All of it"][rawValue]! }
    var about: String { "An agent's long message: cut to the question, cut to three lines, or shown whole." }
}

enum LabAnswers: String, LabChoice {
    case list, radio, cards, accordion, tiles, table, menu, buttons
    var title: String {
        ["list": "List", "radio": "Radio rows", "cards": "Cards", "accordion": "Accordion", "tiles": "Big tiles", "table": "Table", "menu": "Pop-up menu", "buttons": "Buttons"][rawValue]!
    }
    var about: String {
        switch self {
        case .list: "A list like System Settings; the selected row tinted."
        case .radio: "The setup pages' radio rows, no fill."
        case .cards: "Side-by-side cards to compare."
        case .accordion: "One line each; the selected answer opens to its full text."
        case .tiles: "One large tile per answer, full width."
        case .table: "Two columns: the short answer, then its explanation."
        case .menu: "One pop-up button; the selected answer's text under it."
        case .buttons: "One button per answer (the first build)."
        }
    }
}

enum LabRecommended: String, LabChoice {
    case starText, badge, irisPick, tintedTitle, none
    var title: String { ["starText": "★ Recommended", "badge": "Filled badge", "irisPick": "“Iris's pick”", "tintedTitle": "Accent title", "none": "Only sorted first"][rawValue]! }
    var about: String { "How the recommended answer stands out." }
}

enum LabIndicator: String, LabChoice {
    case check, radio, tint, ring
    var title: String { ["check": "Checkmark", "radio": "Radio dot", "tint": "Tint only", "ring": "Outline"][rawValue]! }
    var about: String { "How the selected answer is marked." }
}

enum LabLongAnswer: String, LabChoice {
    case twoLines, threeLines, firstLine, full
    var title: String { ["twoLines": "Two lines, then More", "threeLines": "Three lines, then More", "firstLine": "Bold line only", "full": "All of it"][rawValue]! }
    var about: String { "How much of a long answer shows. “Bold line only” puts the rest in a tooltip." }
}

enum LabKeys: String, LabChoice {
    case hidden, numbers
    var title: String { ["hidden": "Hidden", "numbers": "Numbers 1–4"][rawValue]! }
    var about: String { "Whether each answer shows the key that picks it." }
}

enum LabOwn: String, LabChoice {
    case row, field, link, none
    var title: String { ["row": "“Something else…” row", "field": "Always a field", "link": "“Write my own” link", "none": "None (use Note)"][rawValue]! }
    var about: String { "Where you write your own answer." }
}

enum LabMulti: String, LabChoice {
    case oneAtATime, tabs, stacked, conversation, collapsed
    var title: String { ["oneAtATime": "One at a time", "tabs": "Tabs", "stacked": "All on the card", "conversation": "Conversation", "collapsed": "Folded list"][rawValue]! }
    var about: String {
        switch self {
        case .oneAtATime: "The next question replaces the answered one; “question 1 of 2” in the header."
        case .tabs: "A segmented control, one tab per question; answer in any order."
        case .stacked: "All questions on the card, one Answer for all."
        case .conversation: "Answered questions stay as a short exchange (her question, your reply), the next one below."
        case .collapsed: "Each question one line with its chosen answer; the open one expands."
        }
    }
}

enum LabDesign: String, LabChoice {
    case gallery, hero, compare, carousel, stageCard, split
    var title: String { ["gallery": "Gallery", "hero": "Large and filmstrip", "compare": "Today beside the pick", "carousel": "One at a time", "stageCard": "Open in the Stage", "split": "Beside the text"][rawValue]! }
    var about: String {
        switch self {
        case .gallery: "All options side by side; click one to choose it."
        case .hero: "The selected option large, the others as thumbnails under it."
        case .compare: "Today on the left, the selected option on the right."
        case .carousel: "One large option with arrows and dots."
        case .stageCard: "Small thumbnails and a button to judge them in the Stage."
        case .split: "The selected option large, its description beside it."
        }
    }
}

enum LabThumb: String, LabChoice {
    case small, medium, large
    var title: String { ["small": "Small", "medium": "Medium", "large": "Large"][rawValue]! }
    var about: String { "How big the design pictures are." }
    var width: CGFloat { ["small": 150, "medium": 210, "large": 290][rawValue]! }
}

enum LabDesignChoice: String, LabChoice {
    case pictures, both, list
    var title: String { ["pictures": "By picture", "both": "Pictures and list", "list": "By list"][rawValue]! }
    var about: String { "Whether you choose a design by clicking its picture, from the answer list, or either." }
}

enum LabActions: String, LabChoice {
    case bar, inline, toolbar, floating, side, perAnswer
    var title: String { ["bar": "Bottom bar", "inline": "Under the answers", "toolbar": "Top bar", "floating": "Floating capsule", "side": "Right column", "perAnswer": "On the selected answer"][rawValue]! }
    var about: String {
        switch self {
        case .bar: "Pinned to the bottom of the panel."
        case .inline: "Right after the answers."
        case .toolbar: "Next to Done; no buttons on the page."
        case .floating: "A glass capsule floating at the bottom centre."
        case .side: "A column at the right of the card, at the top."
        case .perAnswer: "The main button sits on the selected answer; Later and Note in the bar."
        }
    }
}

enum LabMainButton: String, LabChoice {
    case glassProminent, borderedProminent, glass, wide, link
    var title: String { ["glassProminent": "Prominent glass", "borderedProminent": "Classic blue", "glass": "Quiet glass", "wide": "Full width", "link": "Text link"][rawValue]! }
    var about: String {
        switch self {
        case .glassProminent: "The “Set up a project” button."
        case .borderedProminent: "The classic macOS default button."
        case .glass: "Glass without the accent; the page has no blue button."
        case .wide: "A prominent button the width of the column."
        case .link: "Blue text with ↵, no button shape."
        }
    }
}

enum LabButtonSize: String, LabChoice {
    case small, regular, large, extraLarge
    var title: String { ["small": "Small", "regular": "Regular", "large": "Large", "extraLarge": "Extra large"][rawValue]! }
    var about: String { "The size of the action buttons." }
    var control: ControlSize { ["small": .small, "regular": .regular, "large": .large, "extraLarge": .extraLarge][rawValue]! }
}

enum LabSecondary: String, LabChoice {
    case glass, bordered, borderless, icons
    var title: String { ["glass": "Glass", "bordered": "Bordered", "borderless": "Text only", "icons": "Icons only"][rawValue]! }
    var about: String { "How Later and Note look." }
}

enum LabOrder: String, LabChoice {
    case mainRight, mainLeft
    var title: String { ["mainRight": "Main on the right", "mainLeft": "Main on the left"][rawValue]! }
    var about: String { "macOS puts the default button on the right; DESIGN.md has it first in a row." }
}

enum LabHint: String, LabChoice {
    case show, hide
    var title: String { ["show": "Shown", "hide": "Hidden"][rawValue]! }
    var about: String { "The grey line saying what the main button does." }
}

enum LabReturn: String, LabChoice {
    case none, glyph
    var title: String { ["none": "No ↵", "glyph": "↵ in the button"][rawValue]! }
    var about: String { "Whether the main button shows its key." }
}

enum LabProgress: String, LabChoice {
    case pills, count, bar, dots, ring, time, none
    var title: String { ["pills": "Pills", "count": "3 of 13", "bar": "Thin bar", "dots": "Dots", "ring": "Ring", "time": "Time left", "none": "None"][rawValue]! }
    var about: String { "How far you are through the queue." }
}

enum LabData: String, LabChoice {
    case queue, long, twoQuestions, design, gains, agent, plan, short
    var title: String {
        ["queue": "Your queue", "long": "Long answers", "twoQuestions": "Two questions", "design": "A design to choose", "gains": "Options with gains and costs",
         "agent": "An agent's long question", "plan": "A plan to approve", "short": "Two short answers"][rawValue]!
    }
    var about: String { "What the card shows: your real queue, or a hard case." }
}

/// Every choice, kept as one value so it survives relaunches; a choice added later starts at its default.
struct LabStyle: Codable, Equatable {
    var data = LabData.long
    var layout = LabLayout.focus, width = LabWidth.medium, position = LabPosition.top, surface = LabSurface.panel
    var density = LabDensity.regular, titleSize = LabTitleSize.title2
    var header = LabHeader.tokens, tokens = LabTokens.bordered, turn = LabTurn.dot
    var ask = LabAsk.bubble, avatar = LabAvatar.circle, byline = LabByline.nameTime, longAsk = LabLongAsk.digest
    var answers = LabAnswers.list, recommended = LabRecommended.starText, indicator = LabIndicator.check
    var longAnswer = LabLongAnswer.twoLines, keys = LabKeys.hidden, own = LabOwn.row
    var multi = LabMulti.oneAtATime
    var design = LabDesign.gallery, thumb = LabThumb.medium, designChoice = LabDesignChoice.pictures
    var actions = LabActions.bar, mainButton = LabMainButton.glassProminent, buttonSize = LabButtonSize.large
    var secondary = LabSecondary.glass, order = LabOrder.mainRight, hint = LabHint.show, returnKey = LabReturn.none
    var progress = LabProgress.pills

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<E: Decodable>(_ k: CodingKeys, _ d: E) -> E { ((try? c.decodeIfPresent(E.self, forKey: k)) ?? nil) ?? d }
        let d = LabStyle()
        data = v(.data, d.data); layout = v(.layout, d.layout); width = v(.width, d.width); position = v(.position, d.position)
        surface = v(.surface, d.surface); density = v(.density, d.density); titleSize = v(.titleSize, d.titleSize)
        header = v(.header, d.header); tokens = v(.tokens, d.tokens); turn = v(.turn, d.turn)
        ask = v(.ask, d.ask); avatar = v(.avatar, d.avatar); byline = v(.byline, d.byline); longAsk = v(.longAsk, d.longAsk)
        answers = v(.answers, d.answers); recommended = v(.recommended, d.recommended); indicator = v(.indicator, d.indicator)
        longAnswer = v(.longAnswer, d.longAnswer); keys = v(.keys, d.keys); own = v(.own, d.own); multi = v(.multi, d.multi)
        design = v(.design, d.design); thumb = v(.thumb, d.thumb); designChoice = v(.designChoice, d.designChoice)
        actions = v(.actions, d.actions); mainButton = v(.mainButton, d.mainButton); buttonSize = v(.buttonSize, d.buttonSize)
        secondary = v(.secondary, d.secondary); order = v(.order, d.order); hint = v(.hint, d.hint); returnKey = v(.returnKey, d.returnKey)
        progress = v(.progress, d.progress)
    }

    static let key = "lab.decide.style"

    static func load() -> LabStyle {
        guard let s = UserDefaults.standard.string(forKey: key), let data = s.data(using: .utf8),
              let style = try? JSONDecoder().decode(LabStyle.self, from: data) else { return LabStyle() }
        return style
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Self.key) }
    }

    func gap(_ base: CGFloat) -> CGFloat { (base * density.scale).rounded() }
}

// MARK: - What a card shows

struct LabOption: Identifiable, Hashable {
    let id: String
    var title: String
    var detail: String?
    var gain: String?
    var cost: String?
    var recommended = false

    /// A long answer split into a short bold line and the rest, at the first colon, dash or sentence end within 90
    /// characters; otherwise the whole text is the title.
    static func from(_ text: String, id: String, recommended: Bool) -> LabOption {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [": ", " — ", " - ", ". "] {
            if let r = t.range(of: sep), t.distance(from: t.startIndex, to: r.lowerBound) <= 90 {
                let head = String(t[..<r.lowerBound]) + (sep == ". " ? "." : "")
                let tail = String(t[r.upperBound...])
                if !tail.isEmpty { return LabOption(id: id, title: head, detail: tail.prefix(1).uppercased() + tail.dropFirst(), recommended: recommended) }
            }
        }
        return LabOption(id: id, title: t, recommended: recommended)
    }
}

enum LabAsker: Hashable {
    case iris, agent(String), hatch
    var name: String { switch self { case .iris: "Iris"; case .agent(let n): n; case .hatch: "Hatch" } }
}

struct LabQuestion: Identifiable {
    let id: String
    var asker: LabAsker = .iris
    var time = "just now"
    var lead: String?
    var ask: String
    var full: String?
    var options: [LabOption] = []
    var allowsOwn = false
}

/// A design option drawn as a small window with a toast; padding and corners differ per option.
struct LabSpecimen: Identifiable, Hashable {
    let id: String
    var name: String
    var note: String
    var padding: CGFloat
    var radius: CGFloat
    var isToday = false
    var recommended = false
}

struct LabCard: Identifiable {
    let id: String
    var kind: String
    var statement: String
    var number: String
    var type: TicketType
    var title: String
    var project = "Hatch"
    var area: String?
    var facts: [(label: String?, value: String)] = []
    var questions: [LabQuestion] = []
    var body: String?
    var files: [String] = []
    var specimens: [LabSpecimen] = []
    var main: String
    var hint: String
}

enum LabCards {
    static func facts(_ t: Ticket) -> [(label: String?, value: String)] {
        [(nil, t.path?.displayName ?? "No path"), ("Priority", TicketPriority.name(t.priority)), ("Area", t.area ?? "None"),
         ("Verify", (t.verify ?? t.path?.defaultVerify ?? .preview).displayName)]
    }

    static func from(store: HatchStore, projectId: Int?) -> [LabCard] {
        ((try? store.pendingDecisions(projectId: projectId)) ?? []).map { card(for: $0, store: store) }
    }

    static func card(for d: PendingDecision, store: HatchStore) -> LabCard {
        let t = d.ticket
        var c = LabCard(id: d.id, kind: "", statement: "", number: t.displayNumber, type: t.type, title: t.title, area: t.area, facts: facts(t), main: "Done", hint: "")
        switch d.kind {
        case .iris:
            let open = (try? store.questions(ticketId: t.id, openOnly: true)) ?? []
            c.kind = "Iris asks"; c.main = "Answer"; c.hint = "Answers go to Iris; the ticket goes on"
            c.questions = open.map { q in
                let digest = QuestionDigest(q.text)
                let asker: LabAsker = q.askedBy.caseInsensitiveCompare("Iris") == .orderedSame ? .iris : .agent(q.askedBy)
                var options = q.suggestions.enumerated().map { LabOption.from($1, id: "\($0)", recommended: $0 == 0) }
                if options.isEmpty, let rec = digest.recommendation {
                    options = [LabOption(id: "rec", title: rec, detail: "\(asker.name)'s own recommendation.", recommended: true)]
                }
                return LabQuestion(id: "q\(q.id)", asker: asker, time: Format.ago(q.at), lead: digest.lead, ask: digest.ask, full: digest.isLong ? q.text : nil,
                                   options: options, allowsOwn: !QuestionPurpose.isActedOn(q.purpose))
            }
            c.statement = "\(c.questions.first?.asker.name ?? "Iris") has \(c.questions.count > 1 ? "\(c.questions.count) questions" : "a question")"
        case .pick:
            let opts = (try? store.questionOptions(ticketId: t.id)) ?? []
            c.kind = "Pick one"; c.statement = opts.count == 2 ? "This or that" : "Pick one of \(opts.count)"
            c.questions = [LabQuestion(id: "pick", asker: t.status == .draft ? .hatch : .agent("Agent on \(t.displayNumber)"),
                                       ask: t.status == .draft ? "Hatch prepared these options." : "The agent offers these options.",
                                       options: opts.map { o in
                                           let detail = [o.detail, o.why].compactMap { $0 }.joined(separator: " ")
                                           return LabOption(id: o.key, title: o.title, detail: detail.isEmpty ? nil : detail, gain: o.gain, cost: o.cost, recommended: o.recommended)
                                       })]
            c.main = "Choose"; c.hint = "Records a decision"
        case .plan:
            c.kind = "Approve a plan"; c.statement = "The agent wants to go ahead"
            c.files = d.plan?.files ?? []
            c.questions = [LabQuestion(id: "plan", asker: .agent("Agent on \(t.displayNumber)"), ask: "These files would change. Approve, or send it back with a note.",
                                       options: [LabOption(id: "approve", title: "Approve the plan", detail: "The agent goes ahead with these files.", recommended: true),
                                                 LabOption(id: "back", title: "Send it back", detail: "Say what to change in a note.")])]
            c.main = "Approve"; c.hint = "Approving lets the agent go ahead"
        case .answer:
            c.kind = "An answer"; c.statement = "The agent answered"
            c.body = ((try? store.notes(ticketId: t.id)) ?? []).last { $0.kind == .agent }?.body ?? ""
            c.main = "Close as answered"; c.hint = "Closes the Question"
        case .submit:
            c.kind = "A draft"; c.statement = "Your draft is waiting"; c.body = t.body
            c.main = "Submit to Iris"; c.hint = "Iris checks it (a model call)"
        case .judge:
            c.kind = "Needs a sitting"; c.statement = "Options to judge"
            let info = ProposalInfo.load(store: store, ticket: t)
            let rec = info.recommendations.first?.choiceName
            c.specimens = (info.manifest?.specimens ?? []).enumerated().map { i, s in
                LabSpecimen(id: s.id, name: s.title, note: s.summary, padding: CGFloat(4 + i * 4), radius: CGFloat(4 + i * 4), isToday: s.isEchoToday,
                            recommended: s.title == rec)
            }
            c.questions = [LabQuestion(id: "judge", asker: .agent("Agent on \(t.displayNumber)"),
                                       ask: info.summary.isEmpty ? "Judge the options, or accept the recommendation." : info.summary,
                                       options: c.specimens.filter { !$0.isToday }.map { LabOption(id: $0.id, title: $0.name, detail: $0.note.isEmpty ? nil : $0.note, recommended: $0.recommended) })]
            c.main = "Accept"; c.hint = "Accepting starts the build"
        case .verify:
            c.kind = "Try it"; c.statement = "Built, ready to try"; c.body = "The work is built. Try it in a Preview before it merges."
            c.main = "Open Previews"; c.hint = "Opens Previews"
        }
        return c
    }

    static let longFacts: [(label: String?, value: String)] = [(nil, "Visual change"), ("Priority", "Normal"), ("Area", "None"), ("Verify", "In a Preview")]

    static let longQ1 = LabQuestion(id: "q1", asker: .iris, time: "28m ago", ask: "What about the “Iris asks” bubbles feels wrong to you?", options: [
        LabOption.from("Too heavy: the grey bubble and the boxed answers make every question look like an alert, while the rest of Decide is quiet text on white. It should read more like a line in a document than a chat.", id: "0", recommended: true),
        LabOption.from("Shape: rounded chat bubbles don't match the cards, tokens and pills used everywhere else in Hatch, so the page mixes two visual languages and neither feels intentional.", id: "1", recommended: false),
        LabOption.from("Colour or size: the grey is too dark in light mode, and the question text is larger than the title it belongs to, which flips the hierarchy of the card.", id: "2", recommended: false),
        LabOption.from("Position: the question should sit right under the title, before the facts, because it is the reason the card exists at all.", id: "3", recommended: false)],
        allowsOwn: true)

    static let longQ2 = LabQuestion(id: "q2", asker: .iris, time: "28m ago",
                                    ask: "Should the bubbles follow the existing components (accentSoft, Radius.card 10, detail font), or may they introduce a new style?",
                                    options: [LabOption(id: "0", title: "Stay within the existing components", recommended: true),
                                              LabOption(id: "1", title: "Add a variant just for the bubbles"),
                                              LabOption(id: "2", title: "Change the shared component everywhere")], allowsOwn: true)

    // Hard cases, so each look is judged on the worst content too.
    static func sample(_ data: LabData) -> [LabCard] {
        switch data {
        case .queue: return []
        case .long:
            return [LabCard(id: "s-long", kind: "Iris asks", statement: "Iris has a question", number: "#15", type: .proposal,
                            title: "Design recommendations for Decide, starting with the “Iris asks” bubbles", facts: longFacts, questions: [longQ1],
                            main: "Answer", hint: "Answers go to Iris; the ticket goes on")]
        case .twoQuestions:
            return [LabCard(id: "s-two", kind: "Iris asks", statement: "Iris has 2 questions", number: "#15", type: .proposal,
                            title: "Design recommendations for Decide, starting with the “Iris asks” bubbles", facts: longFacts, questions: [longQ1, longQ2],
                            main: "Answer", hint: "Answers go to Iris; the ticket goes on")]
        case .design:
            let specs = [LabSpecimen(id: "today", name: "Today", note: "What ships now: tight padding, square corners.", padding: 4, radius: 4, isToday: true),
                         LabSpecimen(id: "compact", name: "Compact", note: "More rows stay visible; the action is close to the text.", padding: 8, radius: 8),
                         LabSpecimen(id: "balanced", name: "Balanced", note: "Calmer spacing; the Undo action is easy to hit.", padding: 12, radius: 12, recommended: true),
                         LabSpecimen(id: "roomy", name: "Roomy", note: "Most air; the toast covers more of the window.", padding: 16, radius: 16)]
            return [LabCard(id: "s-design", kind: "Needs a sitting", statement: "Pick a toast", number: "#140", type: .proposal, title: "Toast spacing and corner radius",
                            area: "Notifications", facts: [(nil, "Change with approaches"), ("Priority", "Normal"), ("Area", "Notifications"), ("Verify", "In a Preview")],
                            questions: [LabQuestion(id: "d", asker: .agent("Agent on #140"), time: "12m ago", ask: "Which spacing feels easier to scan?",
                                                    options: specs.filter { !$0.isToday }.map { LabOption(id: $0.id, title: $0.name, detail: $0.note, recommended: $0.recommended) })],
                            specimens: specs, main: "Accept", hint: "Accepting starts the build")]
        case .gains:
            return [LabCard(id: "s-gains", kind: "Pick one", statement: "Pick one of 3", number: "#170", type: .question, title: "Two values for Color.accent", area: "Components",
                            facts: [(nil, "Quick question"), ("Priority", "Normal"), ("Area", "Components"), ("Verify", "None")],
                            questions: [LabQuestion(id: "g", asker: .hatch, ask: "Hatch found two values for one colour name and prepared these options.", options: [
                                LabOption(id: "A", title: "Keep AcmeComponents' values", detail: "The other values change to match. AcmeComponents is the set the project uses and Proposals import.", gain: "One value per name, matching the package", cost: "12 views change slightly", recommended: true),
                                LabOption(id: "B", title: "Keep the other set's values", detail: "AcmeComponents changes to match.", gain: "Views that use the folder do not change", cost: "40 views change slightly"),
                                LabOption(id: "C", title: "Keep both, rename the other set's", gain: "Nothing changes now", cost: "Two names that look alike")])],
                            main: "Choose", hint: "Records a decision")]
        case .agent:
            let text = "I can't prepare #5 yet. My only workspace is the notebook. It has no app checkout, so I can't read the real launch notice view that the first specimen has to be drawn from. It also has no manifest example, so I don't know the manifest format. Can you give me a workspace on this ticket's branch, or point me to the manifest schema? My recommendation: give me the app workspace. I'd then draw Today from the real notice code and propose three launch notices. A guess made without the real code would cost you a specimen that doesn't match."
            let d = QuestionDigest(text)
            return [LabCard(id: "s-agent", kind: "Agent asks", statement: "The agent on #5 is stuck", number: "#5", type: .proposal,
                            title: "Iris flags hardcoded design values at launch and offers a design-token ticket", facts: longFacts,
                            questions: [LabQuestion(id: "a", asker: .agent("Agent on #5"), time: "6m ago", lead: d.lead, ask: d.ask, full: text,
                                                    options: [LabOption(id: "rec", title: d.recommendation ?? "", detail: "The agent's own recommendation: it draws Today from the real code instead of guessing.", recommended: true)],
                                                    allowsOwn: true)],
                            main: "Answer", hint: "Answers go to the agent; it carries on")]
        case .plan:
            return [LabCard(id: "s-plan", kind: "Approve a plan", statement: "The agent wants to go ahead", number: "#144", type: .bug, title: "Connection test hangs on bad host", area: "Connections",
                            facts: [(nil, "Fix"), ("Priority", "High"), ("Area", "Connections"), ("Verify", "Tests")],
                            questions: [LabQuestion(id: "p", asker: .agent("Agent on #144"), ask: "These files would change. Approve, or send it back with a note.", options: [
                                LabOption(id: "approve", title: "Approve the plan", detail: "1 of 3 files is outside Connections, the ticket's area (Editor/Toolbar.swift). Worth a look, not a blocker.", recommended: true),
                                LabOption(id: "back", title: "Send it back", detail: "Say what to change in a note.")])],
                            files: ["Sources/Connections/ConnectionTest.swift", "Sources/Connections/HostCheck.swift", "Sources/Editor/Toolbar.swift"],
                            main: "Approve", hint: "Approving lets the agent go ahead")]
        case .short:
            return [LabCard(id: "s-short", kind: "Iris asks", statement: "Iris has a question", number: "#146", type: .question, title: "Should tabs restore after a crash?", area: "Editor",
                            facts: [(nil, "Quick question"), ("Priority", "Normal"), ("Area", "Editor"), ("Verify", "None")],
                            questions: [LabQuestion(id: "s", asker: .iris, ask: "Should restored tabs keep their previous split position?",
                                                    options: [LabOption(id: "0", title: "Yes, when both tabs still exist", recommended: true), LabOption(id: "1", title: "No, use the default split")],
                                                    allowsOwn: true)],
                            main: "Answer", hint: "Answers go to Iris; the ticket goes on")]
        }
    }
}

// MARK: - The window

/// What the preview needs besides the style: which card and question, and what is selected.
@MainActor
final class LabModel: ObservableObject {
    @Published var style = LabStyle.load() { didSet { style.save() } }
    @Published var queue: [LabCard] = []
    @Published var index = 0
    @Published var question: [String: Int] = [:]
    @Published var selected: [String: String] = [:]
    @Published var own = ""

    var cards: [LabCard] { style.data == .queue ? queue : LabCards.sample(style.data) }
    var card: LabCard? { cards.isEmpty ? nil : cards[min(index, cards.count - 1)] }

    func questionIndex(_ c: LabCard) -> Int { min(question[c.id] ?? 0, max(c.questions.count - 1, 0)) }

    func selection(_ q: LabQuestion) -> String {
        selected[q.id] ?? q.options.first(where: \.recommended)?.id ?? q.options.first?.id ?? ""
    }

    func binding(_ q: LabQuestion) -> Binding<String> {
        Binding(get: { self.selection(q) }, set: { self.selected[q.id] = $0 })
    }

    /// The main button: the next question, or round again to the first.
    func main() {
        guard let c = card, c.questions.count > 1 else { return }
        question[c.id] = (questionIndex(c) + 1) % c.questions.count
    }

    func move(_ by: Int) {
        guard let c = card, !c.questions.isEmpty else { return }
        let q = c.questions[questionIndex(c)]
        var ids = q.options.map(\.id)
        if q.allowsOwn && style.own == .row { ids.append("own") }
        guard !ids.isEmpty else { return }
        let at = ids.firstIndex(of: selection(q)) ?? 0
        selected[q.id] = ids[(at + by + ids.count) % ids.count]
    }
}

struct DecideLabView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = LabModel()
    @State private var copied = false

    var body: some View {
        LabPreview(model: model)
            .frame(minWidth: 760, minHeight: 600)
            .inspector(isPresented: .constant(true)) { controls.inspectorColumnWidth(min: 340, ideal: 380, max: 480) }
            .onAppear { model.queue = LabCards.from(store: state.store, projectId: state.projectFilterId) }
            .onChange(of: model.style.data) { model.index = 0 }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { model.move(-1); return .handled }
            .onKeyPress(.downArrow) { model.move(1); return .handled }
            .onKeyPress(.leftArrow) { model.index = max(0, model.index - 1); return .handled }
            .onKeyPress(.rightArrow) { model.index = min(max(0, model.cards.count - 1), model.index + 1); return .handled }
            .navigationTitle("Decide Lab")
    }

    // MARK: Controls

    private var controls: some View {
        Form {
            Section {
                row("Content", \.data, queueCount: model.queue.count)
                if model.cards.count > 1 {
                    HStack {
                        Button { model.index = max(0, model.index - 1) } label: { Image(systemName: "chevron.left") }.disabled(model.index == 0)
                        Text("Card \(model.index + 1) of \(model.cards.count)").monospacedDigit().frame(maxWidth: .infinity)
                        Button { model.index = min(model.cards.count - 1, model.index + 1) } label: { Image(systemName: "chevron.right") }.disabled(model.index >= model.cards.count - 1)
                    }
                }
            } footer: { Text("Nothing here decides anything. ← → change card, ↑ ↓ change the answer; ‹ › beside a choice steps through its options.") }
            Section("Page") {
                row("Layout", \.layout); row("Column", \.width); row("Position", \.position); row("Surface", \.surface)
                row("Spacing", \.density); row("Title size", \.titleSize)
            }
            Section("Header") { row("Header", \.header); row("Facts", \.tokens); row("Your turn", \.turn) }
            Section("The question") { row("Style", \.ask); row("Picture", \.avatar); row("Line above", \.byline); row("Long message", \.longAsk) }
            Section("Answers") {
                row("Style", \.answers); row("Recommended", \.recommended); row("Selected", \.indicator); row("Long answers", \.longAnswer)
                row("Keys", \.keys); row("Your own", \.own)
            }
            Section("Two or more questions") { row("Show", \.multi) }
            Section("When a design is shown") { row("Show", \.design); row("Pictures", \.thumb); row("Choose", \.designChoice) }
            Section("Actions") {
                row("Where", \.actions); row("Main button", \.mainButton); row("Size", \.buttonSize); row("Later and Note", \.secondary)
                row("Order", \.order); row("Hint", \.hint); row("Key", \.returnKey)
            }
            Section("Progress") { row("Show", \.progress) }
            Section("Your combination") {
                Text(summary).font(.callout).textSelection(.enabled)
                HStack {
                    Button(copied ? "Copied" : "Copy for Claude") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("Decide Lab choice: " + summary, forType: .string)
                        copied = true
                    }
                    Button("Reset") { let data = model.style.data; model.style = LabStyle(); model.style.data = data }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.style) { copied = false }
    }

    private func row<E: LabChoice>(_ title: String, _ kp: WritableKeyPath<LabStyle, E>, queueCount: Int? = nil) -> some View {
        let value = Binding<E>(get: { model.style[keyPath: kp] }, set: { model.style[keyPath: kp] = $0 })
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                Spacer(minLength: 8)
                Button { step(kp, -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).help("Previous option")
                Picker(title, selection: value) {
                    ForEach(E.allCases) { e in
                        Text(queueCount != nil && e.rawValue == "queue" ? "Your queue (\(queueCount ?? 0))" : e.title).tag(e)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Button { step(kp, 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).help("Next option")
            }
            Text(value.wrappedValue.about).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step<E: LabChoice>(_ kp: WritableKeyPath<LabStyle, E>, _ by: Int) {
        let all = Array(E.allCases)
        guard let at = all.firstIndex(of: model.style[keyPath: kp]) else { return }
        model.style[keyPath: kp] = all[(at + by + all.count) % all.count]
    }

    private var summary: String {
        let s = model.style
        let parts: [(String, String)] = [
            ("Layout", s.layout.title), ("Column", s.width.title), ("Position", s.position.title), ("Surface", s.surface.title), ("Spacing", s.density.title),
            ("Title", s.titleSize.title), ("Header", s.header.title), ("Facts", s.tokens.title), ("Turn", s.turn.title), ("Question", s.ask.title),
            ("Picture", s.avatar.title), ("Line above", s.byline.title), ("Long message", s.longAsk.title), ("Answers", s.answers.title),
            ("Recommended", s.recommended.title), ("Selected", s.indicator.title), ("Long answers", s.longAnswer.title), ("Keys", s.keys.title),
            ("Own answer", s.own.title), ("Two questions", s.multi.title), ("Design", s.design.title), ("Pictures", s.thumb.title),
            ("Choose design", s.designChoice.title), ("Actions", s.actions.title), ("Main button", s.mainButton.title), ("Button size", s.buttonSize.title),
            ("Later and Note", s.secondary.title), ("Order", s.order.title), ("Hint", s.hint.title), ("Key", s.returnKey.title), ("Progress", s.progress.title)]
        return parts.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }
}

// MARK: - Preview

private struct LabPreview: View {
    @ObservedObject var model: LabModel
    private var s: LabStyle { model.style }

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
            if let card = model.card {
                switch s.layout {
                case .focus: focus(card)
                case .inbox: inbox(card)
                case .spotlight: spotlight(card)
                case .stack: stack(card)
                case .split: split(card)
                case .sheet: sheet(card)
                }
            } else {
                ContentUnavailableView("Nothing waits for you", systemImage: "checkmark.circle", description: Text("Pick one of the hard cases under Content."))
            }
        }
    }

    private func content(_ card: LabCard, splitDesign: Bool = false) -> some View {
        LabCardBody(card: card, model: model, splitDesign: splitDesign)
    }

    // MARK: Layouts

    @ViewBuilder private func surface<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        switch s.surface {
        case .panel:
            inner().background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.3)))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .padding(8)
        case .window:
            inner().padding(8)
        case .material:
            inner().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.3)))
                .padding(8)
        case .card:
            inner().background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.3)))
                .padding(8)
        }
    }

    /// The card's column, scrolled, placed per Position, and on a white card when the surface asks for one.
    private func column(_ card: LabCard, top: CGFloat = 36) -> some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    if s.position == .third { Spacer().frame(height: geo.size.height * 0.14) }
                    cardSurface(content(card).frame(maxWidth: s.width.points, alignment: .leading))
                        .padding(.horizontal, s.width == .full ? 48 : 32)
                        .padding(.top, s.position == .top ? s.gap(top) : 0)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: s.position == .centre ? geo.size.height : 0, alignment: .center)
            }
        }
    }

    @ViewBuilder private func cardSurface<C: View>(_ inner: C) -> some View {
        if s.surface == .card {
            inner.padding(24)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        } else {
            inner
        }
    }

    private var hasBottomBar: Bool { s.actions == .bar || s.actions == .perAnswer }

    private func focus(_ card: LabCard) -> some View {
        surface {
            VStack(spacing: 0) {
                LabTopBar(card: card, model: model)
                column(card)
                if hasBottomBar { LabBottomBar(card: card, model: model) }
            }
            .overlay(alignment: .bottom) { if s.actions == .floating { LabFloatingBar(card: card, model: model).padding(.bottom, 18) } }
        }
    }

    private func inbox(_ card: LabCard) -> some View {
        surface {
            HStack(spacing: 0) {
                List(selection: Binding(get: { model.index }, set: { if let v = $0 { model.index = v } })) {
                    Section("Waiting for you · \(model.cards.count)") {
                        ForEach(Array(model.cards.enumerated()), id: \.offset) { i, c in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(c.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Text(c.kind).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(c.title).lineLimit(2)
                            }
                            .padding(.vertical, 3).tag(i)
                        }
                    }
                }
                .listStyle(.sidebar).frame(width: 280)
                Divider()
                VStack(spacing: 0) {
                    LabTopBar(card: card, model: model, compact: true)
                    column(card, top: 12)
                    if hasBottomBar { LabBottomBar(card: card, model: model) }
                }
                .overlay(alignment: .bottom) { if s.actions == .floating { LabFloatingBar(card: card, model: model).padding(.bottom, 18) } }
            }
        }
    }

    private func dimmedApp() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<9, id: \.self) { i in RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: CGFloat(240 + (i * 53) % 260), height: 14) }
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .overlay(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(8)
    }

    private func spotlight(_ card: LabCard) -> some View {
        ZStack {
            dimmedApp()
            VStack(spacing: 0) {
                LabTopBar(card: card, model: model, compact: true)
                ScrollView { content(card).padding(.horizontal, 24).padding(.vertical, s.gap(14)) }.scrollBounceBehavior(.basedOnSize)
                if s.actions != .toolbar && s.actions != .inline && s.actions != .side { LabBottomBar(card: card, model: model) }
            }
            .frame(width: 680).frame(maxHeight: 680).fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        }
    }

    private func sheet(_ card: LabCard) -> some View {
        ZStack(alignment: .top) {
            dimmedApp()
            VStack(spacing: 0) {
                ScrollView { content(card).padding(24) }.scrollBounceBehavior(.basedOnSize)
                LabBottomBar(card: card, model: model)
            }
            .frame(width: 720).frame(maxHeight: 620).fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor), in: UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .padding(.top, 8)
        }
    }

    private func stack(_ card: LabCard) -> some View {
        VStack(spacing: 0) {
            LabTopBar(card: card, model: model)
            ZStack(alignment: .top) {
                ForEach([2, 1], id: \.self) { depth in
                    if model.index + depth < model.cards.count {
                        RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator.opacity(0.4)))
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                            .frame(maxWidth: 760 - CGFloat(depth) * 40, maxHeight: 400).offset(y: CGFloat(depth) * 12)
                    }
                }
                VStack(spacing: 0) {
                    ScrollView { content(card).padding(28) }.scrollBounceBehavior(.basedOnSize)
                    if hasBottomBar { LabBottomBar(card: card, model: model) }
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator.opacity(0.4)))
                .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
                .frame(maxWidth: 760).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32).padding(.top, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) { if s.actions == .floating { LabFloatingBar(card: card, model: model).padding(.bottom, 24) } }
        }
    }

    private func split(_ card: LabCard) -> some View {
        surface {
            VStack(spacing: 0) {
                LabTopBar(card: card, model: model)
                HStack(spacing: 0) {
                    ScrollView { content(card, splitDesign: true).padding(.horizontal, 28).padding(.vertical, s.gap(24)) }
                        .frame(width: 460)
                    Divider()
                    LabContextPane(card: card, model: model)
                }
                if hasBottomBar { LabBottomBar(card: card, model: model) }
            }
            .overlay(alignment: .bottom) { if s.actions == .floating { LabFloatingBar(card: card, model: model).padding(.bottom, 18) } }
        }
    }
}

/// The right half of Split: the selected design large, or the ticket's facts and files.
private struct LabContextPane: View {
    let card: LabCard
    @ObservedObject var model: LabModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let first = card.specimens.first {
                    let sel = card.questions.first.map { model.selection($0) } ?? ""
                    let spec = card.specimens.first { $0.id == sel } ?? first
                    Text(spec.name).font(.title3.weight(.semibold))
                    LabSpecimenView(spec: spec, width: 560)
                    if let today = card.specimens.first(where: \.isToday), today.id != spec.id {
                        Text("Today").font(.headline).foregroundStyle(.secondary)
                        LabSpecimenView(spec: today, width: 360)
                    }
                } else {
                    Text("About \(card.number)").font(.headline)
                    Form {
                        LabeledContent("Type", value: card.type.displayName)
                        ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in LabeledContent(f.label ?? "Path", value: f.value) }
                    }
                    .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true).padding(-20)
                    if !card.files.isEmpty {
                        Text("Files").font(.headline)
                        ForEach(card.files, id: \.self) { Text($0).font(.callout.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
    }
}

// MARK: - Bars and buttons

private struct LabTopBar: View {
    let card: LabCard
    @ObservedObject var model: LabModel
    var compact = false
    private var s: LabStyle { model.style }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if !compact { Label("Decide", systemImage: "checklist").font(.headline) }
                if s.header == .none { Text("\(card.number) \(card.title)").font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                if s.progress != .bar { LabProgressView(model: model) }
                Spacer()
                if s.progress != .count && s.progress != .time && s.progress != .ring {
                    Text("\(model.cards.count - model.index) left").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                if s.actions == .toolbar { LabActionButtons(card: card, model: model, includeNote: false) }
                Button {} label: { Image(systemName: "questionmark") }.buttonStyle(.glass).buttonBorderShape(.capsule)
                Button("Done") {}.buttonStyle(.glass).buttonBorderShape(.capsule)
            }
            .padding(.horizontal, 20).frame(height: 52)
            if s.progress == .bar {
                ProgressView(value: Double(model.index + 1), total: Double(max(model.cards.count, 1))).progressViewStyle(.linear).controlSize(.mini).padding(.horizontal, 20)
            }
        }
    }
}

private struct LabProgressView: View {
    @ObservedObject var model: LabModel

    var body: some View {
        let n = max(model.cards.count, 1), i = model.index
        switch model.style.progress {
        case .pills:
            HStack(spacing: 4) {
                ForEach(0..<min(n, 16), id: \.self) { k in
                    Capsule().fill(k == i ? Theme.you : (k < i ? Color.secondary : Color.secondary.opacity(0.25))).frame(width: k == i ? 26 : 18, height: 5)
                }
            }
        case .count:
            Text("\(i + 1) of \(n)").font(.callout.weight(.medium)).monospacedDigit()
        case .dots:
            HStack(spacing: 5) {
                ForEach(0..<min(n, 20), id: \.self) { k in Circle().fill(k == i ? Theme.you : Color.secondary.opacity(k < i ? 0.7 : 0.25)).frame(width: 6, height: 6) }
            }
        case .ring:
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(i + 1) / CGFloat(n)).stroke(Theme.you, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                Text("\(i + 1) of \(n)").font(.callout).monospacedDigit()
            }
        case .time:
            Text("about \(max(1, n - i)) min left").font(.callout).foregroundStyle(.secondary)
        case .bar, .none:
            EmptyView()
        }
    }
}

/// The main button and Later (and Note), styled per the Lab's choices.
private struct LabActionButtons: View {
    let card: LabCard
    @ObservedObject var model: LabModel
    var includeNote = true
    var showHint = false
    private var s: LabStyle { model.style }

    private var mainTitle: String {
        if card.questions.count > 1 {
            if s.multi == .stacked || s.multi == .tabs || s.multi == .collapsed { return "Answer all" }
            if model.questionIndex(card) < card.questions.count - 1 { return "Answer, next question" }
        }
        return card.main
    }

    var body: some View {
        HStack(spacing: 8) {
            if s.order == .mainLeft { main }
            secondary("Later", "clock")
            if includeNote { secondary("Note", "square.and.pencil") }
            Spacer(minLength: 8)
            if showHint && s.hint == .show { Text(card.hint).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if s.order == .mainRight { main }
        }
        .buttonBorderShape(.capsule)
        .controlSize(s.buttonSize.control)
    }

    private var label: Text {
        s.returnKey == .glyph ? Text("\(mainTitle)  \(Text("↵").foregroundStyle(.secondary))") : Text(mainTitle)
    }

    @ViewBuilder private var main: some View {
        switch s.mainButton {
        case .glassProminent: Button { model.main() } label: { label }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
        case .borderedProminent: Button { model.main() } label: { label }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        case .glass: Button { model.main() } label: { label }.buttonStyle(.glass).keyboardShortcut(.defaultAction)
        case .wide: Button { model.main() } label: { label.frame(minWidth: 180) }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
        case .link: Button { model.main() } label: { Text(mainTitle + "  ↵") }.buttonStyle(.link).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private func secondary(_ title: String, _ symbol: String) -> some View {
        switch s.secondary {
        case .glass: Button {} label: { Text(title) }.buttonStyle(.glass)
        case .bordered: Button {} label: { Text(title) }.buttonStyle(.bordered)
        case .borderless: Button {} label: { Text(title) }.buttonStyle(.borderless)
        case .icons: Button {} label: { Image(systemName: symbol) }.buttonStyle(.glass).help(title)
        }
    }
}

private struct LabBottomBar: View {
    let card: LabCard
    @ObservedObject var model: LabModel
    private var s: LabStyle { model.style }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if s.actions == .perAnswer {
                    HStack(spacing: 8) { Button("Later") {}.buttonStyle(.glass); Button("Note") {}.buttonStyle(.glass); Spacer() }
                        .buttonBorderShape(.capsule).controlSize(s.buttonSize.control)
                } else if s.mainButton == .wide {
                    VStack(spacing: 8) {
                        Button { model.main() } label: { Text(card.main).frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(s.buttonSize.control).keyboardShortcut(.defaultAction)
                        HStack { Button("Later") {}.buttonStyle(.borderless); Spacer(); Button("Note") {}.buttonStyle(.borderless) }.font(.callout)
                    }
                    .padding(.vertical, 10)
                } else {
                    LabActionButtons(card: card, model: model, showHint: true)
                }
            }
            .padding(.horizontal, 24).frame(maxWidth: min(s.width.points, 900) + 48).frame(minHeight: 64).frame(maxWidth: .infinity)
        }
    }
}

private struct LabFloatingBar: View {
    let card: LabCard
    @ObservedObject var model: LabModel

    var body: some View {
        LabActionButtons(card: card, model: model).fixedSize()
            .padding(6).glassEffect(.regular, in: .capsule)
    }
}

// MARK: - The card itself

private struct LabCardBody: View {
    let card: LabCard
    @ObservedObject var model: LabModel
    var splitDesign = false
    @State private var showFacts = false
    private var s: LabStyle { model.style }

    var body: some View {
        HStack(alignment: .top, spacing: s.gap(24)) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let body = card.body, !body.isEmpty {
                    Text(body).textSelection(.enabled).lineLimit(14)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, s.gap(18))
                }
                if !card.files.isEmpty {
                    VStack(alignment: .leading, spacing: 3) { ForEach(card.files, id: \.self) { Text($0).font(.callout.monospaced()).foregroundStyle(.secondary) } }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, s.gap(16))
                }
                questions.padding(.top, s.header == .none ? 0 : s.gap(26))
                if s.actions == .inline { LabActionButtons(card: card, model: model, showHint: true).padding(.top, s.gap(22)) }
            }
            if s.actions == .side {
                VStack(alignment: .trailing, spacing: 8) {
                    Button(card.main) { model.main() }.buttonStyle(.glassProminent)
                    Button("Later") {}.buttonStyle(.glass)
                    Button("Note") {}.buttonStyle(.glass)
                }
                .buttonBorderShape(.capsule).controlSize(s.buttonSize.control).fixedSize()
            }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        switch s.header {
        case .tokens:
            VStack(alignment: .leading, spacing: s.gap(8)) { turnLine; title; facts }
        case .minimal:
            VStack(alignment: .leading, spacing: s.gap(6)) { turnLine; HStack(alignment: .firstTextBaseline, spacing: 10) { title; factsButton } }
        case .statement:
            VStack(alignment: .leading, spacing: s.gap(6)) {
                HStack(spacing: 8) {
                    if s.turn != .none { Circle().fill(Theme.you).frame(width: 8, height: 8) }
                    Text(card.statement).font(.largeTitle.weight(.bold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.number).font(.callout.monospaced()).foregroundStyle(.secondary)
                    Text(card.title).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    factsButton
                }
            }
        case .eyebrow:
            VStack(alignment: .leading, spacing: s.gap(6)) {
                Text(card.kind.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.you)
                title
                facts
            }
        case .tile:
            VStack(alignment: .leading, spacing: s.gap(10)) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: Theme.symbol(for: card.type)).font(.system(size: 20, weight: .medium))
                        .frame(width: 46, height: 46).background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) { turnBadge; Text("\(card.number) · \(card.type.displayName) · \(card.kind)").font(.caption).foregroundStyle(.secondary) }
                        title
                    }
                }
                facts
            }
        case .breadcrumb:
            VStack(alignment: .leading, spacing: s.gap(6)) {
                HStack(spacing: 5) {
                    turnBadge
                    Text([card.project, card.area, card.number].compactMap { $0 }.joined(separator: "  ›  ")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    openLink
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) { title; factsButton }
            }
        case .factsLine:
            VStack(alignment: .leading, spacing: s.gap(6)) {
                turnLine
                title
                Text(([card.type.displayName] + card.facts.map { f in f.label.map { "\($0) \(f.value.lowercased())" } ?? f.value }).joined(separator: "  ·  "))
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .none:
            EmptyView()
        }
    }

    private var title: some View {
        Text(card.title).font(s.titleSize.font).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var turnBadge: some View {
        switch s.turn {
        case .dot: Label("Your turn", systemImage: "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.you).imageScale(.small)
        case .pill: Text("Your turn").font(.caption.weight(.semibold)).foregroundStyle(Theme.you).padding(.horizontal, 8).padding(.vertical, 2).background(Theme.youBackground, in: Capsule())
        case .none: EmptyView()
        }
    }

    private var turnLine: some View {
        HStack(spacing: 6) {
            turnBadge
            if s.turn != .none { Text("·").foregroundStyle(.secondary) }
            Text(card.number).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text([card.type.displayName, card.kind, positionText].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            Spacer()
            openLink
        }
    }

    private var positionText: String? {
        guard card.questions.count > 1, s.multi == .oneAtATime else { return nil }
        return "question \(model.questionIndex(card) + 1) of \(card.questions.count)"
    }

    private var openLink: some View {
        Button {} label: { Label("Open ticket", systemImage: "arrow.up.right").labelStyle(TrailingIconLabelStyle()) }.buttonStyle(.link).font(.caption)
    }

    private func factIcon(_ label: String?) -> String {
        switch label { case "Priority": "flag"; case "Area": "square.grid.2x2"; case "Verify": "checkmark.seal"; default: "arrow.triangle.branch" }
    }

    private func tokenLabel(_ f: (label: String?, value: String)) -> some View {
        HStack(spacing: 4) { if let l = f.label { Text(l).foregroundStyle(.secondary) }; Text(f.value) }
    }

    @ViewBuilder private var facts: some View {
        switch s.tokens {
        case .bordered:
            FlowLayout(spacing: 6) {
                typeToken
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in
                    Menu { Button(f.value) {} } label: { tokenLabel(f) }
                        .menuStyle(.button).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).font(.caption.weight(.medium)).fixedSize()
                }
            }
        case .filled:
            FlowLayout(spacing: 6) {
                typeToken
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in
                    Menu { Button(f.value) {} } label: { tokenLabel(f) }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).font(.caption.weight(.medium))
                        .padding(.horizontal, 9).frame(height: 22).background(.quaternary.opacity(0.6), in: Capsule()).fixedSize()
                }
            }
        case .plain:
            HStack(spacing: 6) {
                Text(card.type.displayName).foregroundStyle(.secondary)
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in
                    Text("·").foregroundStyle(.tertiary)
                    Menu { Button(f.value) {} } label: { Text(f.label.map { "\($0) \(f.value.lowercased())" } ?? f.value) }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).foregroundStyle(.secondary).fixedSize()
                }
            }
            .font(.callout)
        case .icons:
            HStack(spacing: 12) {
                Image(systemName: Theme.symbol(for: card.type)).help(card.type.displayName)
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in
                    Image(systemName: factIcon(f.label)).help("\(f.label ?? "Path"): \(f.value)")
                }
            }
            .foregroundStyle(.secondary).font(.callout)
        }
    }

    private var typeToken: some View {
        Label(card.type.displayName, systemImage: Theme.symbol(for: card.type))
            .font(.caption.weight(.medium)).padding(.horizontal, 9).frame(height: 22).background(.quaternary, in: Capsule())
    }

    private var factsButton: some View {
        Button { showFacts.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless).foregroundStyle(.secondary).help("What Iris set")
            .popover(isPresented: $showFacts, arrowEdge: .bottom) {
                Form {
                    LabeledContent("Type", value: card.type.displayName)
                    ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in LabeledContent(f.label ?? "Path", value: f.value) }
                }
                .formStyle(.grouped).frame(width: 300).fixedSize(horizontal: false, vertical: true)
            }
    }

    // MARK: Questions

    @ViewBuilder private var questions: some View {
        let qs = card.questions
        if qs.count <= 1 {
            if let q = qs.first { LabQuestionView(card: card, question: q, model: model, splitDesign: splitDesign) }
        } else {
            let current = model.questionIndex(card)
            switch s.multi {
            case .oneAtATime:
                LabQuestionView(card: card, question: qs[current], model: model, splitDesign: splitDesign).id(qs[current].id)
            case .tabs:
                VStack(alignment: .leading, spacing: s.gap(16)) {
                    Picker("Question", selection: Binding(get: { current }, set: { model.question[card.id] = $0 })) {
                        ForEach(Array(qs.enumerated()), id: \.offset) { i, _ in Text("Question \(i + 1)").tag(i) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    LabQuestionView(card: card, question: qs[current], model: model, splitDesign: splitDesign).id(qs[current].id)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: s.gap(30)) {
                    ForEach(qs) { q in LabQuestionView(card: card, question: q, model: model, splitDesign: splitDesign) }
                }
            case .conversation:
                VStack(alignment: .leading, spacing: s.gap(14)) {
                    ForEach(Array(qs.prefix(current).enumerated()), id: \.offset) { _, q in answeredExchange(q) }
                    LabQuestionView(card: card, question: qs[current], model: model, splitDesign: splitDesign).id(qs[current].id)
                }
            case .collapsed:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(qs.enumerated()), id: \.offset) { i, q in
                        if i > 0 { Divider().padding(.vertical, s.gap(10)) }
                        if i == current {
                            LabQuestionView(card: card, question: q, model: model, splitDesign: splitDesign)
                        } else {
                            Button { model.question[card.id] = i } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(i + 1)").font(.callout.monospaced()).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(q.ask).lineLimit(1)
                                        Text(chosenTitle(q)).font(.callout).foregroundStyle(Color.accentColor).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down").foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func chosenTitle(_ q: LabQuestion) -> String {
        let sel = model.selection(q)
        return sel == "own" ? "Your own answer" : (q.options.first { $0.id == sel }?.title ?? "")
    }

    /// An answered question in Conversation: her question, then your reply on the right, both small.
    private func answeredExchange(_ q: LabQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(q.ask).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(HX.bubble.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Spacer(minLength: 60)
                Text(chosenTitle(q)).font(.callout).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

/// One question: who asks, the ask, the design when there is one, then the answers.
private struct LabQuestionView: View {
    let card: LabCard
    let question: LabQuestion
    @ObservedObject var model: LabModel
    var splitDesign = false
    @State private var showFull = false
    @State private var expanded: Set<String> = []
    @State private var linkOpen = false
    private var s: LabStyle { model.style }
    private var selection: Binding<String> { model.binding(question) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ask
            if !card.specimens.isEmpty && !splitDesign {
                LabDesignView(card: card, question: question, model: model).padding(.top, s.gap(16)).padding(.leading, indent)
            }
            if showAnswerList {
                answers.padding(.top, s.gap(14)).padding(.leading, indent)
            }
            if question.allowsOwn && (s.own == .field || s.own == .link) { ownExtra.padding(.top, s.gap(10)).padding(.leading, indent) }
        }
    }

    private var showAnswerList: Bool {
        if card.specimens.isEmpty || splitDesign { return !question.options.isEmpty || (question.allowsOwn && s.own == .row) }
        return s.designChoice != .pictures
    }

    private var indent: CGFloat {
        guard s.ask == .bubble || s.ask == .outline else { return 0 }
        switch s.avatar { case .circle: return 38; case .large: return 46; case .mark: return 28; case .none: return 0 }
    }

    // MARK: The ask

    @ViewBuilder private var ask: some View {
        switch s.ask {
        case .bubble, .outline:
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    byline.padding(.leading, 4)
                    askText(font: .body)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(s.ask == .bubble ? HX.bubble : Color.clear, in: RoundedRectangle(cornerRadius: HX.bubbleRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: HX.bubbleRadius, style: .continuous)
                            .strokeBorder(s.ask == .outline ? Color(nsColor: .separatorColor) : Color.clear))
                }
            }
        case .bigText:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { if s.avatar != .none { glyph.frame(width: 14, height: 14) }; byline }
                askText(font: .title3.weight(.semibold))
            }
        case .notice:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { avatar; byline; Spacer() }
                askText(font: .body)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        case .plain:
            HStack(alignment: .top, spacing: 8) {
                if s.avatar != .none { glyph.frame(width: 15, height: 15).padding(.top, 2) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.asker.name + (s.byline == .none ? ":" : " asks:")).fontWeight(.semibold)
                    askText(font: .body)
                }
            }
        case .callout:
            HStack(alignment: .top, spacing: 12) {
                if s.avatar != .none { glyph.frame(width: 18, height: 18).padding(.top, 2) }
                VStack(alignment: .leading, spacing: 4) { byline; askText(font: .body) }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func askText(font: Font) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            switch s.longAsk {
            case .digest:
                if let lead = question.lead { Text(lead).foregroundStyle(.secondary) }
                Text(question.ask).font(font).fontWeight(question.lead != nil && s.ask != .bigText ? .semibold : nil)
                if let full = question.full { fullToggle(full) }
            case .clamp:
                Text(question.full ?? question.ask).font(font).lineLimit(showFull ? nil : 3)
                if question.full != nil {
                    Button(showFull ? "Less" : "More") { withAnimation(.snappy(duration: 0.2)) { showFull.toggle() } }.buttonStyle(.link).font(.caption)
                }
            case .full:
                Text(question.full ?? question.ask).font(font)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func fullToggle(_ full: String) -> some View {
        if showFull { Text(full).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 4) }
        Button { withAnimation(.snappy(duration: 0.2)) { showFull.toggle() } } label: {
            Label(showFull ? "Hide the full message" : "Show the full message", systemImage: showFull ? "chevron.up" : "chevron.down").labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(.link).font(.caption)
    }

    @ViewBuilder private var byline: some View {
        switch s.byline {
        case .nameTime:
            HStack(spacing: 4) { Text(question.asker.name).fontWeight(.semibold).foregroundStyle(.primary); Text("· \(question.time)") }.font(.caption).foregroundStyle(.secondary)
        case .asks:
            Text("\(question.asker.name) asks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var glyph: some View {
        switch question.asker {
        case .iris: Image("IrisIcon").resizable().scaledToFit()
        case .agent: Image(systemName: "cpu").resizable().scaledToFit()
        case .hatch: Image(systemName: "square.stack.3d.up").resizable().scaledToFit()
        }
    }

    @ViewBuilder private var avatar: some View {
        switch s.avatar {
        case .circle:
            glyph.frame(width: 15, height: 15).frame(width: 28, height: 28)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        case .large:
            glyph.frame(width: 20, height: 20).frame(width: 36, height: 36)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        case .mark:
            glyph.frame(width: 18, height: 18).padding(.top, 18)
        case .none:
            EmptyView()
        }
    }

    // MARK: Answers

    @ViewBuilder private var answers: some View {
        switch s.answers {
        case .list: list(radio: false)
        case .radio: list(radio: true)
        case .cards: cards
        case .accordion: accordion
        case .tiles: tiles
        case .table: table
        case .menu: menu
        case .buttons: buttons
        }
    }

    private func isSelected(_ o: LabOption) -> Bool { selection.wrappedValue == o.id }

    @ViewBuilder private func recommendedMark(_ o: LabOption) -> some View {
        if o.recommended {
            switch s.recommended {
            case .starText: Label("Recommended", systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor).imageScale(.small)
            case .badge: Text("Recommended").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
            case .irisPick: Text("\(question.asker.name)'s pick").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            case .tintedTitle, .none: EmptyView()
            }
        }
    }

    private func titleText(_ o: LabOption, weight: Font.Weight = .medium) -> some View {
        Text(o.title).fontWeight(weight).multilineTextAlignment(.leading)
            .foregroundStyle(o.recommended && s.recommended == .tintedTitle ? Color.accentColor : Color.primary)
            .help(s.longAnswer == .firstLine ? (o.detail ?? "") : "")
    }

    @ViewBuilder private func detailText(_ o: LabOption) -> some View {
        if let d = o.detail, s.longAnswer != .firstLine {
            let limit: Int? = expanded.contains(o.id) ? nil : (s.longAnswer == .twoLines ? 2 : (s.longAnswer == .threeLines ? 3 : nil))
            Text(d).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(limit).fixedSize(horizontal: false, vertical: true)
            if limit != nil && d.count > (s.longAnswer == .twoLines ? 200 : 300) {
                Button("More") { expanded.insert(o.id) }.buttonStyle(.link).font(.caption)
            }
        }
    }

    @ViewBuilder private func keyBadge(_ i: Int) -> some View {
        if s.keys == .numbers && i < 4 {
            Text("\(i + 1)").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 18, height: 18).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder private func indicator(_ selected: Bool, leading: Bool) -> some View {
        switch s.indicator {
        case .check:
            if !leading { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor).opacity(selected ? 1 : 0) }
        case .radio:
            if leading { Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary) }
        case .tint, .ring:
            EmptyView()
        }
    }

    private func rowBackground(_ selected: Bool, radio: Bool) -> Color {
        guard selected, !radio else { return .clear }
        return s.indicator == .ring ? .clear : Color.accentColor.opacity(s.indicator == .tint ? 0.14 : 0.1)
    }

    private func list(radio: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(question.options.enumerated()), id: \.element.id) { i, o in
                if i > 0 { Divider().padding(.leading, 14) }
                Button { selection.wrappedValue = o.id } label: {
                    HStack(alignment: .top, spacing: 10) {
                        keyBadge(i)
                        if radio {
                            Image(systemName: isSelected(o) ? "largecircle.fill.circle" : "circle").foregroundStyle(isSelected(o) ? Color.accentColor : .secondary)
                        } else {
                            indicator(isSelected(o), leading: true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) { titleText(o); recommendedMark(o) }
                            detailText(o)
                            LabGainCost(option: o)
                        }
                        Spacer(minLength: 8)
                        if !radio { indicator(isSelected(o), leading: false) }
                        if s.actions == .perAnswer && isSelected(o) {
                            Button(card.main) { model.main() }.buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.regular)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, s.gap(10))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowBackground(isSelected(o), radio: radio))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: s.indicator == .ring && isSelected(o) && !radio ? 2 : 0).padding(2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if question.allowsOwn && s.own == .row { Divider().padding(.leading, 14); ownRow }
        }
        .background(.quaternary.opacity(radio ? 0.25 : 0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: question.options.count > 2 ? 190 : 260), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { i, o in
                    Button { selection.wrappedValue = o.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { keyBadge(i); recommendedMark(o); Spacer(minLength: 0); indicator(isSelected(o), leading: true); indicator(isSelected(o), leading: false) }
                            titleText(o, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                            detailText(o)
                            LabGainCost(option: o)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(isSelected(o) && s.indicator == .tint ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected(o) ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected(o) ? 2 : 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            if question.allowsOwn && s.own == .row { ownRow.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12)) }
        }
    }

    private var accordion: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.element.id) { i, o in
                let open = isSelected(o)
                Button { withAnimation(.snappy(duration: 0.2)) { selection.wrappedValue = o.id } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            keyBadge(i)
                            Image(systemName: open ? "largecircle.fill.circle" : "circle").foregroundStyle(open ? Color.accentColor : .secondary)
                            titleText(o, weight: open ? .semibold : .regular).lineLimit(open ? nil : 1)
                            recommendedMark(o)
                            Spacer(minLength: 0)
                        }
                        if open {
                            VStack(alignment: .leading, spacing: 4) {
                                if let d = o.detail { Text(d).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
                                LabGainCost(option: o)
                            }
                            .padding(.leading, 26)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, s.gap(9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(open ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if question.allowsOwn && s.own == .row { ownRow }
        }
    }

    private var tiles: some View {
        VStack(spacing: s.gap(10)) {
            ForEach(Array(question.options.enumerated()), id: \.element.id) { i, o in
                Button { selection.wrappedValue = o.id } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(i + 1)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(isSelected(o) ? Color.accentColor : .secondary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) { Text(o.title).font(.title3.weight(.semibold)).multilineTextAlignment(.leading); recommendedMark(o) }
                            detailText(o)
                            LabGainCost(option: o)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected(o) ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected(o) ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected(o) ? 2 : 0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            if question.allowsOwn && s.own == .row { ownRow.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12)) }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            ForEach(Array(question.options.enumerated()), id: \.element.id) { i, o in
                if i > 0 { Divider() }
                Button { selection.wrappedValue = o.id } label: {
                    HStack(alignment: .top, spacing: 16) {
                        HStack(alignment: .top, spacing: 8) {
                            indicator(isSelected(o), leading: true)
                            VStack(alignment: .leading, spacing: 3) { titleText(o, weight: .semibold); recommendedMark(o) }
                        }
                        .frame(width: 200, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) { detailText(o); LabGainCost(option: o) }
                        Spacer(minLength: 0)
                        indicator(isSelected(o), leading: false)
                    }
                    .padding(.horizontal, 12).padding(.vertical, s.gap(10))
                    .background(rowBackground(isSelected(o), radio: false))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if question.allowsOwn && s.own == .row { Divider(); ownRow }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Answer", selection: selection) {
                ForEach(question.options) { o in Text(o.recommended ? "\(o.title) (recommended)" : o.title).tag(o.id) }
                if question.allowsOwn && s.own == .row { Divider(); Text("Something else…").tag("own") }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            if let o = question.options.first(where: { $0.id == selection.wrappedValue }) {
                VStack(alignment: .leading, spacing: 3) { detailText(o); LabGainCost(option: o) }
            } else if selection.wrappedValue == "own" {
                TextField("Write your own answer", text: $model.own, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
            }
        }
    }

    private var buttons: some View {
        FlowLayout(spacing: 8) {
            ForEach(question.options) { o in
                if o.recommended {
                    Button { selection.wrappedValue = o.id } label: { Label(o.title, systemImage: "star.fill") }.buttonStyle(.glassProminent)
                } else {
                    Button(o.title) { selection.wrappedValue = o.id }.buttonStyle(.glass)
                }
            }
            if question.allowsOwn && s.own == .row { Button("Something else…") { selection.wrappedValue = "own" }.buttonStyle(.glass) }
        }
        .buttonBorderShape(.capsule).controlSize(s.buttonSize.control)
    }

    private var ownRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { selection.wrappedValue = "own" } label: {
                HStack(spacing: 10) {
                    if s.indicator == .radio || s.answers == .radio || s.answers == .accordion {
                        Image(systemName: selection.wrappedValue == "own" ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection.wrappedValue == "own" ? Color.accentColor : .secondary)
                    }
                    Text("Something else…").foregroundStyle(.secondary)
                    Spacer()
                    if s.indicator == .check && s.answers == .list {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor).opacity(selection.wrappedValue == "own" ? 1 : 0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if selection.wrappedValue == "own" {
                TextField("Write your own answer", text: $model.own, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, s.gap(10))
    }

    @ViewBuilder private var ownExtra: some View {
        if s.own == .field {
            TextField("Or write your own answer", text: $model.own, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
        } else if s.own == .link {
            if linkOpen {
                TextField("Write your own answer", text: $model.own, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
            } else {
                Button("Write my own answer") { linkOpen = true }.buttonStyle(.link).font(.callout)
            }
        }
    }
}

private struct LabGainCost: View {
    let option: LabOption

    var body: some View {
        if option.gain != nil || option.cost != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let g = option.gain { line("plus", g, primary: true) }
                if let c = option.cost { line("minus", c, primary: false) }
            }
            .padding(.top, 2)
        }
    }

    private func line(_ symbol: String, _ text: String, primary: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 10)
            Text(text).font(.callout).foregroundStyle(primary ? Color.primary : Color.secondary).multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Designs

/// How a design's options are shown on the card: a gallery, large with a filmstrip, Today beside the pick, one at a
/// time, a Stage card, or large beside its description.
private struct LabDesignView: View {
    let card: LabCard
    let question: LabQuestion
    @ObservedObject var model: LabModel
    private var s: LabStyle { model.style }
    private var selection: Binding<String> { model.binding(question) }
    private var options: [LabSpecimen] { card.specimens.filter { !$0.isToday } }
    private var today: LabSpecimen? { card.specimens.first(where: \.isToday) }
    private var selected: LabSpecimen { options.first { $0.id == selection.wrappedValue } ?? options.first ?? card.specimens[0] }

    var body: some View {
        switch s.design {
        case .gallery:
            FlowLayout(spacing: 14) { ForEach(card.specimens) { thumb($0, width: s.thumb.width) } }.padding(4)
        case .hero:
            VStack(alignment: .leading, spacing: 12) {
                LabSpecimenView(spec: selected, width: min(s.thumb.width * 2.4, 620))
                caption(selected)
                HStack(spacing: 10) { ForEach(card.specimens) { thumb($0, width: 96, captionShown: false) } }
            }
        case .compare:
            VStack(alignment: .leading, spacing: 10) {
                if options.count > 1 {
                    Picker("Option", selection: selection) { ForEach(options) { Text($0.name).tag($0.id) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                HStack(alignment: .top, spacing: 16) {
                    if let today {
                        VStack(alignment: .leading, spacing: 6) { Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary); LabSpecimenView(spec: today, width: s.thumb.width * 1.4) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.name).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        LabSpecimenView(spec: selected, width: s.thumb.width * 1.4)
                    }
                }
            }
        case .carousel:
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).buttonBorderShape(.circle)
                    LabSpecimenView(spec: selected, width: min(s.thumb.width * 2.2, 560))
                    Button { step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).buttonBorderShape(.circle)
                }
                caption(selected)
                HStack(spacing: 6) { ForEach(options) { o in Circle().fill(o.id == selected.id ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 6, height: 6) } }
            }
            .frame(maxWidth: .infinity)
        case .stageCard:
            HStack(spacing: 14) {
                HStack(spacing: -30) { ForEach(card.specimens.prefix(4)) { LabSpecimenView(spec: $0, width: 110).shadow(color: .black.opacity(0.12), radius: 4, y: 2) } }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(card.specimens.count) options, drawn in the Stage").font(.headline)
                    Text("Judge them side by side with scenarios and pins.").font(.callout).foregroundStyle(.secondary)
                    Button("Open the Stage") {}.buttonStyle(.glass).buttonBorderShape(.capsule)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        case .split:
            HStack(alignment: .top, spacing: 16) {
                LabSpecimenView(spec: selected, width: s.thumb.width * 1.6)
                caption(selected)
            }
        }
    }

    private func step(_ by: Int) {
        guard let at = options.firstIndex(where: { $0.id == selected.id }) else { return }
        selection.wrappedValue = options[(at + by + options.count) % options.count].id
    }

    private func caption(_ spec: LabSpecimen) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(spec.name).font(.headline)
                if spec.recommended { Label("Recommended", systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor).imageScale(.small) }
            }
            Text(spec.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func thumb(_ spec: LabSpecimen, width: CGFloat, captionShown: Bool = true) -> some View {
        let on = !spec.isToday && spec.id == selected.id
        return Button { if !spec.isToday { selection.wrappedValue = spec.id } } label: {
            VStack(alignment: .leading, spacing: 6) {
                LabSpecimenView(spec: spec, width: width)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.accentColor : Color.clear, lineWidth: 3).padding(-3))
                if captionShown {
                    HStack(spacing: 5) {
                        Text(spec.name).font(.callout.weight(on ? .semibold : .regular)).foregroundStyle(spec.isToday ? Color.secondary : Color.primary)
                        if spec.recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.accentColor) }
                    }
                    .frame(width: width, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .help(spec.note)
    }
}

/// A design option drawn small: a window with a sidebar and rows, and a toast whose padding and corners differ.
struct LabSpecimenView: View {
    let spec: LabSpecimen
    var width: CGFloat

    var body: some View {
        let base: CGFloat = 320, scale = width / base
        drawing
            .frame(width: base, height: base * 0.625)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: width * 0.625, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private var drawing: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.secondary.opacity(0.35)).frame(width: 6, height: 6) }
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 18)
                Divider()
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(0..<5, id: \.self) { i in Capsule().fill(Color.secondary.opacity(0.18)).frame(width: CGFloat(34 + (i * 9) % 20), height: 5) }
                    }
                    .padding(9).frame(width: 70, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top).background(Color.secondary.opacity(0.06))
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<7, id: \.self) { i in Capsule().fill(Color.secondary.opacity(0.14)).frame(width: CGFloat(120 + (i * 37) % 90), height: 6) }
                    }
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            HStack(spacing: spec.padding * 0.6 + 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Saved").font(.system(size: 10, weight: .semibold))
                    Text("Query 1 saved to the library").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text("Undo").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
            }
            .padding(spec.padding)
            .frame(width: 190)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: spec.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: spec.radius, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(12)
        }
    }
}
