import SwiftUI
import Security
import HatchCore
import HatchSync

/// The GitHub token Hatch stores, in the macOS Keychain. Nothing else is written to disk.
/// Debug builds keep it in UserDefaults instead: every rebuild has a new signature, and the Keychain asks for the
/// login password each time. Release builds always use the Keychain.
enum HXKeychain {
    private static let service = "app.hatch.github"

    #if DEBUG
    private static func debugKey(_ account: String) -> String { "hatch.debug.github.\(account)" }
    #endif

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        read("token")
    }

    private static func read(_ account: String) -> String? {
        #if DEBUG
        let stored = UserDefaults.standard.string(forKey: debugKey(account)) ?? ""
        return stored.isEmpty ? nil : stored
        #else
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #endif
    }

    @discardableResult
    static func write(_ token: String) -> Bool {
        delete()
        return writeItem("token", token)
    }

    @discardableResult
    static func writeOAuth(accessToken: String, refreshToken: String?, expiresIn: Int?) -> Bool {
        delete()
        guard writeItem("token", accessToken) else { return false }
        if let refreshToken, !writeItem("refresh", refreshToken) { delete(); return false }
        if let expiresIn, !writeItem("expiry", String(Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970)) {
            delete(); return false
        }
        return true
    }

    static func refreshToken() -> String? { read("refresh") }
    static func expiry() -> Date? { read("expiry").flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }

    private static func writeItem(_ account: String, _ text: String) -> Bool {
        #if DEBUG
        UserDefaults.standard.set(text, forKey: debugKey(account))
        return true
        #else
        var q = query(account)
        q[kSecValueData as String] = Data(text.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        #endif
    }

    static func delete() {
        for account in ["token", "refresh", "expiry"] {
            #if DEBUG
            UserDefaults.standard.removeObject(forKey: debugKey(account))
            #else
            SecItemDelete(query(account) as CFDictionary)
            #endif
        }
    }
}

enum HXGitHub {
    /// The client every part of the app uses. Refresh expiring GitHub App authorization before API calls.
    static func client() -> GitHubClient {
        refreshAuthorizationIfNeeded()
        return GitHubClient(token: HXKeychain.read(), fallback: false)
    }

    private static func refreshAuthorizationIfNeeded() {
        guard let expiry = HXKeychain.expiry(), expiry.timeIntervalSinceNow < 300,
              let refreshToken = HXKeychain.refreshToken(),
              let clientID = Bundle.main.object(forInfoDictionaryKey: "HatchGitHubClientID") as? String,
              !clientID.isEmpty, !clientID.contains("REPLACE") else { return }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            responseData = data
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 20) == .success,
              let responseData,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let accessToken = json["access_token"] as? String else { return }
        _ = HXKeychain.writeOAuth(accessToken: accessToken,
                                  refreshToken: json["refresh_token"] as? String ?? refreshToken,
                                  expiresIn: json["expires_in"] as? Int)
    }
}

extension Notification.Name {
    static let hxGitHubAccountChanged = Notification.Name("Hatch.GitHubAccountChanged")
}

/// Who Hatch is signed in as, which repositories it can see, and the actions that link or create the tickets repository.
@MainActor
final class GitHubAccountModel: ObservableObject {
    struct Probe: Sendable {
        var source: GitHubTokenSource
        var user: GitHubUser?
        var repos: [GitHubRepoSummary]
        var installation: GitHubInstallation?
        var repositoryCount: Int?
        var rateLimit: GitHubRateLimit?
        var error: String?
    }

    /// Whether a tickets repository has Hatch's labels, checked once each time Settings › GitHub appears.
    enum LabelCheck: Equatable {
        case checking, repairing, present, missing(Int), failed(String)
    }

    @Published var user: GitHubUser?
    @Published var source: GitHubTokenSource = .none
    @Published var repos: [GitHubRepoSummary] = []
    @Published var installation: GitHubInstallation?
    /// How many repositories the installation was given, when the owner chose some rather than all.
    @Published var repositoryCount: Int?
    @Published var rateLimit: GitHubRateLimit?
    @Published var labelChecks: [String: LabelCheck] = [:]
    @Published var busy = false
    @Published var error: String?

