import ApplicationServices
@preconcurrency import AXorcist
import CoreGraphics
import Darwin
import Foundation
import PeekabooFoundation

/// Synthetic input that targets a process directly instead of the global HID tap.
///
/// This keeps the user's frontmost app and cursor alone. It is best-effort:
/// macOS delivers pid-routed CGEvents differently from hardware events, and
/// some apps ignore background mouse events unless they also expose an AX path.
enum BackgroundInputDriver {
    struct KeyboardEventPlan {
        let modifierKeyDownEvents: [CGEvent]
        let primaryKeyDownEvent: CGEvent
        let primaryKeyUpEvent: CGEvent
        let modifierKeyUpEvents: [CGEvent]
    }

    static func click(
        at point: CGPoint,
        button: MouseButton,
        count: Int,
        targetProcessIdentifier: pid_t) throws
    {
        guard CGPreflightPostEventAccess() else {
            throw PeekabooError.permissionDeniedEventSynthesizing
        }

        guard targetProcessIdentifier > 0, self.isProcessAlive(targetProcessIdentifier) else {
            throw PeekabooError.invalidInput("Target process identifier is not running: \(targetProcessIdentifier)")
        }

        let (downType, upType, cgButton) = Self.eventTypes(for: button)
        let source = CGEventSource(stateID: .hidSystemState)
        let clampedCount = max(1, min(3, count))

        for clickIndex in 1...clampedCount {
            guard
                let down = CGEvent(
                    mouseEventSource: source,
                    mouseType: downType,
                    mouseCursorPosition: point,
                    mouseButton: cgButton),
                let up = CGEvent(
                    mouseEventSource: source,
                    mouseType: upType,
                    mouseCursorPosition: point,
                    mouseButton: cgButton)
            else {
                throw PeekabooError.operationError(message: "Failed to create background mouse events")
            }

            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))
            self.stampRoutingFields(on: down, at: point, targetProcessIdentifier: targetProcessIdentifier)
            self.stampRoutingFields(on: up, at: point, targetProcessIdentifier: targetProcessIdentifier)

            Self.post(down, to: targetProcessIdentifier)
            usleep(30000)
            Self.post(up, to: targetProcessIdentifier)

