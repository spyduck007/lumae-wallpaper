import AppKit
import CoreGraphics
import LumaeCore

@MainActor
final class FullScreenPerformanceController {
    var onCoveredDisplayIDsChange: ((Set<String>) -> Void)?

    private var isEnabled = false
    private var activeDisplayIDs: Set<String> = []
    private var coveredDisplayIDs: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    private var evaluationWorkItems: [DispatchWorkItem] = []
    private var revealGraceDeadline = Date.distantPast

    init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let notificationCenter = NotificationCenter.default

        observe(
            center: workspaceCenter,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            revealFirst: true,
            delays: [0.18, 0.42, 0.80]
        )
        observe(
            center: workspaceCenter,
            name: NSWorkspace.didActivateApplicationNotification,
            revealFirst: false,
            delays: [0.12, 0.35]
        )
        observe(
            center: workspaceCenter,
            name: NSWorkspace.didWakeNotification,
            revealFirst: true,
            delays: [0.30, 0.75, 1.30]
        )
        observe(
            center: workspaceCenter,
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            revealFirst: true,
            delays: [0.25, 0.65]
        )
        observe(
            center: notificationCenter,
            name: NSApplication.didChangeScreenParametersNotification,
            revealFirst: true,
            delays: [0.25, 0.65]
        )
    }

    deinit {
        evaluationWorkItems.forEach { $0.cancel() }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func update(enabled: Bool, topology: DisplayTopology) {
        isEnabled = enabled
        activeDisplayIDs = topology.activeDisplayIDs

        guard enabled else {
            cancelEvaluations()
            publish([])
            return
        }
        scheduleEvaluation(delays: [0, 0.20, 0.50])
    }

    func revealDesktopForSystemTransition() {
        guard isEnabled else { return }
        revealGraceDeadline = Date().addingTimeInterval(1.6)
        publish([])
        scheduleEvaluation(delays: [1.75, 2.40])
    }

    private func observe(
        center: NotificationCenter,
        name: Notification.Name,
        revealFirst: Bool,
        delays: [TimeInterval]
    ) {
        observers.append(
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if revealFirst {
                        self.revealGraceDeadline = Date().addingTimeInterval(0.45)
                        self.publish([])
                    }
                    self.scheduleEvaluation(delays: delays)
                }
            }
        )
    }

    private func scheduleEvaluation(delays: [TimeInterval]) {
        guard isEnabled else { return }
        cancelEvaluations()

        evaluationWorkItems = delays.map { delay in
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.evaluateCoverage()
                }
            }
            if delay <= 0 {
                DispatchQueue.main.async(execute: item)
            } else {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + delay,
                    execute: item
                )
            }
            return item
        }
    }

    private func cancelEvaluations() {
        evaluationWorkItems.forEach { $0.cancel() }
        evaluationWorkItems.removeAll()
    }

    private func evaluateCoverage() {
        guard isEnabled else {
            publish([])
            return
        }
        guard Date() >= revealGraceDeadline else {
            publish([])
            return
        }
        publish(detectCoveredDisplayIDs())
    }

    private func publish(_ next: Set<String>) {
        let filtered = next.intersection(activeDisplayIDs)
        guard filtered != coveredDisplayIDs else { return }
        coveredDisplayIDs = filtered
        onCoveredDisplayIDsChange?(filtered)
    }

    private func detectCoveredDisplayIDs() -> Set<String> {
        let displayFrames = DisplayDiscoveryService.quartzDisplayFrames()
            .filter { activeDisplayIDs.contains($0.key) }
        guard !displayFrames.isEmpty else { return [] }

        let options: CGWindowListOption = [
            .optionOnScreenOnly,
            .excludeDesktopElements
        ]
        guard let windowInfo = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var result: Set<String> = []
        for info in windowInfo {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                  alpha.doubleValue > 0.01,
                  let boundsDictionary = info[kCGWindowBounds as String]
                    as? [String: Any],
                  let windowBounds = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                  ) else {
                continue
            }

            for (displayID, displayBounds) in displayFrames {
                guard displayBounds.width > 0, displayBounds.height > 0 else {
                    continue
                }
                let intersection = windowBounds.intersection(displayBounds)
                guard !intersection.isNull else { continue }
                let displayArea = displayBounds.width * displayBounds.height
                let coveredArea = intersection.width * intersection.height
                if coveredArea / displayArea >= 0.985 {
                    result.insert(displayID)
                }
            }
        }
        return result
    }
}