    /// Who is signed in and what Hatch can see. With `details`, also the repository count and the rate limit, which
    /// only Settings shows (the rate limit costs nothing; the count is one small request).
    func refresh(details: Bool = false) {
        busy = true
        Task {
            let probe = await Task.detached { () -> Probe in
                let source: GitHubTokenSource = HXKeychain.read() == nil ? .none : .stored
                guard source != .none else { return Probe(source: source, user: nil, repos: [], error: nil) }
                let client = HXGitHub.client()
                do {
                    let me = try client.currentUser()
                    let repos = try client.listRepositories()
                    let all = (try? client.installations()) ?? []
                    // The owner's own installation first; an organization's only when there is no personal one.
                    let installation = all.first { $0.account.lowercased() == me.login.lowercased() } ?? all.first
                    var count: Int?
                    var limit: GitHubRateLimit?
                    if details {
                        if let installation, !installation.allRepositories {
                            count = try? client.installationRepositoryCount(installation.id)
                        }
                        limit = try? client.rateLimit()
                    }
                    return Probe(source: source, user: me, repos: repos, installation: installation,
                                 repositoryCount: count, rateLimit: limit, error: nil)
                } catch {
                    return Probe(source: source, user: nil, repos: [], error: Self.describe(error))
                }
            }.value
            source = probe.source
            user = probe.user
            repos = probe.repos
            installation = probe.installation
            if details || probe.user == nil {
                repositoryCount = probe.repositoryCount
                rateLimit = probe.rateLimit
            }
            error = probe.error
            busy = false
        }
    }

    /// Asks GitHub which of Hatch's labels each repository lacks. Off the main thread; one request per repository.
    func checkLabels(_ repositories: [String]) {
        guard user != nil else { return }
        for repo in repositories { labelChecks[repo] = .checking }
        Task {
            for repo in repositories {
                let check = await Task.detached { () -> LabelCheck in
                    do {
                        let missing = try HXGitHub.client().missingHatchLabels(repo: repo)
                        return missing.isEmpty ? .present : .missing(missing.count)
                    } catch {
                        return .failed(Self.describe(error))
                    }
                }.value
                labelChecks[repo] = check
            }
        }
    }

    /// Adds Hatch's missing labels to `repo`, then checks again.
    func repairLabels(_ repo: String) {
        labelChecks[repo] = .repairing
        Task {
            let failure = await Task.detached { () -> String? in
                do { try HXGitHub.client().ensureLabels(repo: repo, LabelSpec.baseSet); return nil }
                catch { return Self.describe(error) }
            }.value
            if let failure { labelChecks[repo] = .failed(failure) } else { checkLabels([repo]) }
        }
    }

    /// Made-up account for snapshots: connected, with two permissions missing so the page shows both states.
    func loadDemo() {
        user = GitHubUser(login: "tashda", name: "Kenneth Berg")
        source = .stored
        repos = [
            GitHubRepoSummary(fullName: "acme/hatch-tickets", isPrivate: true),
            GitHubRepoSummary(fullName: "acme/client-tickets", isPrivate: true),
            GitHubRepoSummary(fullName: "acme/app", isPrivate: true, defaultBranch: "main"),
            GitHubRepoSummary(fullName: "acme/app-notebook", isPrivate: true),
            GitHubRepoSummary(fullName: "acme/design-system", isPrivate: false),
        ]
        installation = GitHubInstallation(
            id: 1, appSlug: "hatch", account: "tashda", settingsURL: URL(string: "https://github.com/settings/installations/1")!,
            repositorySelection: "all",
            permissions: ["issues": "write", "contents": "read", "checks": "read", "statuses": "read", "metadata": "read"])
        rateLimit = GitHubRateLimit(remaining: 4812, limit: 5000, reset: Date().addingTimeInterval(38 * 60))
        labelChecks = ["acme/hatch-tickets": .present, "acme/client-tickets": .missing(3)]
        error = nil
        busy = false
    }

    /// GitHub's page where repositories are added to Hatch's installation.
    var manageRepositoriesURL: URL {
        installation?.settingsURL ?? URL(string: "https://github.com/settings/installations")!
    }

    func connect(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !HXKeychain.write(trimmed) { error = "The Keychain would not store the GitHub authorization."; return }
        NotificationCenter.default.post(name: .hxGitHubAccountChanged, object: nil)
        refresh()
    }

    func signOut() {
        HXKeychain.delete()
        NotificationCenter.default.post(name: .hxGitHubAccountChanged, object: nil)
        refresh()
    }

