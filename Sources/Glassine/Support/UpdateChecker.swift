import AppKit

/// Checks GitHub Releases for a newer version. Deliberately simple: no
/// framework, no background downloads — just a polite alert with a link.
enum UpdateChecker {
    static let repository = "a-libre/glassine"
    static let releasesPage = URL(string: "https://github.com/a-libre/glassine/releases/latest")!
    private static let lastCheckKey = "glassine.updates.lastCheck"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Once a day at most, quietly.
    static func checkAutomaticallyIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        check(userInitiated: false)
    }

    static func check(userInitiated: Bool) {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Glassine/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, status == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if userInitiated {
                        let reason = error?.localizedDescription
                            ?? (status == 404 ? "No releases have been published yet." : "GitHub returned status \(status).")
                        alert(title: "Couldn't check for updates", message: reason, buttons: ["OK"])
                    }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
                if isVersion(latest, newerThan: currentVersion) {
                    let choice = alert(
                        title: "Glassine \(latest) is available",
                        message: "You have \(currentVersion). The new version is on GitHub — download the disk image, drag Glassine to Applications, and you're done.",
                        buttons: ["Download", "Later"]
                    )
                    if choice == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
                } else if userInitiated {
                    alert(title: "You're up to date", message: "Glassine \(currentVersion) is the latest version.", buttons: ["OK"])
                }
            }
        }.resume()
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @discardableResult
    private static func alert(title: String, message: String, buttons: [String]) -> NSApplication.ModalResponse {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .informational
        for b in buttons { a.addButton(withTitle: b) }
        return a.runModal()
    }
}
