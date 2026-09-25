import Carbon.HIToolbox
import CoreGraphics
import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

enum ComputerUseTests {
    struct KeyCodeMapTests {
        @Test
        func mapsLettersAndDigitsCaseInsensitively() {
            #expect(KeyCodeMap.keyCode(for: "a") == CGKeyCode(kVK_ANSI_A))
            #expect(KeyCodeMap.keyCode(for: "Z") == CGKeyCode(kVK_ANSI_Z))
            #expect(KeyCodeMap.keyCode(for: "0") == CGKeyCode(kVK_ANSI_0))
            #expect(KeyCodeMap.keyCode(for: "9") == CGKeyCode(kVK_ANSI_9))
        }

        @Test
        func mapsNamedKeysAndAliases() {
            #expect(KeyCodeMap.keyCode(for: "return") == CGKeyCode(kVK_Return))
            #expect(KeyCodeMap.keyCode(for: "Enter") == CGKeyCode(kVK_Return))
            #expect(KeyCodeMap.keyCode(for: "esc") == CGKeyCode(kVK_Escape))
            #expect(KeyCodeMap.keyCode(for: "backspace") == CGKeyCode(kVK_Delete))
            #expect(KeyCodeMap.keyCode(for: "forwardDelete") == CGKeyCode(kVK_ForwardDelete))
            #expect(KeyCodeMap.keyCode(for: "page down") == CGKeyCode(kVK_PageDown))
            #expect(KeyCodeMap.keyCode(for: "left") == CGKeyCode(kVK_LeftArrow))
            #expect(KeyCodeMap.keyCode(for: "space") == CGKeyCode(kVK_Space))
            #expect(KeyCodeMap.keyCode(for: " ") == CGKeyCode(kVK_Space))
            #expect(KeyCodeMap.keyCode(for: "F12") == CGKeyCode(kVK_F12))
        }

        @Test
        func mapsPunctuation() {
            #expect(KeyCodeMap.keyCode(for: ",") == CGKeyCode(kVK_ANSI_Comma))
            #expect(KeyCodeMap.keyCode(for: "-") == CGKeyCode(kVK_ANSI_Minus))
            #expect(KeyCodeMap.keyCode(for: "`") == CGKeyCode(kVK_ANSI_Grave))
            #expect(KeyCodeMap.keyCode(for: "]") == CGKeyCode(kVK_ANSI_RightBracket))
        }

        @Test
        func rejectsUnknownKeys() {
            #expect(KeyCodeMap.keyCode(for: "hyper") == nil)
            #expect(KeyCodeMap.keyCode(for: "f13") == nil)
            #expect(KeyCodeMap.keyCode(for: "") == nil)
            #expect(KeyCodeMap.keyCode(for: "é") == nil)
        }

        @Test
        func mapsModifiersToEventFlags() {
            #expect(KeyCodeMap.flags(for: []) == [])
            #expect(KeyCodeMap.flags(for: [.command, .shift]) == [.maskCommand, .maskShift])
            #expect(KeyCodeMap.flags(for: [.option, .control]) == [.maskAlternate, .maskControl])
        }
    }

    struct ElementIdentityTests {
        @Test
        func identifierIsDeterministicAndShort() {
            let first = ElementIdentity.id(path: [0, 3, 1], role: "AXButton")
            let second = ElementIdentity.id(path: [0, 3, 1], role: "AXButton")
            #expect(first == second)
            #expect(first.count == 7)
            #expect(first.hasPrefix("e"))
            #expect(first.dropFirst().allSatisfy { $0.isNumber || ("a"..."z").contains(String($0)) })
        }

        @Test
        func identifierDiffersByPathAndRole() {
            let button = ElementIdentity.id(path: [0, 3, 1], role: "AXButton")
            #expect(button != ElementIdentity.id(path: [0, 3, 2], role: "AXButton"))
            #expect(button != ElementIdentity.id(path: [0, 31], role: "AXButton"))
            #expect(button != ElementIdentity.id(path: [0, 3, 1], role: "AXLink"))
        }

        @Test
        func uniqueIdentifierAvoidsTakenTokensDeterministically() {
            let base = ElementIdentity.id(path: [2], role: "AXButton")
            let taken: Set = [base]
            let resolved = ElementIdentity.uniqueID(path: [2], role: "AXButton", isTaken: taken.contains)
            #expect(resolved != base)
            #expect(resolved == ElementIdentity.uniqueID(path: [2], role: "AXButton", isTaken: taken.contains))
            #expect(ElementIdentity.uniqueID(path: [2], role: "AXButton", isTaken: { _ in false }) == base)
        }

