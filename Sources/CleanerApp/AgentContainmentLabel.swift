import CleanerCore
import SwiftUI

struct AgentContainmentLabel: View {
    let match: AgentOverlapMatch?
    let kind: AgentOverlapKind
    let status: String

    var body: some View {
        Group {
            if let match {
                VStack(alignment: .leading, spacing: 5) {
                    Text(kind == .skill ? L10n.text("其他 Skill 对本项的覆盖（前 3 名）") : L10n.text("其他 MCP 对本项的覆盖（前 3 名）"))
                        .fontWeight(.semibold)
                    ForEach(match.targets) { target in
                        let path = String(target.targetID.dropFirst(kind.rawValue.count + 1))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(target.title).lineLimit(1).truncationMode(.middle)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                Text(L10n.text("{0}%", percentage(target.coverage)))
                                    .monospacedDigit()
                                    .frame(width: 50, alignment: .trailing)
                            }
                            Text(path)
                                .font(.caption2).lineLimit(1).truncationMode(.middle)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .help(path)
                    }
                    if match.totalFeatureCount == 0 {
                        Text(L10n.text("未提取到能力描述"))
                    } else if match.targets.isEmpty {
                        Text(L10n.text("暂无其他对象覆盖"))
                    }
                }
            } else {
                Text(status)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.leading)
        .frame(width: 360, alignment: .leading)
        .layoutPriority(1)
    }

    private func percentage(_ value: Double) -> String {
        String(format: "%.1f", (value * 1_000).rounded(.down) / 10)
    }
}
