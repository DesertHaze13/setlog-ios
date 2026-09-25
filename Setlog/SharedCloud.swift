import Foundation
import Security

struct CloudSession: Codable {
    var uid: String
    var email: String
    var idToken: String
    var refreshToken: String
    var expiresAt: Double
}

struct CloudRecord {
    var state: WorkoutState
    var revision: Int
    var updateTime: String
}

enum CloudFailure: LocalizedError {
    case invalidResponse, conflict, missingRecord, server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The shared response was invalid. Nothing was overwritten."
        case .conflict: "Another device changed the shared record. Choose which copy to keep."
        case .missingRecord: "Sign in on the website first to establish the reviewed shared copy."
        case .server(let detail): detail
        }
    }
}

enum SharedCloud {
    private static let apiKey = configValue("API_KEY")
    private static let projectId = configValue("PROJECT_ID")
    private static let keychainAccount = "setlog-firebase-session-v1"

    private static func configValue(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) else { return "" }
        return values[key] as? String ?? ""
    }

    static func storedSession() -> CloudSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: keychainAccount,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSession.self, from: data)
    }

    static func saveSession(_ session: CloudSession) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
        guard let data = try? JSONEncoder().encode(session) else { return }
        var item = query
        item[kSecValueData as String] = data
        #if !os(macOS)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        SecItemAdd(item as CFDictionary, nil)
    }

    static func signOut() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: keychainAccount] as CFDictionary)
    }

    static func authenticate(email: String, password: String, create: Bool) async throws -> CloudSession {
        let action = create ? "signUp" : "signInWithPassword"
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(action)?key=\(apiKey)")!
        let body = ["email": email, "password": password, "returnSecureToken": true] as [String: Any]
        let data = try await request(url: url, method: "POST", body: JSONSerialization.data(withJSONObject: body), contentType: "application/json")
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uid = result["localId"] as? String,
              let token = result["idToken"] as? String,
              let refresh = result["refreshToken"] as? String,
              let seconds = Double(result["expiresIn"] as? String ?? "") else { throw CloudFailure.invalidResponse }
        let session = CloudSession(uid: uid, email: result["email"] as? String ?? email,
                                   idToken: token, refreshToken: refresh,
                                   expiresAt: Date().timeIntervalSince1970 + seconds)
        saveSession(session)
        return session
    }

    static func fresh(_ session: CloudSession) async throws -> CloudSession {
        let cached = storedSession()
        let session = cached?.uid == session.uid ? cached! : session
        if session.expiresAt > Date().timeIntervalSince1970 + 60 { return session }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"),
                            URLQueryItem(name: "refresh_token", value: session.refreshToken)]
        let data = try await request(url: url, method: "POST", body: Data((parts.percentEncodedQuery ?? "").utf8), contentType: "application/x-www-form-urlencoded")
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = result["id_token"] as? String,
              let refresh = result["refresh_token"] as? String,
              let seconds = Double(result["expires_in"] as? String ?? "") else { throw CloudFailure.invalidResponse }
        let next = CloudSession(uid: session.uid, email: session.email, idToken: token,
                                refreshToken: refresh, expiresAt: Date().timeIntervalSince1970 + seconds)
        saveSession(next)
        return next
    }

    static func read(_ session: CloudSession) async throws -> CloudRecord? {
        let current = try await fresh(session)
        var request = URLRequest(url: documentURL(uid: current.uid))
        request.setValue("Bearer \(current.idToken)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudFailure.invalidResponse }
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw serverError(data) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = object["fields"] as? [String: Any],
              let json = (fields["json"] as? [String: Any])?["stringValue"] as? String,
              let revisionText = (fields["revision"] as? [String: Any])?["integerValue"] as? String,
              let revision = Int(revisionText),
              let updateTime = object["updateTime"] as? String,
              let state = try? JSONDecoder().decode(WorkoutState.self, from: Data(json.utf8)),
              state.isValid else { throw CloudFailure.invalidResponse }
        return CloudRecord(state: state, revision: revision, updateTime: updateTime)
    }

    static func write(_ session: CloudSession, state: WorkoutState, after previous: CloudRecord) async throws -> CloudRecord {
        let current = try await fresh(session)
        var components = URLComponents(url: documentURL(uid: current.uid), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "currentDocument.updateTime", value: previous.updateTime)]
        let json = String(data: try JSONEncoder().encode(state), encoding: .utf8)!
        let fields: [String: Any] = ["fields": ["json": ["stringValue": json],
                                                "revision": ["integerValue": String(previous.revision + 1)]]]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(current.idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudFailure.invalidResponse }
        if response.statusCode == 409 || response.statusCode == 412 { throw CloudFailure.conflict }
        guard (200..<300).contains(response.statusCode) else { throw serverError(data) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updateTime = object["updateTime"] as? String else { throw CloudFailure.invalidResponse }
        return CloudRecord(state: state, revision: previous.revision + 1, updateTime: updateTime)
    }

    private static func documentURL(uid: String) -> URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/users/\(uid)/workout/state")!
    }

    private static func request(url: URL, method: String, body: Data, contentType: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        #if os(iOS)
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudFailure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw serverError(data) }
        return data
    }

    private static func serverError(_ data: Data) -> CloudFailure {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let detail = (object?["error"] as? [String: Any])?["message"] as? String ?? "The shared service is unavailable."
        return .server(detail.replacingOccurrences(of: "_", with: " ").lowercased())
    }
}