        @Test
        func fnv1aMatchesReferenceVector() {
            #expect(ElementIdentity.fnv1a("") == 0xcbf2_9ce4_8422_2325)
            #expect(ElementIdentity.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
        }
    }

    struct CoordinateConversionTests {
        // Primary display 1512×982 at the origin; a 1920×1080 display to its right,
        // aligned to the primary's bottom edge in AppKit coordinates.
        private let conversion = CoordinateConversion(primaryScreenHeight: 982)

        @Test
        func primaryDisplayMapsToOriginInBothSystems() {
            let appKit = CGRect(x: 0, y: 0, width: 1512, height: 982)
            let global = conversion.globalTopLeft(fromAppKit: appKit)
            #expect(global == ScreenRect(x: 0, y: 0, width: 1512, height: 982))
            #expect(conversion.appKit(fromGlobalTopLeft: global) == appKit)
        }

        @Test
        func secondaryDisplayFlipsAroundPrimaryHeight() {
            let appKit = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
            let global = conversion.globalTopLeft(fromAppKit: appKit)
            #expect(global == ScreenRect(x: 1512, y: -98, width: 1920, height: 1080))
            #expect(conversion.appKit(fromGlobalTopLeft: global) == appKit)
        }

        @Test
        func pointsRoundTrip() {
            let appKitPoint = CGPoint(x: 2000, y: 1050)
            let global = conversion.globalTopLeft(fromAppKit: appKitPoint)
            #expect(global == CGPoint(x: 2000, y: -68))
            #expect(conversion.appKit(fromGlobalTopLeft: global) == appKitPoint)
        }

        @Test
        func layoutFindsDisplayContainingPoint() {
            let layout = DisplayLayout(displays: [
                DisplaySnapshot(id: 1, frame: ScreenRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2),
                DisplaySnapshot(id: 2, frame: ScreenRect(x: 1512, y: -98, width: 1920, height: 1080), backingScale: 1)
            ])
            #expect(layout.display(containingX: 100, y: 100)?.id == 1)
            #expect(layout.display(containingX: 2000, y: -50)?.id == 2)
            #expect(layout.display(containingX: 100, y: -50) == nil)
            #expect(layout.primary?.id == 1)
        }
    }

    struct ScreenshotScalingTests {
        @Test
        func capsLongEdgeAndKeepsAspectRatio() {
            let size = ScreenshotScaling.pixelSize(pointWidth: 1512, pointHeight: 982, backingScale: 2)
            #expect(size.width == 1600)
            #expect(size.height == 1039)
        }

        @Test
        func capsPortraitDisplaysOnHeight() {
            let size = ScreenshotScaling.pixelSize(pointWidth: 1080, pointHeight: 1920, backingScale: 1)
            #expect(size == ScreenshotScaling.PixelSize(width: 900, height: 1600))
        }

        @Test
        func keepsNativeSizeBelowCap() {
            let size = ScreenshotScaling.pixelSize(pointWidth: 1280, pointHeight: 800, backingScale: 1)
            #expect(size == ScreenshotScaling.PixelSize(width: 1280, height: 800))
        }
    }

    struct ApplicationLocatorTests {
        private let first = URL(filePath: "/Fixture/Applications", directoryHint: .isDirectory)
        private let second = URL(filePath: "/Fixture/System/Applications", directoryHint: .isDirectory)

        private func locator(files: [URL: [String]]) -> ApplicationLocator {
            ApplicationLocator(
                searchDirectories: [first, second],
                fileExists: { url in
                    files[url.deletingLastPathComponent()]?.contains(url.lastPathComponent) ?? false
                },
                directoryContents: { files[$0] ?? [] }
            )
        }

        @Test
        func returnsCandidatesInSearchDirectoryOrder() {
            let locator = locator(files: [first: ["Notes.app"], second: ["Notes.app", "Mail.app"]])
            let candidates = locator.candidates(forApplicationNamed: "Notes")
            #expect(candidates.map(\.path) == ["/Fixture/Applications/Notes.app", "/Fixture/System/Applications/Notes.app"])
        }

