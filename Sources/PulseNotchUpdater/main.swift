import Darwin
import Foundation

// This executable is outside the app's lifetime so Homebrew can replace the bundle.
guard CommandLine.arguments.count == 5,
      let pid = Int32(CommandLine.arguments[1]), pid > 0 else {
    exit(2)
}

let brew = URL(fileURLWithPath: CommandLine.arguments[2])
let app = URL(fileURLWithPath: CommandLine.arguments[3])
let result = URL(fileURLWithPath: CommandLine.arguments[4])

func run(_ executable: URL, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw UpdateError.commandFailed }
}

enum UpdateError: Error { case commandFailed }

let deadline = Date().addingTimeInterval(60)
while kill(pid, 0) == 0 {
    guard Date() < deadline else {
        try? "failed".write(to: result, atomically: true, encoding: .utf8)
        exit(1)
    }
    Thread.sleep(forTimeInterval: 0.25)
}

do {
    try run(brew, ["update"])
    try run(brew, ["upgrade", "--cask", "pulse-notch"])
    try "success".write(to: result, atomically: true, encoding: .utf8)
} catch {
    try? "failed".write(to: result, atomically: true, encoding: .utf8)
}

try? run(URL(fileURLWithPath: "/usr/bin/open"), [app.path])
