public enum SelectionLabelPolicy {
    public static func cleanupToggle(name: String, isSelected: Bool, isBlocked: Bool) -> String {
        toggle(name: name, isSelected: isSelected, isBlocked: isBlocked, planName: L10n.text("清理计划"))
    }

    public static func uninstallToggle(name: String, isSelected: Bool, isBlocked: Bool) -> String {
        toggle(name: name, isSelected: isSelected, isBlocked: isBlocked, planName: L10n.text("卸载计划"))
    }

    private static func toggle(name: String, isSelected: Bool, isBlocked: Bool, planName: String) -> String {
        if isBlocked { return L10n.text("{0}，始终保护", String(describing: name)) }
        return isSelected ? L10n.text("从{0}移除 {1}", String(describing: planName), String(describing: name)) : L10n.text("将 {0} 加入{1}", String(describing: name), String(describing: planName))
    }
}
