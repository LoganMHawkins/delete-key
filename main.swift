import Cocoa
import ApplicationServices

// Makes a bare Delete (backspace) keypress behave like ⌘Delete in Finder
// and on the Desktop, unless a text field is being edited (rename, search).

let finderBundleID = "com.apple.finder"
let deleteKeyCode: Int64 = 51
let forwardDeleteKeyCode: Int64 = 117
let returnKeyCode: Int64 = 36
let enterKeyCode: Int64 = 76
let oKeyCode: Int64 = 31
// Opt-in: pass --open-with-return to make Return/Enter open items instead of renaming.
let openWithReturn = CommandLine.arguments.contains("--open-with-return")
let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

// Asks Finder itself for its focused element: the system-wide query fails for Finder.
// Fails safe: if the answer is unclear, treat it as editing so the key passes through.
func isEditingText(pid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var focused: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
    if err == .noValue { return false }          // nothing focused (e.g. bare Desktop)
    guard err == .success, let element = focused else { return true }
    let el = element as! AXUIElement
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
    if let r = role as? String,
       r == kAXTextFieldRole || r == kAXTextAreaRole || r == kAXComboBoxRole { return true }
    // Any other element that exposes a text selection is an editable text control.
    var range: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success
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
        if isEditingText(pid: front.processIdentifier) { break }
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

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(options) {
    // Prompt shown; poll until the user grants Accessibility access.
    while !AXIsProcessTrusted() { Thread.sleep(forTimeInterval: 2) }
}

guard let created = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: callback,
    userInfo: nil
) else {
    fputs("DeleteKey: could not create event tap\n", stderr)
    exit(1)
}
tap = created

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: created, enable: true)
CFRunLoopRun()
