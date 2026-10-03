import AppKit
import Foundation
import SwiftUI

/// GitHub App device authorization for the native app. The only credential saved is the resulting user token,
/// stored in the macOS Keychain; users never handle or paste a token.
@MainActor
final class GitHubDeviceFlow: ObservableObject {
    @Published var userCode: String?
    @Published var verificationURL: URL?
    @Published var message: String?
    @Published var error: String?
    @Published var busy = false

    private var task: Task<Void, Never>?

    func start(onToken: @escaping (String) -> Void) {
        guard !busy else { return }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "HatchGitHubClientID") as? String,
              !clientID.isEmpty, !clientID.contains("REPLACE") else {
            error = "Hatch's GitHub App is not configured yet. Add its Client ID after registering the app."
            return
        }

        busy = true
        userCode = nil
        verificationURL = nil
        error = nil
        message = "Contacting GitHub…"
        task = Task {
            do {
                let device = try await GitHubDeviceFlow.requestDeviceCode(clientID: clientID)
                userCode = device.userCode
                verificationURL = device.verificationURL
                message = "Enter this code on GitHub. Hatch will finish connecting automatically."
                NSWorkspace.shared.open(device.verificationURL)

                var interval = max(device.interval, 5)
                let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))
                while Date() < deadline, !Task.isCancelled {
                    try await Task.sleep(for: .seconds(interval))
                    do {
                        let token = try await GitHubDeviceFlow.poll(clientID: clientID, deviceCode: device.deviceCode)
                        guard HXKeychain.writeOAuth(accessToken: token.accessToken,
                                                    refreshToken: token.refreshToken,
                                                    expiresIn: token.expiresIn) else { throw DeviceFlowError.keychain }
                        NotificationCenter.default.post(name: .hxGitHubAccountChanged, object: nil)
                        onToken(token.accessToken)
                        message = "GitHub connected."
                        busy = false
                        userCode = nil
                        return
                    } catch DeviceFlowError.pending {
                        continue
                    } catch DeviceFlowError.slowDown {
                        interval += 5
                    }
                }
                if !Task.isCancelled { error = "The GitHub sign-in code expired. Start again to get a new code." }
            } catch is CancellationError {
                // The user cancelled the in-progress authorization.
            } catch {
                self.error = Self.describe(error)
            }
            busy = false
            userCode = nil
            verificationURL = nil
            if message != "GitHub connected." { message = nil }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        busy = false
        userCode = nil
        verificationURL = nil
        message = nil
        error = nil
    }

    private struct DeviceCode: Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let expiresIn: Int
        let interval: Int
    }

    private struct OAuthToken: Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
    }

    private enum DeviceFlowError: Error {
        case pending, slowDown, rejected(String), keychain
    }

    private static func requestDeviceCode(clientID: String) async throws -> DeviceCode {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([("client_id", clientID)])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let urlString = json["verification_uri"] as? String,
              let verificationURL = URL(string: urlString) else {
            throw DeviceFlowError.rejected("GitHub did not return a device sign-in code.")
        }
        return DeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURL: verificationURL,
                          expiresIn: json["expires_in"] as? Int ?? 900, interval: json["interval"] as? Int ?? 5)
    }

    private static func poll(clientID: String, deviceCode: String) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([
            ("client_id", clientID),
            ("device_code", deviceCode),
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceFlowError.rejected("GitHub could not complete sign-in.")
        }
        if let token = json["access_token"] as? String {
            return OAuthToken(accessToken: token, refreshToken: json["refresh_token"] as? String,
                              expiresIn: json["expires_in"] as? Int)
        }
        switch json["error"] as? String {
        case "authorization_pending": throw DeviceFlowError.pending
        case "slow_down": throw DeviceFlowError.slowDown
        case "access_denied": throw DeviceFlowError.rejected("GitHub sign-in was denied.")
        case "expired_token": throw DeviceFlowError.rejected("The GitHub sign-in code expired. Start again.")
        default: throw DeviceFlowError.rejected("GitHub could not complete sign-in.")
        }
    }

    private static func form(_ values: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func describe(_ error: Error) -> String {
        if case DeviceFlowError.keychain = error { return "The macOS Keychain would not store the GitHub authorization." }
        if case DeviceFlowError.rejected(let message) = error { return message }
        return "GitHub sign-in failed: \(error.localizedDescription)"
    }
}
