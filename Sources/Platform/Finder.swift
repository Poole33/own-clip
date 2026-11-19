import ApplicationServices
import Foundation

struct FinderFocus {
    let fileBrowser: Bool
    let hasSelection: Bool

    static func inspect(pid: pid_t, requireSelection: Bool) -> Self? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let focused = element(app, kAXFocusedUIElementAttribute) else { return nil }
        let browsingRoles: Set<String> = [kAXBrowserRole, kAXOutlineRole, kAXTableRole, kAXListRole,
                                          kAXScrollAreaRole, "AXCollection", "AXGrid"]
        let editingRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
        let locationBar = value(focused, kAXSubroleAttribute) as? String == "AXSearchField"
        if locationBar || editingRoles.contains(value(focused, kAXRoleAttribute) as? String ?? "") { return nil }

        var node: AXUIElement? = focused
        var fileBrowser = false
        var selection = false
        for _ in 0..<5 {
            guard let current = node, let role = value(current, kAXRoleAttribute) as? String else { break }
            if editingRoles.contains(role) || role == kAXToolbarRole { return nil }
            if role == kAXWindowRole { break }
            if browsingRoles.contains(role) { fileBrowser = true }
            if requireSelection {
                for attribute in [kAXSelectedRowsAttribute, kAXSelectedChildrenAttribute] {
                    if let selected = value(current, attribute) as? [AXUIElement], !selected.isEmpty { selection = true }
                }
                if value(current, kAXSelectedAttribute) as? Bool == true { selection = true }
            }
            node = element(current, kAXParentAttribute)
        }
        return Self(fileBrowser: fileBrowser, hasSelection: selection)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(result, to: AXUIElement.self)
    }
}
