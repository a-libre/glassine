import AppKit
import CryptoKit
import Foundation
import Security

// Sync with GitHub: the library kept in a private repository of the user's,
// so a second Mac — one they would rather not sign into iCloud on — has the
// same documents, and every version of every note is kept. No git binary, no
// daemon: Glassine talks to GitHub's REST API itself — blobs, trees, commits,
// one branch — and pushes each round of changes as one commit.
//
// The merge is three-way against a small state file that remembers, per
// path, the blob both sides agreed on last time. A file changed on one side
// only moves to the other; a file changed on both keeps the local version
// and writes the remote one beside it as "Name (conflict).md", the way the
// editor already settles a file changed under it. Nothing is ever lost: every
// push is a commit.

// MARK: - The remote

/// The head of the branch: the commit, and the tree it points at.
struct RemoteHead: Equatable {
    let commit: String
    let tree: String
}

enum SyncError: LocalizedError {
    case notFastForward
    case unauthorized
    case notFound(String)
    case rateLimited
    case offline(String)
    case http(Int, String)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notFastForward: return "The repository moved while this Mac was pushing."
        case .unauthorized: return "GitHub didn't accept the token. Sign in again."
        case .notFound(let what): return "GitHub has no \(what)."
        case .rateLimited: return "GitHub's rate limit is spent; it clears within the hour."
        case .offline(let s): return s
        case .http(let code, let message): return "GitHub answered \(code): \(message)"
        case .other(let s): return s
        }
    }

    var isOffline: Bool { if case .offline = self { return true } else { return false } }
}

/// What the engine needs of the place a library is kept in common: a head, a
/// tree of paths to blob ids, blobs, and one way to move the head forward
/// that fails when someone else moved it first.
protocol SyncRemote: AnyObject {
    var name: String { get }
    /// The head of the branch, or nil when there are no commits yet.
    func head() async throws -> RemoteHead?
    /// Every file under the tree, by path, with its blob id.
    func tree(_ sha: String) async throws -> [String: String]
    func blob(_ sha: String) async throws -> Data
    /// One commit on top of `base` with these writes and deletions.
    func push(base: RemoteHead?, writes: [String: Data], deletes: [String], message: String) async throws -> RemoteHead
}

// MARK: - Git plumbing