        @Test
        func matchesNamesCaseInsensitivelyWithRealBundleName() {
            let locator = locator(files: [second: ["Safari.app"]])
            #expect(locator.candidates(forApplicationNamed: "safari").map(\.path) == ["/Fixture/System/Applications/Safari.app"])
            #expect(locator.candidates(forApplicationNamed: "SAFARI.APP").map(\.lastPathComponent) == ["Safari.app"])
        }

        @Test
        func rejectsNamesThatEscapeSearchDirectories() {
            let locator = locator(files: [first: ["Notes.app"]])
            #expect(locator.candidates(forApplicationNamed: "../Notes").isEmpty)
            #expect(locator.candidates(forApplicationNamed: "   ").isEmpty)
            #expect(locator.candidates(forApplicationNamed: "Missing").isEmpty)
        }

        @Test
        func recognizesBundleIdentifiers() {
            #expect(ApplicationLocator.looksLikeBundleIdentifier("com.apple.Safari"))
            #expect(ApplicationLocator.looksLikeBundleIdentifier("com.microsoft.VSCode"))
            #expect(!ApplicationLocator.looksLikeBundleIdentifier("Visual Studio Code"))
            #expect(!ApplicationLocator.looksLikeBundleIdentifier("Safari"))
            #expect(!ApplicationLocator.looksLikeBundleIdentifier("Safari.app"))
            #expect(!ApplicationLocator.looksLikeBundleIdentifier("com..apple"))
        }
    }

    struct AccessibleRoleFilterTests {
        @Test
        func keepsActionableRolesEvenWithoutLabel() {
            for role in ["AXButton", "AXTextField", "AXCheckBox", "AXPopUpButton", "AXLink", "AXSlider"] {
                #expect(AccessibleRoleFilter.keeps(role: role, label: ""))
            }
        }

        @Test
        func keepsStructuralAndTextRolesOnlyWithLabel() {
            #expect(!AccessibleRoleFilter.keeps(role: "AXStaticText", label: ""))
            #expect(AccessibleRoleFilter.keeps(role: "AXStaticText", label: "Inbox"))
            #expect(!AccessibleRoleFilter.keeps(role: "AXRow", label: ""))
            #expect(AccessibleRoleFilter.keeps(role: "AXCell", label: "Today"))
        }

        @Test
        func dropsContainerRoles() {
            #expect(!AccessibleRoleFilter.isCandidate(role: "AXGroup"))
            #expect(!AccessibleRoleFilter.keeps(role: "AXScrollArea", label: "Content"))
        }

        @Test
        func detectsSecureFieldsByRoleOrSubrole() {
            #expect(AccessibleRoleFilter.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
            #expect(AccessibleRoleFilter.isSecure(role: "AXSecureTextField", subrole: nil))
            #expect(!AccessibleRoleFilter.isSecure(role: "AXTextField", subrole: "AXSearchField"))
        }

        @Test
        func secureElementsNeverCarryValues() {
            let element = AccessibleElement(id: "e1", role: "AXSecureTextField", label: "Password", value: "hunter2", isSecure: true)
            #expect(element.value == nil)
        }

        @Test
        func labelUsesFirstNonEmptyCandidateAndTruncates() {
            #expect(AccessibleLabel.first(of: [nil, "  ", "Save", "Help"]) == "Save")
            #expect(AccessibleLabel.first(of: [nil, ""]) == "")
            let long = String(repeating: "x", count: 300)
            #expect(AccessibleLabel.first(of: [long]).count == AccessibleLabel.maximumLabelLength + 1)
        }

        @Test
        func windowMatcherRequiresUnambiguousMatch() {
            let frame = ScreenRect(x: 10, y: 20, width: 800, height: 600)
            let candidates = [
                WindowCandidate(id: 1, frame: ScreenRect(x: 11, y: 20, width: 800, height: 600), title: "Draft"),
                WindowCandidate(id: 2, frame: ScreenRect(x: 400, y: 20, width: 800, height: 600), title: "Other")
            ]
            #expect(WindowMatcher.match(candidates, frame: frame, title: nil) == 1)
            let twins = candidates + [WindowCandidate(id: 3, frame: frame, title: "Notes")]
            #expect(WindowMatcher.match(twins, frame: frame, title: "Notes") == 3)
            #expect(WindowMatcher.match(twins, frame: frame, title: nil) == nil)
        }
    }

