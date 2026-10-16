import Foundation
import IOKit.hid
import ZenTouchCore

/// Opens the eGalax controller and delivers report-6 payloads (report ID stripped) on the main run loop.
/// If the panel can't be opened yet (no Input Monitoring permission, or another app such as a second
/// zentouch holds it), it keeps retrying, so a login-started copy recovers on its own.
final class TouchDevice {
    static let vendorID = 0x0EEF
    static let productID = 0xC000

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let seize: Bool
    private let onReport: ([UInt8]) -> Void
    private let onConnectionChange: (Bool) -> Void
    private var retryTimer: Timer?
    private var lastFailure: IOReturn?

    private(set) var isOpen = false
    /// Why the panel isn't open, for the menu bar.
    var problem: String? {
        guard !isOpen, let code = lastFailure else { return nil }
        return code == kIOReturnExclusiveAccess ? "Panel in use by another app (another zentouch?)" : "Can't open the panel"
    }

    init(seize: Bool, onReport: @escaping ([UInt8]) -> Void, onConnectionChange: @escaping (Bool) -> Void) {
        self.seize = seize
        self.onReport = onReport
        self.onConnectionChange = onConnectionChange
    }

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            Unmanaged<TouchDevice>.fromOpaque(ctx!).takeUnretainedValue().onConnectionChange(true)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            Unmanaged<TouchDevice>.fromOpaque(ctx!).takeUnretainedValue().onConnectionChange(false)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { ctx, _, _, _, reportID, report, length in
            guard reportID == UInt32(EGalaxReportParser.reportID) else { return }
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            // macOS prefixes numbered reports with their ID; the length tells us whether it is there.
            if bytes.count == EGalaxReportParser.payloadLength + 1 { bytes.removeFirst() }
            Unmanaged<TouchDevice>.fromOpaque(ctx!).takeUnretainedValue().onReport(bytes)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        guard !open() else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            if self?.open() ?? true { timer.invalidate() }
        }
    }

    private func open() -> Bool {
        // Seizing stops macOS's own digitizer handling, which otherwise drives the cursor on the wrong screen.
        let options = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        let result = IOHIDManagerOpen(manager, options)
        isOpen = result == kIOReturnSuccess
        if isOpen {
            if lastFailure != nil { print("[zentouch] Touch panel opened") }
        } else if result != lastFailure {
            let hex = String(UInt32(bitPattern: result), radix: 16)
            print("[zentouch] Can't open the touch panel (0x\(hex)); retrying every 3 s.")
        }
        lastFailure = isOpen ? nil : result
        return isOpen
    }

    func stop() {
        retryTimer?.invalidate()
        if isOpen { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }
}