enum GitBlob {
    /// The id git gives a file with these bytes — the same one GitHub will
    /// report, so a local file can be compared to the tree without a request.
    static func sha(of data: Data) -> String {
        var d = Data("blob \(data.count)\0".utf8)
        d.append(data)
        return Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - GitHub's API

/// A thin client for api.github.com: one token, JSON in and out, and
/// GitHub's answers turned into SyncErrors.
final class GitHubAPI {
    static let base = "https://api.github.com"
    var token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 120
        c.waitsForConnectivity = false
        session = URLSession(configuration: c)
    }

    deinit { session.finishTasksAndInvalidate() }

    private static let userAgent = "Glassine/\(Distribution.version)"

    /// `path` is sent as given: callers percent-encode what needs it.
    func request(_ method: String, _ path: String, query: [String: String] = [:], body: Any? = nil,
                 accept: String = "application/vnd.github+json") async throws -> (Data, HTTPURLResponse) {
        guard var comps = URLComponents(string: GitHubAPI.base + path) else { throw SyncError.other("A path GitHub can't take: \(path)") }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw SyncError.other("A path GitHub can't take: \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue(GitHubAPI.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw SyncError.offline("Can't reach GitHub right now.")
            default:
                throw SyncError.other(e.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.other("No answer from GitHub.") }
        if (200..<300).contains(http.statusCode) { return (data, http) }
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
        switch http.statusCode {
        case 401: throw SyncError.unauthorized
        case 403 where http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0": throw SyncError.rateLimited
        case 403: throw SyncError.http(403, message.isEmpty ? "the token isn't allowed to do that" : message)
        case 404: throw SyncError.notFound(path.hasPrefix("/repos/") ? "repository or branch at \(path.dropFirst(7))" : "such thing (\(path))")
        default: throw SyncError.http(http.statusCode, message)
        }
    }

    func json(_ method: String, _ path: String, query: [String: String] = [:], body: Any? = nil) async throws -> [String: Any] {
        let (data, _) = try await request(method, path, query: query, body: body)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func jsonArray(_ method: String, _ path: String, query: [String: String] = [:]) async throws -> [[String: Any]] {
        let (data, _) = try await request(method, path, query: query)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    // MARK: Accounts and repositories

    /// The login of whoever the token belongs to.
    func login() async throws -> String {
        (try await json("GET", "/user"))["login"] as? String ?? ""
    }

    struct Repository {
        let fullName: String
        let defaultBranch: String
        let canPush: Bool
        let isPrivate: Bool
        let isEmpty: Bool
    }

    func repository(_ fullName: String) async throws -> Repository {
        let r = try await json("GET", "/repos/\(fullName)")
        let perms = r["permissions"] as? [String: Any]
        return Repository(
            fullName: r["full_name"] as? String ?? fullName,
            defaultBranch: r["default_branch"] as? String ?? "main",
            canPush: perms?["push"] as? Bool ?? true,
            isPrivate: r["private"] as? Bool ?? false,
            isEmpty: (r["size"] as? Int ?? 0) == 0
        )
    }

    /// The user's own repositories, most recently pushed first.
    func repositories() async throws -> [Repository] {
        let list = try await jsonArray("GET", "/user/repos", query: ["affiliation": "owner", "per_page": "100", "sort": "pushed"])
        return list.compactMap { r in
            guard let name = r["full_name"] as? String else { return nil }
            let perms = r["permissions"] as? [String: Any]
            return Repository(fullName: name, defaultBranch: r["default_branch"] as? String ?? "main",
                              canPush: perms?["push"] as? Bool ?? true, isPrivate: r["private"] as? Bool ?? false,
                              isEmpty: (r["size"] as? Int ?? 0) == 0)
        }
    }

    /// A new, empty, private repository under the user's own account.
    func createRepository(named name: String) async throws -> Repository {
        let r = try await json("POST", "/user/repos", body: [
            "name": name, "private": true, "auto_init": false,
            "description": "A Glassine library",
        ])
        return Repository(fullName: r["full_name"] as? String ?? name, defaultBranch: r["default_branch"] as? String ?? "main",
                          canPush: true, isPrivate: true, isEmpty: true)
    }

    // MARK: Signing in without a token to paste (OAuth device flow)

    /// The OAuth app Glassine signs in as. Empty until one is registered on
    /// github.com (Settings → Developer settings → OAuth Apps, with "Enable
    /// Device Flow" on); with it empty the sign-in button stays out of sight
    /// and a token is pasted instead. The id is public by design; there is
    /// no secret in the device flow.
    static let clientID = ""

    struct DeviceCode {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let interval: TimeInterval
        let expires: Date
    }

    private static func form(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: req)
        } catch {
            throw SyncError.offline("Can't reach GitHub right now.")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func requestDeviceCode() async throws -> DeviceCode {
        let r = try await form("https://github.com/login/device/code", ["client_id": clientID, "scope": "repo"])
        guard let device = r["device_code"] as? String, let user = r["user_code"] as? String,
              let uri = r["verification_uri"] as? String, let url = URL(string: uri) else {
            throw SyncError.other((r["error_description"] as? String) ?? "GitHub didn't offer a sign-in code.")
        }
        let interval = TimeInterval(r["interval"] as? Int ?? 5)
        let expires = Date().addingTimeInterval(TimeInterval(r["expires_in"] as? Int ?? 900))
        return DeviceCode(deviceCode: device, userCode: user, verificationURL: url, interval: interval, expires: expires)
    }

    /// Waits for the code to be entered on github.com; the token, once it is.
    static func waitForToken(_ code: DeviceCode) async throws -> String {
        var interval = code.interval
        while Date() < code.expires {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            let r = try await form("https://github.com/login/oauth/access_token", [
                "client_id": clientID, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = r["access_token"] as? String { return token }
            switch r["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw SyncError.other("The code expired before it was entered. Try again.")
            case "access_denied": throw SyncError.other("Sign-in was cancelled on github.com.")
            default: throw SyncError.other((r["error_description"] as? String) ?? "GitHub didn't finish the sign-in.")
            }
        }
        throw SyncError.other("The code expired before it was entered. Try again.")
    }
}

/// A branch of a GitHub repository as a SyncRemote.
final class GitHubRemote: SyncRemote {
    let api: GitHubAPI
    let repo: String
    let branch: String

    init(api: GitHubAPI, repo: String, branch: String) {
        self.api = api
        self.repo = repo
        self.branch = branch
    }

    var name: String { repo }

    func head() async throws -> RemoteHead? {
        do {
            let r = try await api.json("GET", "/repos/\(repo)/branches/\(branch)")
            guard let commit = r["commit"] as? [String: Any], let sha = commit["sha"] as? String,
                  let inner = commit["commit"] as? [String: Any], let tree = inner["tree"] as? [String: Any],
                  let treeSHA = tree["sha"] as? String else { throw SyncError.other("GitHub's answer about the branch made no sense.") }
            return RemoteHead(commit: sha, tree: treeSHA)
        } catch SyncError.notFound {
            // No such branch — or no commits at all, which looks the same
            // from here. An empty repository answers the commits list with 409.
            do {
                _ = try await api.request("GET", "/repos/\(repo)/commits", query: ["per_page": "1"])
            } catch SyncError.http(409, _) {
                return nil
            }
            throw SyncError.notFound("branch “\(branch)” in \(repo)")
        }
    }

    func tree(_ sha: String) async throws -> [String: String] {
        let r = try await api.json("GET", "/repos/\(repo)/git/trees/\(sha)", query: ["recursive": "1"])
        var files: [String: String] = [:]
        for entry in r["tree"] as? [[String: Any]] ?? [] {
            guard entry["type"] as? String == "blob", let path = entry["path"] as? String, let blob = entry["sha"] as? String else { continue }
            files[path] = blob
        }
        return files
    }

    func blob(_ sha: String) async throws -> Data {
        let (data, _) = try await api.request("GET", "/repos/\(repo)/git/blobs/\(sha)", accept: "application/vnd.github.raw+json")
        return data
    }

    func push(base: RemoteHead?, writes: [String: Data], deletes: [String], message: String) async throws -> RemoteHead {
        var base = base
        var writes = writes
        if base == nil {
            // The tree and commit endpoints refuse an empty repository; the
            // contents endpoint makes its first commit. One file goes in
            // that way and the rest follow as usual.
            let (firstPath, firstData) = writes.first.map { ($0.key, $0.value) }
                ?? (".glassine/library", Data("This repository is a Glassine library.\n".utf8))
            let escaped = firstPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? firstPath
            _ = try await api.json("PUT", "/repos/\(repo)/contents/\(escaped)", body: [
                "message": message, "content": firstData.base64EncodedString(), "branch": branch,
            ])
            writes.removeValue(forKey: firstPath)
            guard let made = try await head() else { throw SyncError.other("GitHub took the first file but shows no branch.") }
            base = made
            if writes.isEmpty && deletes.isEmpty { return made }
        }
        guard let base else { throw SyncError.other("No branch to push to.") }
        var entries: [[String: Any]] = []
        for (path, data) in writes {
            let r = try await api.json("POST", "/repos/\(repo)/git/blobs", body: ["content": data.base64EncodedString(), "encoding": "base64"])
            guard let sha = r["sha"] as? String else { throw SyncError.other("GitHub didn't return a blob id.") }
            entries.append(["path": path, "mode": "100644", "type": "blob", "sha": sha])
        }
        for path in deletes {
            entries.append(["path": path, "mode": "100644", "type": "blob", "sha": NSNull()])
        }
        let treeR = try await api.json("POST", "/repos/\(repo)/git/trees", body: ["base_tree": base.tree, "tree": entries])
        guard let treeSHA = treeR["sha"] as? String else { throw SyncError.other("GitHub didn't return a tree id.") }
        let commitR = try await api.json("POST", "/repos/\(repo)/git/commits", body: ["message": message, "tree": treeSHA, "parents": [base.commit]])
        guard let commitSHA = commitR["sha"] as? String else { throw SyncError.other("GitHub didn't return a commit id.") }
        do {
            _ = try await api.json("PATCH", "/repos/\(repo)/git/refs/heads/\(branch)", body: ["sha": commitSHA, "force": false])
        } catch SyncError.http(422, _) {
            throw SyncError.notFastForward
        }
        return RemoteHead(commit: commitSHA, tree: treeSHA)
    }
}

/// A folder standing in for a repository — the head in a manifest, the
/// blobs in an objects folder — so the merge can be exercised on one Mac
/// without a network. Used by the headless test (`-glassine.syncTest`).
final class FolderRemote: SyncRemote {
    let root: URL
    init(root: URL) { self.root = root }

    var name: String { root.lastPathComponent }
    private var manifest: URL { root.appendingPathComponent("head.json") }
    private var objects: URL { root.appendingPathComponent("objects", isDirectory: true) }

    private struct Manifest: Codable {
        var commit: String
        var tree: String
        var files: [String: String]
    }

    private func load() throws -> Manifest? {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
    }

    func head() async throws -> RemoteHead? {
        guard let m = try load() else { return nil }
        return RemoteHead(commit: m.commit, tree: m.tree)
    }

    func tree(_ sha: String) async throws -> [String: String] {
        guard let m = try load(), m.tree == sha else { throw SyncError.notFound("tree \(sha)") }
        return m.files
    }

    func blob(_ sha: String) async throws -> Data {
        try Data(contentsOf: objects.appendingPathComponent(sha))
    }

    func push(base: RemoteHead?, writes: [String: Data], deletes: [String], message: String) async throws -> RemoteHead {
        let current = try load()
        guard current?.commit == base?.commit else { throw SyncError.notFastForward }
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        var files = current?.files ?? [:]
        for (path, data) in writes {
            let sha = GitBlob.sha(of: data)
            try data.write(to: objects.appendingPathComponent(sha))
            files[path] = sha
        }
        for path in deletes { files.removeValue(forKey: path) }
        let commit = UUID().uuidString
        let treeSHA = Insecure.SHA1.hash(data: Data(files.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)\n" }.joined().utf8))
            .map { String(format: "%02x", $0) }.joined()
        try JSONEncoder().encode(Manifest(commit: commit, tree: treeSHA, files: files)).write(to: manifest)
        try? (message + "\n").data(using: .utf8)?.write(to: root.appendingPathComponent("last-message.txt"))
        return RemoteHead(commit: commit, tree: treeSHA)
    }
}

// MARK: - Keychain

enum SyncKeychain {
    static let service = "ink.glassine.sync"
    static let account = "github"

    static func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func store(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(token.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Glassine — GitHub sync"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func forget() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - One round of sync

/// What both sides agreed on last time: the head, and each path's blob.
struct SyncState: Codable {
    var head: String? = nil
    var tree: String? = nil
    var files: [String: String] = [:]

    static func load(from url: URL) -> SyncState {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return s
    }

    func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try? enc.encode(self).write(to: url, options: .atomic)
    }
}

struct SyncOutcome {
    var pulled: [String] = []
    var pushed: [String] = []
    var removedHere: [String] = []
    var removedThere: [String] = []
    var conflicts: [String] = []
    var deferred: [String] = []
    /// Local changes left unpushed because the round failed.
    var pendingLocal = 0
    var error: SyncError? = nil

    var changedLibrary: Bool { !pulled.isEmpty || !removedHere.isEmpty || !conflicts.isEmpty }
    var quiet: Bool { pulled.isEmpty && pushed.isEmpty && removedHere.isEmpty && removedThere.isEmpty && conflicts.isEmpty }
}

/// One round: snapshot the library, read the remote, merge three ways,
/// write what came, push what went, remember where things stand.
final class SyncRun {
    let remote: SyncRemote
    let root: URL
    let stateURL: URL
    /// A path the editor is in the middle of — left alone this round.
    let busy: String?
    let host: String
    var log: ((String) -> Void)?

    private var state: SyncState
    private var hashCache: [String: (modified: Date, size: Int, sha: String)]

    init(remote: SyncRemote, root: URL, stateURL: URL, busy: String?, host: String,
         hashCache: [String: (modified: Date, size: Int, sha: String)] = [:]) {
        self.remote = remote
        self.root = root
        self.stateURL = stateURL
        self.busy = busy
        self.host = host
        self.state = SyncState.load(from: stateURL)
        self.hashCache = hashCache
    }

    var cache: [String: (modified: Date, size: Int, sha: String)] { hashCache }

    /// Paths the sync carries: the library's documents, nothing hidden.
    static func carries(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let last = parts.last, !parts.contains(where: { $0.hasPrefix(".") }) else { return false }
        let ext = (last as NSString).pathExtension.lowercased()
        return LibraryStore.extensions.contains(ext)
    }

    private struct LocalFile {
        let url: URL
        let sha: String
    }

    /// Every document on disk with its blob id; iCloud files not yet
    /// downloaded are asked for and left out of this round entirely.
    private func snapshot() throws -> (files: [String: LocalFile], skipped: Set<String>) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .nameKey, .contentModificationDateKey, .fileSizeKey, .fileAllocatedSizeKey, .ubiquitousItemDownloadingStatusKey]
        var files: [String: LocalFile] = [:]
        var skipped = Set<String>()
        func walk(_ dir: URL, rel: String) {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for item in items {
                let v = try? item.resourceValues(forKeys: keys)
                let name = v?.name ?? item.lastPathComponent
                if name.hasPrefix(".") || v?.isSymbolicLink == true { continue }
                let childRel = rel.isEmpty ? name : rel + "/" + name
                if v?.isDirectory == true { walk(item, rel: childRel); continue }
                guard SyncRun.carries(childRel) else { continue }
                let size = v?.fileSize ?? 0
                if let status = v?.ubiquitousItemDownloadingStatus, status != .current {
                    try? fm.startDownloadingUbiquitousItem(at: item)
                    skipped.insert(childRel)
                    continue
                }
                if size > 0, (v?.fileAllocatedSize ?? size) == 0 {
                    try? fm.startDownloadingUbiquitousItem(at: item)
                    skipped.insert(childRel)
                    continue
                }
                let modified = v?.contentModificationDate ?? .distantPast
                if let cached = hashCache[childRel], cached.modified == modified, cached.size == size {
                    files[childRel] = LocalFile(url: item, sha: cached.sha)
                    continue
                }
                guard let data = try? Data(contentsOf: item) else { skipped.insert(childRel); continue }
                let sha = GitBlob.sha(of: data)
                hashCache[childRel] = (modified, size, sha)
                files[childRel] = LocalFile(url: item, sha: sha)
            }
        }
        walk(root, rel: "")
        return (files, skipped)
    }

    private func write(_ data: Data, to rel: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do {
                let created = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.creationDate] as? Date
                try data.write(to: u, options: .atomic)
                if let created {
                    var keep = URL(fileURLWithPath: u.path)
                    var values = URLResourceValues()
                    values.creationDate = created
                    try? keep.setResourceValues(values)
                }
            } catch {
                writeError = error
            }
        }
        if let e = coordError { throw e }
        if let e = writeError { throw e }
        // The file is what the remote holds now; no need to hash it again.
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        hashCache[rel] = (v?.contentModificationDate ?? .distantPast, v?.fileSize ?? data.count, GitBlob.sha(of: data))
    }

    private func remove(_ rel: String) throws {
        let url = root.appendingPathComponent(rel)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try FileManager.default.removeItem(at: url)
        }
        hashCache.removeValue(forKey: rel)
    }

    /// "Name (conflict).md" beside `rel`, or "(conflict 2)" and so on.
    private func conflictPath(for rel: String) -> String {
        let url = root.appendingPathComponent(rel)
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        while true {
            let candidate = dir.appendingPathComponent(n == 1 ? "\(stem) (conflict)" : "\(stem) (conflict \(n))").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate.pathRelative(to: root) }
            n += 1
        }
    }

    private static func summary(_ out: SyncOutcome) -> String {
        func list(_ verb: String, _ paths: [String]) -> String? {
            guard !paths.isEmpty else { return nil }
            let names = paths.prefix(4).map { ($0 as NSString).lastPathComponent }
            let more = paths.count > 4 ? " and \(paths.count - 4) more" : ""
            return "\(verb) \(names.joined(separator: ", "))\(more)"
        }
        let parts = [list("edited", out.pushed), list("removed", out.removedThere)].compactMap { $0 }
        return parts.isEmpty ? "no changes" : parts.joined(separator: "; ")
    }

    func run() async -> SyncOutcome {
        var out = SyncOutcome()
        do {
            for attempt in 1...3 {
                out = SyncOutcome()
                let (local, skipped) = try snapshot()
                let head = try await remote.head()
                let remoteFiles: [String: String]
                if let head, head.commit == state.head, head.tree == state.tree {
                    remoteFiles = state.files
                } else if let head {
                    remoteFiles = try await remote.tree(head.tree).filter { SyncRun.carries($0.key) }
                } else {
                    remoteFiles = [:]
                }
                log?("round \(attempt): \(local.count) local, \(remoteFiles.count) remote, head \(head?.commit.prefix(7) ?? "none")")

                var next = state.files
                var writes: [String: Data] = [:]
                var pushSHAs: [String: String] = [:]
                var deletesThere: [String] = []
                var pulls: [(path: String, sha: String)] = []
                var removals: [String] = []
                var conflicts: [(path: String, sha: String)] = []

                let paths = Set(local.keys).union(remoteFiles.keys).union(state.files.keys).subtracting(skipped)
                for p in paths.sorted() {
                    let L = local[p]?.sha, R = remoteFiles[p], B = state.files[p]
                    if L == R {
                        if let L { next[p] = L } else { next.removeValue(forKey: p) }
                    } else if L == B {
                        // Untouched here since last time: take what the remote did.
                        if p == busy { out.deferred.append(p); continue }
                        if let R { pulls.append((p, R)) } else { removals.append(p) }
                    } else if R == B {
                        // Untouched there: send what happened here.
                        if let L, let file = local[p] {
                            guard let data = try? Data(contentsOf: file.url) else { continue }
                            writes[p] = data
                            pushSHAs[p] = L
                        } else {
                            deletesThere.append(p)
                        }
                    } else {
                        // Changed on both sides.
                        if p == busy { out.deferred.append(p); continue }
                        if let L, let R, let file = local[p] {
                            guard let data = try? Data(contentsOf: file.url) else { continue }
                            conflicts.append((p, R))
                            writes[p] = data
                            pushSHAs[p] = L
                        } else if let L, let file = local[p] {
                            // Removed there, edited here: what was written stays.
                            guard let data = try? Data(contentsOf: file.url) else { continue }
                            writes[p] = data
                            pushSHAs[p] = L
                        } else if let R {
                            // Removed here, edited there: the edit comes back.
                            pulls.append((p, R))
                        }
                    }
                }

                // What came from the remote — and, for a conflict, the remote
                // version beside the local one under a name of its own.
                for (p, sha) in pulls {
                    let data = try await remote.blob(sha)
                    try write(data, to: p)
                    next[p] = sha
                    out.pulled.append(p)
                }
                for (p, sha) in conflicts {
                    let data = try await remote.blob(sha)
                    let copy = conflictPath(for: p)
                    try write(data, to: copy)
                    writes[copy] = data
                    pushSHAs[copy] = GitBlob.sha(of: data)
                    next[p] = pushSHAs[p]
                    out.conflicts.append(p)
                }
                for p in removals {
                    try remove(p)
                    next.removeValue(forKey: p)
                    out.removedHere.append(p)
                }

                out.pushed = writes.keys.sorted()
                out.removedThere = deletesThere.sorted()
                out.pendingLocal = writes.count + deletesThere.count
                var newHead = head
                if !writes.isEmpty || !deletesThere.isEmpty {
                    let message = "Glassine on \(host): \(SyncRun.summary(out))"
                    do {
                        newHead = try await remote.push(base: head, writes: writes, deletes: deletesThere, message: message)
                    } catch SyncError.notFastForward {
                        log?("not fast-forward; again")
                        // Keep what was pulled and removed, so the next attempt
                        // starts from it; a conflict's remote version counts as
                        // seen, so the copy beside the file is not made twice.
                        state.files = next
                        for (p, sha) in conflicts { state.files[p] = sha }
                        if attempt == 3 { throw SyncError.notFastForward }
                        continue
                    }
                    for (p, sha) in pushSHAs { next[p] = sha }
                    for p in deletesThere { next.removeValue(forKey: p) }
                    out.pendingLocal = 0
                }
                // A deferred path is still behind the remote, so the head is
                // not marked as seen: the next round reads the tree again.
                state.head = out.deferred.isEmpty ? newHead?.commit : nil
                state.tree = out.deferred.isEmpty ? newHead?.tree : nil
                state.files = next
                state.save(to: stateURL)
                log?("done: pulled \(out.pulled.count), pushed \(out.pushed.count), removed here \(out.removedHere.count), there \(out.removedThere.count), conflicts \(out.conflicts.count), deferred \(out.deferred.count)")
                return out
            }
        } catch let e as SyncError {
            out.error = e
        } catch {
            out.error = .other(error.localizedDescription)
        }
        log?("failed: \(out.error?.errorDescription ?? "?")")
        return out
    }
}

// MARK: - The engine

/// Owns the connection and the schedule: a round soon after every save, one
/// every half minute while the app is active, one on coming to the front,
/// one when asked. Rounds never overlap; a round asked for during a round
/// runs right after it. Published state changes on the main thread; the
/// rounds run on a background task.
final class SyncEngine: ObservableObject {
    enum Status: Equatable {
        case off
        case syncing
        case upToDate(Date)
        case offline(Date?)
        case failed(String)
    }

    @Published private(set) var status: Status = .off
    /// The last round's story, when it had one: what was kept both ways.
    @Published private(set) var note: String?
    @Published private(set) var pending = 0
    @Published private(set) var lastSync: Date?

    private(set) var library: LibraryStore
    private let settings: AppSettings
    private var remote: SyncRemote?
    private var api: GitHubAPI?

    /// The document being edited right now, when it has unsaved changes.
    var busyPath: (() -> String?)?
    /// The library changed underneath the app.
    var libraryChanged: (() -> Void)?

    private var running = false
    private var runAgain = false
    private var timer: Timer?
    private let soon = Debouncer(delay: 3)
    private var hashCache: [String: (modified: Date, size: Int, sha: String)] = [:]
    private var observers: [NSObjectProtocol] = []

    var repository: String? { settings.data.syncRepository }
    var branch: String { settings.data.syncBranch }
    var isConnected: Bool { remote != nil }
    var canSignIn: Bool { !GitHubAPI.clientID.isEmpty }

    init(library: LibraryStore, settings: AppSettings) {
        self.library = library
        self.settings = settings
    }

    /// Picks up a connection made on an earlier run.
    func start() {
        // A check shot of the connected state, through a folder standing in
        // for the repository: `-glassine.syncDemo <folder>` with -glassine.shoot.
        if ScreenshotMode.isActive, let folder = UserDefaults.standard.string(forKey: "glassine.syncDemo") {
            settings.data.syncRepository = "alex/notes"
            settings.data.syncLogin = "alex"
            attach(remote: FolderRemote(root: URL(fileURLWithPath: folder, isDirectory: true)))
            sync()
            return
        }
        guard let repo = settings.data.syncRepository, let token = SyncKeychain.token() else { return }
        attach(token: token, repo: repo, branch: settings.data.syncBranch)
        sync()
    }

    private func attach(token: String, repo: String, branch: String) {
        let api = GitHubAPI(token: token)
        self.api = api
        remote = GitHubRemote(api: api, repo: repo, branch: branch)
        status = .upToDate(lastSync ?? .distantPast)
        startListening()
    }

    /// The remote, for a test through a folder instead of GitHub.
    func attach(remote: SyncRemote) {
        self.remote = remote
        status = .upToDate(.distantPast)
        startListening()
    }

    private func startListening() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .glassineDocumentSaved, object: nil, queue: .main) { [weak self] _ in
            self?.syncSoon()
        })
        observers.append(nc.addObserver(forName: .glassineLibraryMutated, object: nil, queue: .main) { [weak self] _ in
            self?.syncSoon()
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard NSApp.isActive else { return }
            self?.sync()
        }
    }

    private func stopListening() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        timer?.invalidate()
        timer = nil
    }

