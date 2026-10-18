import AppKit
import IOKit.hid
import ZenTouchCore

let usage = """
usage: zentouch [options]

Touchscreen driver for the ASUS ZenScreen MB16AMT (eGalax EXC3200) on macOS.

  --display NAME   match the touch display by name (default: MB16AMT; falls back to the first external display)
  --dump           print contacts and gestures instead of moving the cursor
  --no-seize       don't take exclusive access to the panel (macOS keeps handling it too)
  --swap-xy        swap the panel axes
  --flip-x         mirror horizontally
  --flip-y         mirror vertically
  --zoom-keys      pinch zooms with ⌘+ / ⌘− steps instead of trackpad-style gestures
  --help           show this help
"""

var displayQuery = "MB16AMT"
var dump = false
var seize = true
var zoomStyle = ZoomStyle.gesture
var calibration = Calibration()

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--display": displayQuery = args.popFirst() ?? displayQuery
    case "--dump": dump = true
    case "--no-seize": seize = false
    case "--swap-xy": calibration.swapXY = true
    case "--flip-x": calibration.flipX = true
    case "--flip-y": calibration.flipY = true
    case "--zoom-keys": zoomStyle = .keys
    case "--help", "-h": print(usage); exit(0)
    default: print("unknown option \(arg)\n\n\(usage)"); exit(64)
    }
}

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ message: String) { print("[zentouch] \(message)") }

// Reading the panel needs Input Monitoring; posting events needs Accessibility.
// macOS only shows each prompt once; afterwards use the menu bar's settings shortcuts.
if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    log("Input Monitoring not granted yet: allow it in System Settings → Privacy & Security, then restart.")
}
if !dump, !CGPreflightPostEventAccess() {
    CGRequestPostEventAccess()
    log("Accessibility not granted yet: allow it in System Settings → Privacy & Security, then restart.")
}

if let display = DisplayLocator.find(nameContaining: displayQuery) {
    log("Touch display: \(display.name)")
} else {
    log("Touch display not connected yet; waiting for it.")
}

var parser = EGalaxReportParser()
var engine = GestureEngine()
let injector = EventInjector(zoomStyle: zoomStyle)
var mapper: DisplayMapper?
var panelConnected = false
var paused = false

func now() -> Double { ProcessInfo.processInfo.systemUptime }

func handle(_ actions: [TouchAction]) {
    if dump {
        actions.forEach { log("  → \($0)") }
    } else {
        actions.forEach(injector.perform)
    }
}

/// Ends any gesture in progress, so nothing (like a held mouse button) is left stuck.
func finishGesture() { handle(engine.update([], at: now())) }

let device = TouchDevice(seize: seize, onReport: { payload in
    guard let contacts = parser.feed(payload), !paused else { return }
    // Re-read the display geometry at the start of each gesture so rearranging or rotating applies at once.
    if engine.isIdle, !contacts.isEmpty { mapper = DisplayLocator.mapper(nameContaining: displayQuery, calibration: calibration) }
    guard let mapper else { return }

    let points = contacts.map(mapper.map)
    if dump {
        let desc = zip(contacts, points).map { c, p in
            String(format: "#%d raw(%.3f, %.3f) → (%.0f, %.0f)", c.id, c.x, c.y, p.x, p.y)
        }
        log(desc.isEmpty ? "lift" : desc.joined(separator: "  "))
    }
    handle(engine.update(points, at: now()))
}, onConnectionChange: { connected in
    panelConnected = connected
    log(connected ? "Touch panel connected" : "Touch panel disconnected")
    if !connected { finishGesture() }
})

device.start()
log(dump ? "Dumping touches. Ctrl-C to quit." : "Running.")

let ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
    guard !paused else { return }
    handle(engine.tick(at: now()))
}

func shutDown() {
    finishGesture()
    device.stop()
}

// Ctrl-C in a terminal, or launchctl stopping the agent.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalSources = [SIGINT, SIGTERM].map { sig in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        shutDown()
        exit(0)
    }
    source.resume()
    return source
}

// A menu bar app with no Dock icon or main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusMenu = dump ? nil : StatusMenu(isPanelConnected: { panelConnected }, panelProblem: { device.problem }, onPauseChange: { isPaused in
    if isPaused { finishGesture() }
    paused = isPaused
    log(isPaused ? "Paused" : "Resumed")
})
let terminationObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
) { _ in shutDown() }
app.run()
