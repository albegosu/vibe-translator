import AppKit
import ApplicationServices

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        // Never let a busy app freeze the menu bar app.
        AXUIElementSetMessagingTimeout(element, 1.0)
        return element
    }

    /// Chromium/Electron only build their accessibility tree when an assistive
    /// technology asks for it. This is the documented opt-in for Electron apps.
    @discardableResult
    static func enableManualAccessibility(_ app: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func isElectron(_ app: NSRunningApplication) -> Bool {
        guard let frameworks = app.bundleURL?.appendingPathComponent("Contents/Frameworks/Electron Framework.framework") else {
            return false
        }
        return FileManager.default.fileExists(atPath: frameworks.path)
    }
}

extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
    }

    func string(_ name: String) -> String? {
        attribute(name) as? String
    }

    func element(_ name: String) -> AXUIElement? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    var role: String? { string(kAXRoleAttribute) }
    var stringValue: String? { string(kAXValueAttribute) }

    var attributeNames: [String] {
        var names: CFArray?
        AXUIElementCopyAttributeNames(self, &names)
        return (names as? [String]) ?? []
    }

    var parameterizedAttributeNames: [String] {
        var names: CFArray?
        AXUIElementCopyParameterizedAttributeNames(self, &names)
        return (names as? [String]) ?? []
    }

    func isSettable(_ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success && settable.boolValue
    }

    func set(_ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    /// Selects the whole value. AX ranges are measured in UTF-16 code units.
    func selectAll(of text: String) -> AXError {
        var range = CFRange(location: 0, length: (text as NSString).length)
        guard let value = AXValueCreate(.cfRange, &range) else { return .failure }
        return set(kAXSelectedTextRangeAttribute, value)
    }

    var selectedRange: CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// Roles that editors (native and web) use for editable text.
    var isTextInput: Bool {
        let editableRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField"]
        if let role, editableRoles.contains(role) { return true }
        return attribute("AXEditableAncestor") != nil && isSettable(kAXSelectedTextRangeAttribute)
    }
}

extension AXError {
    var name: String {
        switch self {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .invalidUIElementObserver: "invalidUIElementObserver"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notificationUnsupported: "notificationUnsupported"
        case .notImplemented: "notImplemented"
        case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
        case .notificationNotRegistered: "notificationNotRegistered"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: "notEnoughPrecision"
        @unknown default: "AXError(\(rawValue))"
        }
    }
}
