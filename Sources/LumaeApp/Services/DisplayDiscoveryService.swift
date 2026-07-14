import AppKit
import CoreGraphics
import LumaeCore

@MainActor
final class DisplayDiscoveryService {
    var onTopologyChange: ((DisplayTopology) -> Void)?
    private(set) var currentTopology = DisplayTopology(displays: [])
    private var observer: NSObjectProtocol?

    func start() {
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func refresh() {
        let displays = NSScreen.screens.compactMap { screen -> DisplayDescriptor? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let mode = CGDisplayCopyDisplayMode(id)
            let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id), serial = CGDisplaySerialNumber(id)
            let stable = serial != 0 ? "v\(vendor)-m\(model)-s\(serial)" : "cg-\(id)-v\(vendor)-m\(model)"
            return DisplayDescriptor(
                fingerprint: DisplayFingerprint(stableID: stable, vendorID: vendor, modelID: model, serialNumber: serial, localizedName: screen.localizedName),
                framePoints: LRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: screen.frame.width, height: screen.frame.height),
                visibleFramePoints: LRect(x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y, width: screen.visibleFrame.width, height: screen.visibleFrame.height),
                pixelSize: LSize(width: Double(mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor)), height: Double(mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor))),
                backingScaleFactor: screen.backingScaleFactor,
                refreshRate: mode?.refreshRate,
                rotationDegrees: CGDisplayRotation(id),
                isMain: CGDisplayIsMain(id) != 0,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                mirroredDisplayID: CGDisplayIsInMirrorSet(id) != 0 ? String(CGDisplayMirrorsDisplay(id)) : nil
            )
        }
        let topology = DisplayTopology(displays: displays)
        if topology.displays != currentTopology.displays { currentTopology = topology; onTopologyChange?(topology) }
    }
}