    struct InputPlanningTests {
        @Test
        func chunksTextWithoutSplittingGraphemes() {
            let text = String(repeating: "a", count: 19) + "👍🏽" + "bc"
            let chunks = TextChunking.chunks(of: text)
            #expect(chunks.count == 2)
            #expect(chunks[0].count == 19)
            #expect(String(utf16CodeUnits: chunks[1], count: chunks[1].count) == "👍🏽bc")
            #expect(chunks.allSatisfy { $0.count <= TextChunking.maximumUTF16Units })
            #expect(TextChunking.chunks(of: "").isEmpty)
        }

        @Test
        func scrollDeltasFollowQuartzSignsAndClamp() {
            #expect(ScrollDeltas.lines(for: .up, amount: 3) == (3, 0))
            #expect(ScrollDeltas.lines(for: .down, amount: 3) == (-3, 0))
            #expect(ScrollDeltas.lines(for: .left, amount: 0) == (0, 1))
            #expect(ScrollDeltas.lines(for: .right, amount: 500) == (0, -50))
        }
    }

    struct DesktopAvailabilityStateTests {
        @Test
        func availableOnlyWhenNothingBlocks() {
            var state = DesktopAvailabilityState()
            #expect(state.isAvailable)
            state.apply(.screenLocked)
            #expect(!state.isAvailable)
            state.apply(.composerFocusChanged(true))
            state.apply(.screenUnlocked)
            #expect(!state.isAvailable)
            state.apply(.composerFocusChanged(false))
            #expect(state.isAvailable)
        }

        @Test
        func sleepTransitionsTrackSystemAndDisplays() {
            var state = DesktopAvailabilityState()
            state.apply(.displaysDidSleep)
            #expect(state.asleep)
            state.apply(.displaysDidWake)
            #expect(state.isAvailable)
            state.apply(.systemWillSleep)
            state.apply(.displaysDidSleep)
            state.apply(.systemDidWake)
            #expect(!state.asleep)
            #expect(state.isAvailable)
        }

        @Test
        func inactiveSessionBlocksInput() {
            var state = DesktopAvailabilityState()
            state.apply(.sessionDidResignActive)
            #expect(!state.isAvailable)
            state.apply(.sessionDidBecomeActive)
            #expect(state.isAvailable)
        }
    }

    struct DesktopSessionMonitorTests {
        private func waitForWaiters(_ monitor: DesktopSessionMonitor, count: Int) async -> Bool {
            for _ in 0..<10_000 {
                if await monitor.pendingWaiterCount == count { return true }
                await Task.yield()
            }
            return false
        }

        @Test
        func returnsImmediatelyWhenAvailable() async throws {
            let monitor = DesktopSessionMonitor(initialState: DesktopAvailabilityState())
            try await monitor.waitUntilAvailable()
            #expect(await monitor.isAvailable)
        }

        @Test
        func suspendsWhileComposerFocusedAndResumesWhenCleared() async throws {
            let monitor = DesktopSessionMonitor(initialState: DesktopAvailabilityState(composerFocused: true))
            let waiter = Task { try await monitor.waitUntilAvailable() }

            #expect(await waitForWaiters(monitor, count: 1))
            await monitor.apply(.screenLocked)
            await monitor.apply(.composerFocusChanged(false))
            #expect(await monitor.pendingWaiterCount == 1)

            await monitor.apply(.screenUnlocked)
            try await waiter.value
            #expect(await monitor.isAvailable)
            #expect(await monitor.pendingWaiterCount == 0)
        }

        @Test
        func throwsCancellationErrorWhenCancelled() async {
            let monitor = DesktopSessionMonitor(initialState: DesktopAvailabilityState(composerFocused: true))
            let waiter = Task { try await monitor.waitUntilAvailable() }
            #expect(await waitForWaiters(monitor, count: 1))

            waiter.cancel()

            await #expect(throws: CancellationError.self) { try await waiter.value }
            #expect(await waitForWaiters(monitor, count: 0))
        }

        @Test
        func composerFocusSetterAppliesInOrder() async {
            let monitor = DesktopSessionMonitor(initialState: DesktopAvailabilityState())
            let updates = await monitor.availabilityUpdates()
            monitor.setComposerFocused(true)
            monitor.setComposerFocused(false)
            monitor.setComposerFocused(true)

            var received: [Bool] = []
            for await value in updates {
                received.append(value)
                if received.count == 4 { break }
            }
            #expect(received == [true, false, true, false])
            #expect(await monitor.state.composerFocused)
        }
    }
}