    /// Links `fullName` as a tickets repository, creating it (private) when asked. Reports back on the main actor.
    func prepareTicketsRepo(_ fullName: String, create: Bool, done: @escaping (Result<TicketsRepoReport, Error>) -> Void) {
        busy = true
        Task {
            let result = await Task.detached { () -> Result<TicketsRepoReport, Error> in
                Result { try HXGitHub.client().prepareTicketsRepo(fullName, createIfMissing: create) }
            }.value
            busy = false
            if case .success = result { refresh() }
            done(result)
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let t = error as? TrackerError {
            switch t {
            case .noToken: return "No token found."
            case .unauthorized: return "GitHub did not accept this token. It may have expired, or it lacks the repo scope."
            default: return "\(t)"
            }
        }
        return "\(error)"
    }
}

/// "Choose from GitHub…": every repository the token can see, private ones marked.
struct HXRepoPickerMenu: View {
    @ObservedObject var account: GitHubAccountModel
    let onPick: (GitHubRepoSummary) -> Void

    var body: some View {
        Menu {
            if account.repos.isEmpty {
                Text(account.user == nil ? "Connect GitHub in Settings first" : "No repositories found")
            }
            ForEach(account.repos) { repo in
                Button { onPick(repo) } label: {
                    Label(repo.fullName, systemImage: repo.isPrivate ? "lock" : "globe")
                }
            }
        } label: {
            Label("Choose from GitHub", systemImage: "list.bullet")
        }
        .menuIndicator(.hidden)
        .disabled(account.user == nil)
        .task { if !Snapshots.demoMode && account.user == nil && !account.busy { account.refresh() } }
    }
}

/// The three repository roles chosen from GitHub. Tickets must remain private.
struct HXRepositoryAssignments {
    let tickets: GitHubRepoSummary
    let project: GitHubRepoSummary?
    let design: GitHubRepoSummary?

    func repository(for role: RepoRole) -> GitHubRepoSummary? {
        switch role {
        case .tickets: tickets
        case .app: project
        case .designSystem: design
        case .specimens, .notebook: nil
        }
    }

    func apply(to config: inout ProjectConfig) {
        config.ticketsRepo = tickets.fullName
        for role in [RepoRole.tickets, .app, .designSystem] {
            let selected = repository(for: role)
            if let index = config.repos.firstIndex(where: { $0.role == role }) {
                if let selected {
                    if config.repos[index].remote != selected.fullName {
                        config.repos[index].localPath = nil
                    }
                    config.repos[index].remote = selected.fullName
                    if role != .tickets { config.repos[index].branch = selected.defaultBranch }
                } else {
                    config.repos.remove(at: index)
                }
            } else if let selected {
                config.repos.append(RepoConfig(role: role, remote: selected.fullName,
                                             branch: role == .tickets ? "main" : selected.defaultBranch))
            }
        }
    }
}

/// A fixed, grouped macOS sheet. Search filters GitHub's repository list and never accepts a typed remote.
struct HXRepositorySelectionSheet: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var account: GitHubAccountModel
    let projectName: String
    let ticketsLocked: Bool
    let onSave: (HXRepositoryAssignments) -> Bool
    @Environment(\.dismiss) private var dismiss

    @StateObject private var deviceFlow = GitHubDeviceFlow()
    @State private var selectedNames: [RepoRole: String]
    @State private var saveError: String?

    init(account: GitHubAccountModel, projectName: String, initial: [RepoRole: String], ticketsLocked: Bool = false,
         onSave: @escaping (HXRepositoryAssignments) -> Bool) {
        self.account = account
        self.projectName = projectName
        self.ticketsLocked = ticketsLocked
        self.onSave = onSave
        _selectedNames = State(initialValue: initial)
    }

    /// A plain sheet: a title, one grouped form with a pop-up menu per role, and the standard buttons.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose GitHub Repositories").font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 4)

