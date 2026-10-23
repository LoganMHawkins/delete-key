import Cocoa
import ApplicationServices
import ServiceManagement

// Makes a bare Delete (backspace) keypress behave like ⌘Delete in Finder
// and on the Desktop, unless a text field is being edited (rename, search).

let logPath = NSHomeDirectory() + "/Library/Logs/DeleteKey.log"
func log(_ m: String) {
    let line = "\(Date()) DeleteKey: \(m)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}
// Verbose per-keypress logging: `touch ~/Library/Logs/DeleteKey.debug` to enable, remove to disable.
var debug: Bool { FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Logs/DeleteKey.debug") }

let finderBundleID = "com.apple.finder"
let deleteKeyCode: Int64 = 51
let forwardDeleteKeyCode: Int64 = 117
let returnKeyCode: Int64 = 36
let enterKeyCode: Int64 = 76
let oKeyCode: Int64 = 31
// Opt-in: make Return/Enter open items instead of starting a rename:
//   defaults write ca.theboldbureau.deletekey openWithReturn -bool true   (then relaunch)
let openWithReturn = CommandLine.arguments.contains("--open-with-return")
    || UserDefaults.standard.bool(forKey: "openWithReturn")
let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

// Asks Finder itself for its focused element: the system-wide query fails for Finder.
// Fails safe: if the answer is unclear, treat it as editing so the key passes through.
func isEditingText(pid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var focused: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
    if debug { log("focus query err=\(err.rawValue)") }
    if err == .noValue { return false }          // nothing focused (e.g. bare Desktop)
    guard err == .success, let element = focused else { return true }
    let el = element as! AXUIElement
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
    if let r = role as? String,
       r == kAXTextFieldRole || r == kAXTextAreaRole || r == kAXComboBoxRole { return true }
    if debug { log("focused role=\((role as? String) ?? "nil")") }
    return false
}

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown,
          event.flags.intersection(modifierMask).isEmpty,
          let front = NSWorkspace.shared.frontmostApplication,
          front.bundleIdentifier == finderBundleID
    else { return Unmanaged.passUnretained(event) }

    let code = event.getIntegerValueField(.keyboardEventKeycode)
    switch code {
    case deleteKeyCode, forwardDeleteKeyCode:
        if isEditingText(pid: front.processIdentifier) { if debug { log("delete skipped: editing text") }; break }
        if debug { log("delete -> trash") }
        event.setIntegerValueField(.keyboardEventKeycode, value: deleteKeyCode)
        event.flags.insert(.maskCommand)            // ⌘Delete = Move to Trash
    case returnKeyCode, enterKeyCode:
        if !openWithReturn || isEditingText(pid: front.processIdentifier) { break }
        event.setIntegerValueField(.keyboardEventKeycode, value: oKeyCode)
        event.flags.insert(.maskCommand)            // ⌘O = Open
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

// Only one copy at a time.
let myPID = ProcessInfo.processInfo.processIdentifier
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != myPID }) {
    exit(0)
}

// Start at login: register once, so turning it off in Login Items sticks.
if #available(macOS 13.0, *), !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
    do { try SMAppService.mainApp.register(); log("registered as login item") }
    catch { log("login item registration failed: \(error.localizedDescription)") }
    UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
}

log("starting, trusted=\(AXIsProcessTrusted())")

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(options) {
    // Prompt shown; poll until the user grants Accessibility access, then relaunch:
    // the trust answer is cached per process, so start a fresh copy once this one exits.
    while !AXIsProcessTrusted() { Thread.sleep(forTimeInterval: 2) }
    log("access granted, relaunching")
    let relaunch = Process()
    relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
    relaunch.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
    try? relaunch.run()
    exit(0)
}

guard let created = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: callback,
    userInfo: nil
) else {
    log("could not create event tap")
    exit(1)
}
tap = created
log("event tap created, running")

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: created, enable: true)
CFRunLoopRun()
