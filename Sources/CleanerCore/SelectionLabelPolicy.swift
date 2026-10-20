public enum SelectionLabelPolicy {
    public static func cleanupToggle(name: String, isSelected: Bool, isBlocked: Bool) -> String {
        toggle(name: name, isSelected: isSelected, isBlocked: isBlocked, planName: "清理计划")
    }

    public static func uninstallToggle(name: String, isSelected: Bool, isBlocked: Bool) -> String {
        toggle(name: name, isSelected: isSelected, isBlocked: isBlocked, planName: "卸载计划")
    }

    private static func toggle(name: String, isSelected: Bool, isBlocked: Bool, planName: String) -> String {
        if isBlocked { return "\(name)，始终保护" }
        return isSelected ? "从\(planName)移除 \(name)" : "将 \(name) 加入\(planName)"
    }
}