            if connected {
                Form {
                    Section {
                        assignmentRow(.tickets, title: "Tickets",
                                      detail: ticketsLocked ? "Issues and attachments. Fixed after the first ticket." : "Issues and attachments. Private repositories only.")
                        assignmentRow(.app, title: "Project", detail: "App source and Specs")
                        assignmentRow(.designSystem, title: "Components", detail: "Only when they are a separate repository; most apps keep them inside")
                    } footer: {
                        statusLine
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                connectionPrompt
            }

            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 24)
            }
            HStack {
                Text(ticketsLocked
                     ? "Project and Design can be changed later in Project settings."
                     : "You can change these choices later in Project settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(width: 540)
        .onAppear { if !Snapshots.demoMode { account.refresh() } }
    }

    private var subtitle: String {
        if let user = account.user { return "Select where \(projectName) keeps its work. Connected as @\(user.login)." }
        return "Select where \(projectName) keeps its work."
    }

    /// What is wrong, or a quiet note; plus a way to reload the list from GitHub.
    @ViewBuilder private var statusLine: some View {
        HStack(alignment: .firstTextBaseline) {
            if available.isEmpty {
                Text("No repositories are available to Hatch. Check the GitHub App installation and refresh the list.")
                    .foregroundStyle(Theme.critical)
            } else if hasUnavailableAssignment {
                Text("A saved repository is no longer available to this account. Choose another before saving.")
                    .foregroundStyle(Theme.critical)
            } else if hasDuplicateAssignments {
                Text("Choose a different repository for each role.").foregroundStyle(Theme.critical)
            } else {
                Text("Only repositories available to Hatch appear here.")
            }
            Spacer()
            if !Snapshots.demoMode {
                Button("Refresh") { account.refresh() }.buttonStyle(.link)
            }
        }
    }

    private var connected: Bool { account.user != nil || Snapshots.demoMode }

    private var available: [GitHubRepoSummary] {
        if Snapshots.demoMode {
            return [
                GitHubRepoSummary(fullName: "acme/hatch-tickets", isPrivate: true),
                GitHubRepoSummary(fullName: "acme/app", isPrivate: true),
                GitHubRepoSummary(fullName: "acme/design-system", isPrivate: true),
                GitHubRepoSummary(fullName: "acme/public-site", isPrivate: false)
            ]
        }
        return account.repos
    }

    private var canSave: Bool {
        guard connected, let tickets = chosen(.tickets), tickets.isPrivate else { return false }
        guard [RepoRole.app, .designSystem].allSatisfy({ role in
            selectedNames[role] == nil || chosen(role) != nil
        }) else { return false }
        return !hasDuplicateAssignments
    }

    private var hasDuplicateAssignments: Bool {
        let names = [RepoRole.tickets, .app, .designSystem].compactMap { selectedNames[$0] }
        return Set(names).count != names.count
    }

    private var hasUnavailableAssignment: Bool {
        [RepoRole.tickets, .app, .designSystem].contains { role in
            selectedNames[role] != nil && chosen(role) == nil
        }
    }

    private func chosen(_ role: RepoRole) -> GitHubRepoSummary? {
        guard let name = selectedNames[role] else { return nil }
        return available.first { $0.fullName == name }
    }

    /// The repositories a role may use: Tickets takes private ones only.
    private func choices(for role: RepoRole) -> [GitHubRepoSummary] {
        role == .tickets ? available.filter { $0.isPrivate } : available
    }

    private func assignmentRow(_ role: RepoRole, title: String, detail: String) -> some View {
        LabeledContent {
            if role == .tickets && ticketsLocked {
                Label(selectedNames[role] ?? "Not selected", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                Picker(title, selection: Binding<String?>(
                    get: { selectedNames[role] },
                    set: { selectedNames[role] = $0 }
                )) {
                    if role != .tickets { Text("None").tag(String?.none) }
                    // A saved choice that is no longer available stays visible, so it can be replaced on purpose.
                    if let name = selectedNames[role], !choices(for: role).contains(where: { $0.fullName == name }) {
                        Text("\(name) (unavailable)").tag(String?.some(name))
                    } else if selectedNames[role] == nil && role == .tickets {
                        Text("Choose…").tag(String?.none)
                    }
                    ForEach(choices(for: role), id: \.fullName) { repo in
                        Text(repo.isPrivate ? repo.fullName : "\(repo.fullName) (public)").tag(String?.some(repo.fullName))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var connectionPrompt: some View {
        VStack(spacing: 12) {
            Text("Connect GitHub to choose repositories").font(.headline)
            Text("Hatch lists only repositories available to your GitHub account. No repository address or token needs to be typed.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if account.busy { ProgressView("Checking account…") }
            if let error = account.error { Text(error).foregroundStyle(Theme.critical) }
            if let code = deviceFlow.userCode {
                Text("Enter this code on GitHub").foregroundStyle(.secondary)
                Text(code).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
                if let url = deviceFlow.verificationURL {
                    Button("Open GitHub") { NSWorkspace.shared.open(url) }
                }
            }
            if let error = deviceFlow.error { Text(error).foregroundStyle(Theme.critical) }
            if deviceFlow.busy {
                Button("Cancel connection") { deviceFlow.cancel() }
            } else {
                Button("Connect with GitHub") { deviceFlow.start { _ in account.refresh() } }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func save() {
        guard let tickets = chosen(.tickets), tickets.isPrivate else { return }
        if onSave(HXRepositoryAssignments(tickets: tickets, project: chosen(.app), design: chosen(.designSystem))) {
            dismiss()
        } else {
            saveError = state.errorMessage ?? "Could not save these repositories."
        }
    }
}