            if clickIndex < clampedCount {
                usleep(80000)
            }
        }
    }

    static func type(
        _ text: String,
        delayPerCharacter: TimeInterval,
        targetProcessIdentifier: pid_t) throws
    {
        try self.validateTarget(targetProcessIdentifier)

        for character in text {
            try self.typeCharacter(character, targetProcessIdentifier: targetProcessIdentifier)
            if delayPerCharacter > 0 {
                Thread.sleep(forTimeInterval: delayPerCharacter)
            }
        }
    }

    static func typeCharacter(_ character: Character, targetProcessIdentifier: pid_t) throws {
        try self.validateTarget(targetProcessIdentifier)

        if let stroke = self.keyboardStroke(for: character) {
            try self.postKeyboardStroke(stroke, targetProcessIdentifier: targetProcessIdentifier)
            return
        }

        try self.postUnicodeCharacter(character, targetProcessIdentifier: targetProcessIdentifier)
    }

    static func tapKey(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags = [],
        targetProcessIdentifier: pid_t) throws
    {
        try self.validateTarget(targetProcessIdentifier)
        try self.postKeyboardStroke(
            (keyCode: keyCode, flags: modifiers),
            targetProcessIdentifier: targetProcessIdentifier)
    }

    static func postEvent(_ event: CGEvent, to pid: pid_t) {
        self.post(event, to: pid)
    }

    @discardableResult
    static func replaceFocusedText(
        with text: String,
        targetProcessIdentifier: pid_t) throws -> Bool
    {
        try self.validateLiveTarget(targetProcessIdentifier)
        guard let element = try self.focusedEditableTextElement(targetProcessIdentifier: targetProcessIdentifier) else {
            return false
        }
        guard try self.setText(text, on: element) else {
            return false
        }
        self.setSelectedTextRange(CFRange(location: text.utf16.count, length: 0), on: element)
        return true
    }

    @discardableResult
    static func insertTextIntoFocusedText(
        _ text: String,
        targetProcessIdentifier: pid_t) throws -> Bool
    {
        try self.validateLiveTarget(targetProcessIdentifier)
        guard let element = try self.focusedEditableTextElement(targetProcessIdentifier: targetProcessIdentifier),
              let currentText = try self.textValue(from: element)
        else {
            return false
        }

        let selectedRange = self.selectedTextRange(from: element)
        let edit = self.textByReplacingSelection(in: currentText, selection: selectedRange, replacement: text)
        guard try self.setText(edit.text, on: element) else {
            return false
        }
        self.setSelectedTextRange(CFRange(location: edit.cursorLocation, length: 0), on: element)
        return true
    }

    @discardableResult
    static func performFocusedTextKey(
        _ key: PeekabooFoundation.SpecialKey,
        targetProcessIdentifier: pid_t) throws -> Bool
    {
        try self.validateLiveTarget(targetProcessIdentifier)
        guard let element = try self.focusedEditableTextElement(targetProcessIdentifier: targetProcessIdentifier),
              let currentText = try self.textValue(from: element)
        else {
            return false
        }

        let textLength = currentText.utf16.count
        let selection = self.clampedSelection(self.selectedTextRange(from: element), textLength: textLength)

        switch key {
        case .leftArrow:
            let location = self.cursorLocationMovingLeft(from: selection, in: currentText)
            self.setSelectedTextRange(CFRange(location: location, length: 0), on: element)
            return true

        case .rightArrow:
            let location = self.cursorLocationMovingRight(from: selection, in: currentText)
            self.setSelectedTextRange(CFRange(location: location, length: 0), on: element)
            return true

        case .home:
            self.setSelectedTextRange(CFRange(location: 0, length: 0), on: element)
            return true

        case .end:
            self.setSelectedTextRange(CFRange(location: textLength, length: 0), on: element)
            return true

        case .delete:
            guard let editRange = self.deletionRangeBeforeSelection(selection, in: currentText) else {
                return true
            }
            let edit = self.textByReplacingSelection(in: currentText, selection: editRange, replacement: "")
            guard try self.setText(edit.text, on: element) else { return false }
            self.setSelectedTextRange(CFRange(location: edit.cursorLocation, length: 0), on: element)
            return true

        case .forwardDelete:
            guard let editRange = self.deletionRangeAfterSelection(selection, in: currentText) else {
                return true
            }
            let edit = self.textByReplacingSelection(in: currentText, selection: editRange, replacement: "")
            guard try self.setText(edit.text, on: element) else { return false }
            self.setSelectedTextRange(CFRange(location: edit.cursorLocation, length: 0), on: element)
            return true

        case .space:
            let edit = self.textByReplacingSelection(in: currentText, selection: selection, replacement: " ")
            guard try self.setText(edit.text, on: element) else { return false }
            self.setSelectedTextRange(CFRange(location: edit.cursorLocation, length: 0), on: element)
            return true

        default:
            return false
        }
    }

    private static func post(_ event: CGEvent, to pid: pid_t) {
        if !SkyLightPerPidEventPost.post(event, to: pid) {
            event.postToPid(pid)
        }
    }

    private static func validateTarget(_ targetProcessIdentifier: pid_t) throws {
        guard CGPreflightPostEventAccess() else {
            throw PeekabooError.permissionDeniedEventSynthesizing
        }

        try self.validateLiveTarget(targetProcessIdentifier)
    }

    private static func validateLiveTarget(_ targetProcessIdentifier: pid_t) throws {
        guard targetProcessIdentifier > 0, self.isProcessAlive(targetProcessIdentifier) else {
            throw PeekabooError.invalidInput("Target process identifier is not running: \(targetProcessIdentifier)")
        }
    }

    private static func postKeyboardStroke(
        _ stroke: (keyCode: CGKeyCode, flags: CGEventFlags),
        targetProcessIdentifier: pid_t) throws
    {
        let plan = try self.keyboardEventPlan(
            keyCode: stroke.keyCode,
            flags: stroke.flags,
            targetProcessIdentifier: targetProcessIdentifier)

        for event in plan.modifierKeyDownEvents {
            self.post(event, to: targetProcessIdentifier)
            usleep(1000)
        }

        self.post(plan.primaryKeyDownEvent, to: targetProcessIdentifier)
        usleep(1000)
        self.post(plan.primaryKeyUpEvent, to: targetProcessIdentifier)

        for event in plan.modifierKeyUpEvents {
            usleep(1000)
            self.post(event, to: targetProcessIdentifier)
        }
    }

    static func keyboardEventPlan(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        targetProcessIdentifier: pid_t) throws -> KeyboardEventPlan
    {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers = self.modifierKeys(for: flags)
        var activeFlags: CGEventFlags = []

        let modifierDownEvents = try modifiers.map { modifier in
            activeFlags.insert(modifier.flag)
            return try self.makeKeyboardEvent(
                keyCode: modifier.keyCode,
                keyDown: true,
                flags: activeFlags,
                source: source,
                targetProcessIdentifier: targetProcessIdentifier)
        }

        let primaryKeyDownEvent = try self.makeKeyboardEvent(
            keyCode: keyCode,
            keyDown: true,
            flags: flags,
            source: source,
            targetProcessIdentifier: targetProcessIdentifier)
        let primaryKeyUpEvent = try self.makeKeyboardEvent(
            keyCode: keyCode,
            keyDown: false,
            flags: flags,
            source: source,
            targetProcessIdentifier: targetProcessIdentifier)

        let modifierUpEvents = try modifiers.reversed().map { modifier in
            activeFlags.remove(modifier.flag)
            return try self.makeKeyboardEvent(
                keyCode: modifier.keyCode,
                keyDown: false,
                flags: activeFlags,
                source: source,
                targetProcessIdentifier: targetProcessIdentifier)
        }

        return KeyboardEventPlan(
            modifierKeyDownEvents: modifierDownEvents,
            primaryKeyDownEvent: primaryKeyDownEvent,
            primaryKeyUpEvent: primaryKeyUpEvent,
            modifierKeyUpEvents: modifierUpEvents)
    }

    private static func makeKeyboardEvent(
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags,
        source: CGEventSource?,
        targetProcessIdentifier: pid_t) throws -> CGEvent
    {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw PeekabooError.operationError(message: "Failed to create background keyboard events")
        }

        event.flags = flags
        self.stampKeyboardRoutingFields(on: event, targetProcessIdentifier: targetProcessIdentifier)
        return event
    }

    private static func modifierKeys(for flags: CGEventFlags) -> [(keyCode: CGKeyCode, flag: CGEventFlags)] {
        var modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)] = []

        if flags.contains(.maskCommand) {
            modifiers.append((keyCode: 0x37, flag: .maskCommand))
        }
        if flags.contains(.maskShift) {
            modifiers.append((keyCode: 0x38, flag: .maskShift))
        }
        if flags.contains(.maskAlternate) {
            modifiers.append((keyCode: 0x3A, flag: .maskAlternate))
        }
        if flags.contains(.maskControl) {
            modifiers.append((keyCode: 0x3B, flag: .maskControl))
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.append((keyCode: 0x3F, flag: .maskSecondaryFn))
        }

        return modifiers
    }

    private static func postUnicodeCharacter(_ character: Character, targetProcessIdentifier: pid_t) throws {
        let string = String(character)
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw PeekabooError.operationError(message: "Failed to create background unicode keyboard events")
        }

        let chars = Array(string.utf16)
        chars.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: buffer.baseAddress!)
            keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: buffer.baseAddress!)
        }

        self.stampKeyboardRoutingFields(on: keyDown, targetProcessIdentifier: targetProcessIdentifier)
        self.stampKeyboardRoutingFields(on: keyUp, targetProcessIdentifier: targetProcessIdentifier)
        self.post(keyDown, to: targetProcessIdentifier)
        usleep(1000)
        self.post(keyUp, to: targetProcessIdentifier)
    }

    private static func keyboardStroke(for character: Character) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        let string = String(character)
        guard string.count == 1 else { return nil }

        if let scalar = string.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(scalar),
           let keyCode = self.keyCodes[string]
        {
            return (keyCode, [])
        }

        if let scalar = string.unicodeScalars.first,
           CharacterSet.uppercaseLetters.contains(scalar),
           let keyCode = self.keyCodes[string.lowercased()]
        {
            return (keyCode, .maskShift)
        }

        if let keyCode = self.keyCodes[string] {
            return (keyCode, [])
        }

        if let shifted = self.shiftedKeyCodes[character] {
            return (shifted, .maskShift)
        }

        return nil
    }

    private static func stampRoutingFields(
        on event: CGEvent,
        at point: CGPoint,
        targetProcessIdentifier: pid_t)
    {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetProcessIdentifier))

        guard let windowID = self.windowID(containing: point, targetProcessIdentifier: targetProcessIdentifier) else {
            return
        }

        let value = Int64(windowID)
        event.setIntegerValueField(.windowID, value: value)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: value)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: value)
    }

    static func stampKeyboardRoutingFields(on event: CGEvent, targetProcessIdentifier: pid_t) {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetProcessIdentifier))
    }

    static func textByReplacingSelection(
        in currentText: String,
        selection: CFRange?,
        replacement: String) -> (text: String, cursorLocation: Int)
    {
        guard let selection,
              selection.location >= 0,
              selection.length >= 0
        else {
            return (currentText + replacement, currentText.utf16.count + replacement.utf16.count)
        }

        let utf16 = currentText.utf16
        guard let startUTF16 = utf16.index(
            utf16.startIndex,
            offsetBy: selection.location,
            limitedBy: utf16.endIndex),
            let endUTF16 = utf16.index(
                startUTF16,
                offsetBy: selection.length,
                limitedBy: utf16.endIndex),
            let start = String.Index(startUTF16, within: currentText),
            let end = String.Index(endUTF16, within: currentText)
        else {
            return (currentText + replacement, currentText.utf16.count + replacement.utf16.count)
        }

        let updated = currentText.replacingCharacters(in: start..<end, with: replacement)
        return (updated, selection.location + replacement.utf16.count)
    }

    static func cursorLocationMovingLeft(from selection: CFRange, in text: String) -> Int {
        if selection.length > 0 {
            return selection.location
        }
        guard selection.location > 0,
              let cursor = self.stringIndex(in: text, utf16Offset: selection.location)
        else {
            return max(0, selection.location - 1)
        }

        return text.index(before: cursor).utf16Offset(in: text)
    }

    static func cursorLocationMovingRight(from selection: CFRange, in text: String) -> Int {
        if selection.length > 0 {
            return selection.location + selection.length
        }
        let textLength = text.utf16.count
        guard selection.location < textLength,
              let cursor = self.stringIndex(in: text, utf16Offset: selection.location)
        else {
            return min(textLength, selection.location + 1)
        }

        return text.index(after: cursor).utf16Offset(in: text)
    }

    private static func clampedSelection(_ selection: CFRange?, textLength: Int) -> CFRange {
        guard let selection,
              selection.location >= 0,
              selection.length >= 0
        else {
            return CFRange(location: textLength, length: 0)
        }

        let location = min(selection.location, textLength)
        let length = min(selection.length, textLength - location)
        return CFRange(location: location, length: length)
    }

    private static func deletionRangeBeforeSelection(_ selection: CFRange, in text: String) -> CFRange? {
        if selection.length > 0 {
            return selection
        }
        guard selection.location > 0,
              let cursor = self.stringIndex(in: text, utf16Offset: selection.location)
        else {
            return nil
        }

        let previous = text.index(before: cursor)
        return CFRange(
            location: previous.utf16Offset(in: text),
            length: cursor.utf16Offset(in: text) - previous.utf16Offset(in: text))
    }

    private static func deletionRangeAfterSelection(_ selection: CFRange, in text: String) -> CFRange? {
        if selection.length > 0 {
            return selection
        }
        guard let cursor = self.stringIndex(in: text, utf16Offset: selection.location),
              cursor < text.endIndex
        else {
            return nil
        }

        let next = text.index(after: cursor)
        return CFRange(
            location: cursor.utf16Offset(in: text),
            length: next.utf16Offset(in: text) - cursor.utf16Offset(in: text))
    }

    private static func stringIndex(in text: String, utf16Offset: Int) -> String.Index? {
        let utf16 = text.utf16
        guard let utf16Index = utf16.index(
            utf16.startIndex,
            offsetBy: utf16Offset,
            limitedBy: utf16.endIndex)
        else {
            return nil
        }
        return String.Index(utf16Index, within: text)
    }

    private static func focusedEditableTextElement(targetProcessIdentifier: pid_t) throws -> AXUIElement? {
        let application = AXUIElementCreateApplication(targetProcessIdentifier)
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue)

        guard focusedError != .apiDisabled else {
            throw PeekabooError.permissionDeniedAccessibility
        }
        guard focusedError == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        guard !self.isSecureTextElement(element),
              self.isValueSettable(element)
        else {
            return nil
        }
        return element
    }

    private static func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable)
        return error == .success && settable.boolValue
    }

    private static func isSecureTextElement(_ element: AXUIElement) -> Bool {
        let role = self.stringAttribute(kAXRoleAttribute as CFString, from: element)
        let subrole = self.stringAttribute(kAXSubroleAttribute as CFString, from: element)
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    private static func textValue(from element: AXUIElement) throws -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value)
        guard error != .apiDisabled else {
            throw PeekabooError.permissionDeniedAccessibility
        }
        guard error == .success else {
            return nil
        }
        return value as? String
    }

    private static func setText(_ text: String, on element: AXUIElement) throws -> Bool {
        let error = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef)
        switch error {
        case .success:
            return true
        case .apiDisabled:
            throw PeekabooError.permissionDeniedAccessibility
        default:
            return false
        }
    }

    private static func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private static func setSelectedTextRange(_ range: CFRange, on element: AXUIElement) {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else {
            return
        }
        _ = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value)
    }

    private static func stringAttribute(_ attributeName: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attributeName, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private static func windowID(containing point: CGPoint, targetProcessIdentifier: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else {
            return nil
        }

        for window in windows {
            guard self.pid(from: window[kCGWindowOwnerPID as String]) == targetProcessIdentifier,
                  self.intValue(from: window[kCGWindowLayer as String]) == 0,
                  let windowNumber = self.windowID(from: window[kCGWindowNumber as String]),
                  let boundsValue = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as CFDictionary),
                  bounds.contains(point)
            else {
                continue
            }

            return windowNumber
        }

        return nil
    }

    private static func windowID(from value: Any?) -> CGWindowID? {
        self.intValue(from: value).map(CGWindowID.init)
    }

    private static func pid(from value: Any?) -> pid_t? {
        self.intValue(from: value).map(pid_t.init)
    }

    private static func intValue(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let int = value as? Int {
            return int
        }
        if let int32 = value as? Int32 {
            return Int(int32)
        }
        if let uint32 = value as? UInt32 {
            return Int(uint32)
        }
        return nil
    }

    private static func eventTypes(for button: MouseButton) -> (CGEventType, CGEventType, CGMouseButton) {
        switch button {
        case .left:
            (.leftMouseDown, .leftMouseUp, .left)
        case .right:
            (.rightMouseDown, .rightMouseUp, .right)
        case .middle:
            (.otherMouseDown, .otherMouseUp, .center)
        }
    }

    private static func isProcessAlive(_ processIdentifier: pid_t) -> Bool {
        errno = 0
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32, " ": 0x31,
    ]

    private static let shiftedKeyCodes: [Character: CGKeyCode] = [
        "!": 0x12, "@": 0x13, "#": 0x14, "$": 0x15, "%": 0x17, "^": 0x16, "&": 0x1A, "*": 0x1C,
        "(": 0x19, ")": 0x1D, "_": 0x1B, "+": 0x18, "{": 0x21, "}": 0x1E, "|": 0x2A, ":": 0x29,
        "\"": 0x27, "<": 0x2B, ">": 0x2F, "?": 0x2C, "~": 0x32,
    ]
}

private enum SkyLightPerPidEventPost {
    private typealias PostToPidFn = @convention(c) (pid_t, CGEvent) -> Void

    private static let postToPid: PostToPidFn? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY)
        else {
            return nil
        }
        guard let symbol = dlsym(handle, "SLEventPostToPid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: PostToPidFn.self)
    }()

    @discardableResult
    static func post(_ event: CGEvent, to pid: pid_t) -> Bool {
        guard let postToPid else {
            return false
        }
        postToPid(pid, event)
        return true
    }
}
