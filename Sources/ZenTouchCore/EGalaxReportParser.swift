/// A single finger on the panel, in normalized panel coordinates (0...1, origin top-left).
public struct Contact: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// Parses input report 6 of the eGalax EXC3200 controller in the ASUS ZenScreen MB16AMT.
///
/// Layout (from the device's HID report descriptor, report ID stripped):
///   byte 0        contact count (0...12); 0 means "continuation of the previous frame"
///   bytes 1..50   5 finger slots x 10 bytes:
///                   +0 bit0 tip switch
///                   +1 contact id
///                   +2 X  (uint16 LE, 0...4095)
///                   +4 Y  (uint16 LE, 0...4095)
///                   +6 4 bytes padding
///   bytes 51..54  scan time (uint32 LE)
///
/// The controller runs in "hybrid" mode: when more than 5 contacts are reported, the frame is
/// split across several reports and only the first carries the contact count.
public struct EGalaxReportParser {
    public static let reportID: UInt8 = 6
    public static let payloadLength = 1 + slotCount * slotSize + 4

    static let slotCount = 5
    static let slotSize = 10
    static let logicalMax = 4095.0

    private var active: [Contact] = []
    private var expected = 0
    private var received = 0

    public init() {}

    /// Feeds one report payload (without the report ID byte). Returns the touching contacts once
    /// every slot of the frame has arrived, or nil while a hybrid frame is still incomplete.
    public mutating func feed(_ payload: [UInt8]) -> [Contact]? {
        guard payload.count >= Self.payloadLength else { return nil }

        let count = Int(payload[0])
        if count > 0 {
            active = []
            expected = count
            received = 0
        }
        guard expected > 0 else { return nil }

        for slot in 0..<Self.slotCount where received < expected {
            let o = 1 + slot * Self.slotSize
            received += 1
            guard payload[o] & 0x01 == 1 else { continue }  // lifted finger: reported once with tip = 0
            let x = Double(UInt16(payload[o + 2]) | UInt16(payload[o + 3]) << 8)
            let y = Double(UInt16(payload[o + 4]) | UInt16(payload[o + 5]) << 8)
            active.append(Contact(
                id: Int(payload[o + 1]),
                x: min(max(x / Self.logicalMax, 0), 1),
                y: min(max(y / Self.logicalMax, 0), 1)
            ))
        }

        guard received >= expected else { return nil }
        expected = 0
        return active
    }
}
