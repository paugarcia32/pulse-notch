import Foundation

let data = FileHandle.standardInput.readDataToEndOfFile()

if
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let rateLimits = object["rate_limits"],
    let snapshotData = try? JSONSerialization.data(
        withJSONObject: ["rate_limits": rateLimits]
    )
{
    let snapshotURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/pulse-notch-usage.json")
    do {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try snapshotData.write(to: snapshotURL, options: .atomic)
    } catch {
        FileHandle.standardError.write(
            Data("Pulse Notch could not record Claude usage: \(error.localizedDescription)\n".utf8)
        )
    }
}
