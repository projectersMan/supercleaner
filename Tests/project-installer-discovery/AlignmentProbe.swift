import AppKit
import SwiftUI

@main struct AlignmentProbe: App {
    @State private var selection = "Cleanup Center"
    private let destinations = ["Cleanup Center", "System Cleanup", "Uninstall Apps", "Duplicate Large Files", "Agent Environment", "Local AI Models", "Project Artifacts", "Recovery", "Settings"]
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(destinations, id: \.self, selection: $selection) { name in Text(name).tag(name) }
                    .navigationSplitViewColumnWidth(min: 210, ideal: 238)
            } detail: {
                VStack(alignment: .leading) {
                    Text(selection).font(.largeTitle.bold())
                    Spacer()
                }
                .padding(24)
                .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
                .navigationTitle("SuperCleaner Alignment Check")
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
    }
}