    // MARK: Connecting

    /// Signs in with a pasted token and a repository name.
    @MainActor
    func connect(repository: String, token: String) async throws {
        let api = GitHubAPI(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        let name = repository.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard name.split(separator: "/").count == 2 else { throw SyncError.other("Name the repository as owner/name — for example alex/notes.") }
        let repo = try await api.repository(name)
        guard repo.canPush else { throw SyncError.other("The token can read \(repo.fullName) but not write to it. It needs Contents: read and write.") }
        SyncKeychain.store(api.token)
        settings.data.syncRepository = repo.fullName
        settings.data.syncBranch = repo.defaultBranch
        settings.data.syncLogin = (try? await api.login()) ?? String(repo.fullName.split(separator: "/").first ?? "")
        attach(token: api.token, repo: repo.fullName, branch: repo.defaultBranch)
        sync()
    }

    /// Starts the sign-in without a token to paste: a code for github.com.
    func beginSignIn() async throws -> GitHubAPI.DeviceCode {
        try await GitHubAPI.requestDeviceCode()
    }

    /// Waits for the code to be entered; keeps the token; the login it belongs to.
    @MainActor
    func finishSignIn(_ code: GitHubAPI.DeviceCode) async throws -> String {
        let token = try await GitHubAPI.waitForToken(code)
        let api = GitHubAPI(token: token)
        let login = try await api.login()
        SyncKeychain.store(token)
        settings.data.syncLogin = login
        self.api = api
        return login
    }

    /// After a sign-in: the repositories to choose from.
    @MainActor
    func repositories() async throws -> [GitHubAPI.Repository] {
        guard let api = api ?? SyncKeychain.token().map({ GitHubAPI(token: $0) }) else { throw SyncError.unauthorized }
        self.api = api
        return try await api.repositories()
    }

    /// After a sign-in: a new private repository, then the connection to it.
    @MainActor
    func createAndUse(repositoryNamed name: String) async throws {
        guard let api else { throw SyncError.unauthorized }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw SyncError.other("Give the repository a name.") }
        let repo = try await api.createRepository(named: clean)
        try await use(repositoryNamed: repo.fullName)
    }

