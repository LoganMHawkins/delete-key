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

func isEditingText() -> Bool {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused else { return false }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
    guard let r = role as? String else { return false }
    return r == kAXTextFieldRole || r == kAXTextAreaRole || r == kAXComboBoxRole
}

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown,
          event.flags.intersection(modifierMask).isEmpty,
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderBundleID
    else { return Unmanaged.passUnretained(event) }

    let code = event.getIntegerValueField(.keyboardEventKeycode)
    switch code {
    case deleteKeyCode, forwardDeleteKeyCode:
        if isEditingText() { break }
        event.setIntegerValueField(.keyboardEventKeycode, value: deleteKeyCode)
        event.flags.insert(.maskCommand)            // ⌘Delete = Move to Trash
    case returnKeyCode, enterKeyCode:
        if !openWithReturn || isEditingText() { break }
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
