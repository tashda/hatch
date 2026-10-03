import SwiftUI
import Security
import HatchCore
import HatchSync

/// The GitHub token Hatch stores, in the macOS Keychain. Nothing else is written to disk.
enum HXKeychain {
    private static let service = "app.hatch.github"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        read("token")
    }

    private static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
        var q = query(account)
        q[kSecValueData as String] = Data(text.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        for account in ["token", "refresh", "expiry"] { SecItemDelete(query(account) as CFDictionary) }
    }
}

enum HXGitHub {
    /// The client every part of the app uses. Refresh expiring GitHub App authorization before API calls.
    static func client() -> GitHubClient {
        refreshAuthorizationIfNeeded()
        return GitHubClient(token: HXKeychain.read())
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
        var error: String?
    }

    @Published var user: GitHubUser?
    @Published var source: GitHubTokenSource = .none
    @Published var repos: [GitHubRepoSummary] = []
    @Published var busy = false
    @Published var error: String?

    func refresh() {
        busy = true
        Task {
            let probe = await Task.detached { () -> Probe in
                let source = GitHubClient.tokenSource(stored: HXKeychain.read())
                guard source != .none else { return Probe(source: source, user: nil, repos: [], error: nil) }
                let client = HXGitHub.client()
                do {
                    let me = try client.currentUser()
                    let repos = try client.listRepositories()
                    return Probe(source: source, user: me, repos: repos, error: nil)
                } catch {
                    return Probe(source: source, user: nil, repos: [], error: Self.describe(error))
                }
            }.value
            source = probe.source
            user = probe.user
            repos = probe.repos
            error = probe.error
            busy = false
        }
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
        case .specimens: nil
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
    @State private var openPicker: RepoRole?
    @State private var filter = ""
    @State private var saveError: String?

    init(account: GitHubAccountModel, projectName: String, initial: [RepoRole: String], ticketsLocked: Bool = false,
         onSave: @escaping (HXRepositoryAssignments) -> Bool) {
        self.account = account
        self.projectName = projectName
        self.ticketsLocked = ticketsLocked
        self.onSave = onSave
        _selectedNames = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image("GitHubMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 27, height: 27)
                    .frame(width: 46, height: 46)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose GitHub repositories").font(.title3.weight(.semibold))
                    Text("Select where \(projectName) keeps its work.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let user = account.user {
                    Label("@\(user.login)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else if Snapshots.demoMode {
                    Label("Demo preview", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            if connected {
                Form {
                    Section {
                        assignmentRow(.tickets, title: "Tickets",
                                      detail: ticketsLocked ? "Issues and attachments · fixed after the first ticket" : "Issues and attachments · private only",
                                      symbol: "ticket")
                        assignmentRow(.app, title: "Project", detail: "App source and Specs", symbol: "curlybraces")
                        assignmentRow(.designSystem, title: "Design", detail: "Design system assets", symbol: "paintpalette")
                    } header: {
                        Text("Repository assignments")
                    } footer: {
                        if available.isEmpty {
                            Text("No repositories are available to Hatch. Check the GitHub App installation and refresh the list.")
                                .foregroundStyle(Theme.critical)
                        } else if hasUnavailableAssignment {
                            Text("A saved repository is no longer available to this account. Choose another before saving.")
                                .foregroundStyle(Theme.critical)
                        } else if hasDuplicateAssignments {
                            Text("Choose a different repository for each role.")
                                .foregroundStyle(Theme.critical)
                        } else {
                            Text("Only repositories available to Hatch appear here.")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 270)
            } else {
                connectionPrompt
            }

            Divider()
            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
            }
            HStack {
                Text(ticketsLocked
                     ? "Project and Design can be changed later in Project settings."
                     : "You can change these choices later in Project settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save repositories") { save() }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 660)
        .onAppear { if !Snapshots.demoMode { account.refresh() } }
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

    private func assignmentRow(_ role: RepoRole, title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            if role == .tickets && ticketsLocked {
                Label(selectedNames[role] ?? "Not selected", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 190, alignment: .trailing)
            } else {
                Button {
                    filter = ""
                    openPicker = role
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedNames[role] ?? "Choose repository").lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 190, alignment: .trailing)
                }
                .buttonStyle(.bordered)
                .popover(isPresented: Binding(
                    get: { openPicker == role },
                    set: { if !$0 { openPicker = nil } }
                ), arrowEdge: .bottom) {
                    repositoryPopover(for: role)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func repositoryPopover(for role: RepoRole) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose \(role == .tickets ? "tickets" : role == .app ? "project" : "design") repository")
                .font(.headline)
            TextField("Filter repositories", text: $filter)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if role != .tickets {
                        Button {
                            selectedNames.removeValue(forKey: role)
                            openPicker = nil
                        } label: {
                            Label("No repository", systemImage: "minus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    ForEach(filteredRepositories) { repo in
                        Button {
                            selectedNames[role] = repo.fullName
                            openPicker = nil
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: repo.isPrivate ? "lock" : "globe")
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.fullName).lineLimit(1)
                                    Text(repo.isPrivate ? "Private" : role == .tickets ? "Public · unavailable for Tickets" : "Public")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedNames[role] == repo.fullName {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(role == .tickets && !repo.isPrivate)
                        Divider()
                    }
                    if filteredRepositories.isEmpty {
                        Text("No matching repositories")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }
            }
            HStack {
                Text("Repositories available to Hatch")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { account.refresh() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 390, height: 350)
    }

    private var filteredRepositories: [GitHubRepoSummary] {
        available.filter { filter.isEmpty || $0.fullName.localizedCaseInsensitiveContains(filter) }
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
