import AppKit
import Combine
import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    var hasInternalBattery: Bool
    var percentage: Int
    var isCharging: Bool
    var isFullyCharged: Bool
    var isOnACPower: Bool

    static let noBattery = BatterySnapshot(
        hasInternalBattery: false,
        percentage: 100,
        isCharging: false,
        isFullyCharged: false,
        isOnACPower: true
    )

    var statusText: String {
        guard hasInternalBattery else { return "AC Power" }
        if isFullyCharged { return "Charged" }
        if isCharging { return "Charging" }
        return isOnACPower ? "Power Adapter" : "On Battery"
    }
}

final class BatteryService: ObservableObject {
    static let shared = BatteryService()

    @Published private(set) var snapshot = BatterySnapshot.noBattery

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()
        timer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }

        let notificationCenter = NotificationCenter.default
        observers.append(
            notificationCenter.addObserver(
                forName: Notification.Name.NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        )
    }

    deinit {
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
                as? [CFTypeRef] else {
            snapshot = .noBattery
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(
                info,
                source
            )?.takeUnretainedValue() as? [String: Any],
            let type = description[kIOPSTypeKey as String] as? String,
            type == (kIOPSInternalBatteryType as String) else {
                continue
            }

            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey as String] as? Int ?? 100, 1)
            let percentage = min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
            let powerSource = description[kIOPSPowerSourceStateKey as String] as? String
            let isOnACPower = powerSource == (kIOPSACPowerValue as String)
            let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let isFullyCharged = description[kIOPSIsChargedKey as String] as? Bool
                ?? (isOnACPower && percentage >= 100)

            snapshot = BatterySnapshot(
                hasInternalBattery: true,
                percentage: percentage,
                isCharging: isCharging,
                isFullyCharged: isFullyCharged,
                isOnACPower: isOnACPower
            )
            return
        }

        snapshot = .noBattery
    }
}
