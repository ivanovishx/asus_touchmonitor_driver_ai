// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "zentouch",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: report parsing, coordinate mapping, gesture recognition. No IOKit, fully testable.
        .target(name: "ZenTouchCore"),
        // The daemon: HID access, display lookup, event injection.
        .executableTarget(name: "zentouch", dependencies: ["ZenTouchCore"]),
        .testTarget(name: "ZenTouchCoreTests", dependencies: ["ZenTouchCore"]),
    ]
)
