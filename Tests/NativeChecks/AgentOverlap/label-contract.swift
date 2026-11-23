import CleanerCore
import Foundation
import SwiftUI
import AppKit

@main struct LabelContract {
    @MainActor static func main() async throws {
        precondition((2...3).contains(CommandLine.arguments.count))
        _ = NSApplication.shared
        let message = "Analysis policy changed; recalculate all containment in Settings."
        var match: AgentOverlapMatch?
        if CommandLine.arguments.count == 3 {
            let index = try await AgentOverlapStore(url: URL(fileURLWithPath: CommandLine.arguments[2]), descriptionSources: []).load(resetAnalysis: false)
            match = AgentOverlapAnalyzer.recommendations(in: index, activeIDs: Set(index.entries.keys)).first { $0.sourceID == "skill|/fixture/skill-0" }
            precondition(match?.targets.count == 3)
        }
        let view = AgentContainmentLabel(match: match, kind: .skill, status: message).padding(12).background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 400, height: nil)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("render failed") }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Rendered visible analysis-status component")
    }
}