    /// After a sign-in: the connection to one of the user's repositories.
    @MainActor
    func use(repositoryNamed fullName: String) async throws {
        guard let api else { throw SyncError.unauthorized }
        let repo = try await api.repository(fullName)
        guard repo.canPush else { throw SyncError.other("You can read \(repo.fullName) but not write to it.") }
        settings.data.syncRepository = repo.fullName
        settings.data.syncBranch = repo.defaultBranch
        attach(token: api.token, repo: repo.fullName, branch: repo.defaultBranch)
        sync()
    }

    /// Forgets the token and the repository; the documents stay.
    func disconnect() {
        stopListening()
        remote = nil
        api = nil
        SyncKeychain.forget()
        settings.data.syncRepository = nil
        settings.data.syncLogin = nil
        settings.data.syncBranch = "main"
        status = .off
        note = nil
        pending = 0
        hashCache = [:]
    }

    /// The library moved: whatever was connected was for the old one.
    func libraryDidChange(to library: LibraryStore) {
        let wasConnected = isConnected
        self.library = library
        hashCache = [:]
        if wasConnected {
            disconnect()
            note = "Sync was turned off when the library moved. Connect it again from here."
        }
    }

    // MARK: Running

    /// The state file for this repository and library, in Application Support.
    private var stateURL: URL {
        let key = Insecure.SHA1.hash(data: Data("\(remote?.name ?? "")\n\(library.rootURL.path)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Glassine/Sync/\(key).json")
    }

    func syncSoon() {
        guard isConnected else { return }
        soon.call { [weak self] in self?.sync() }
    }

    func sync() {
        guard let remote else { return }
        if running { runAgain = true; return }
        running = true
        if case .syncing = status {} else { status = .syncing }
        let run = SyncRun(remote: remote, root: library.rootURL, stateURL: stateURL, busy: busyPath?(),
                          host: Host.current().localizedName ?? "a Mac", hashCache: hashCache)
        run.log = { line in ScreenshotMode.note("sync: " + line) }
        Task.detached(priority: .utility) { [weak self] in
            let outcome = await run.run()
            let cache = run.cache
            DispatchQueue.main.async { self?.finish(outcome, cache: cache) }
        }
    }

    private func finish(_ out: SyncOutcome, cache: [String: (modified: Date, size: Int, sha: String)]) {
        running = false
        hashCache = cache
        if let error = out.error {
            pending = out.pendingLocal
            if error.isOffline {
                status = .offline(lastSync)
            } else {
                status = .failed(error.errorDescription ?? "Sync failed.")
            }
        } else {
            pending = 0
            lastSync = Date()
            status = .upToDate(lastSync!)
            if !out.conflicts.isEmpty {
                let names = out.conflicts.prefix(3).map { ($0 as NSString).deletingPathExtension }
                note = "Both Macs changed \(names.joined(separator: ", ")); both versions are kept, the other as “(conflict)”."
            } else if out.changedLibrary {
                note = nil
            }
        }
        if out.changedLibrary { libraryChanged?() }
        if runAgain || !out.deferred.isEmpty {
            runAgain = false
            soon.call { [weak self] in self?.sync() }
        }
    }

    // MARK: Words

    /// The status as a line for the footer and the settings.
    var statusText: String {
        switch status {
        case .off: return "Off"
        case .syncing: return "Syncing…"
        case .upToDate(let when): return "Up to date · \(SyncEngine.ago(when))"
        case .offline(let last):
            let waiting = pending > 0 ? " — \(pending) change\(pending == 1 ? "" : "s") waiting" : ""
            return "Offline\(waiting)" + (last.map { " · last synced \(SyncEngine.ago($0))" } ?? "")
        case .failed(let message): return message
        }
    }

    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if date == .distantPast { return "not yet" }
        if s < 5 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    // MARK: Headless test

    /// `-glassine.syncTest <library folder> -glassine.syncFolder <remote folder>`:
    /// one round between a library and a folder standing in for the
    /// repository, then exit. The round's log goes to the remote folder as
    /// log.txt. Two libraries taking turns through one folder exercise the
    /// merge — adds, edits, removals, conflicts — with no network and no token.
    static func runHeadlessTestIfRequested() -> Bool {
        let defaults = UserDefaults.standard
        guard let lib = defaults.string(forKey: "glassine.syncTest"), let folder = defaults.string(forKey: "glassine.syncFolder") else { return false }
        let root = URL(fileURLWithPath: lib, isDirectory: true)
        let remoteURL = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: remoteURL, withIntermediateDirectories: true)
        let logURL = remoteURL.appendingPathComponent("log.txt")
        var lines: [String] = []
        let stateURL = remoteURL.appendingPathComponent("state-\(root.lastPathComponent).json")
        let run = SyncRun(remote: FolderRemote(root: remoteURL), root: root, stateURL: stateURL,
                          busy: defaults.string(forKey: "glassine.syncBusy"), host: "test")
        run.log = { lines.append($0) }
        Task.detached {
            let out = await run.run()
            lines.append("outcome: pulled=\(out.pulled) pushed=\(out.pushed) removedHere=\(out.removedHere) removedThere=\(out.removedThere) conflicts=\(out.conflicts) deferred=\(out.deferred) error=\(out.error?.errorDescription ?? "none")")
            try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: logURL)
            exit(out.error == nil ? 0 : 1)
        }
        return true
    }
}

extension Notification.Name {
    /// A document's text reached the disk.
    static let glassineDocumentSaved = Notification.Name("ink.glassine.documentSaved")
    /// A file or folder in the library was made, renamed, moved or trashed.
    static let glassineLibraryMutated = Notification.Name("ink.glassine.libraryMutated")
}
