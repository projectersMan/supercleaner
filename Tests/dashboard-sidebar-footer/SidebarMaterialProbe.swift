import AppKit
import SwiftUI

@main struct SidebarMaterialProbe: App {
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List { Text("Cleanup Center"); Text("System Cleanup"); Text("Tools"); Text("Settings") }
                    .navigationSplitViewColumnWidth(min: 210, ideal: 211)
            } detail: {
                VStack(spacing: 0) {
                    Spacer()
                    sample("NSVisualEffectView.sidebar").background(SidebarMaterial())
                    sample("windowBackgroundColor").background(Color(nsColor: .windowBackgroundColor))
                    sample("regularMaterial").background(.regularMaterial)
                    sample("thinMaterial").background(.thinMaterial)
                    sample("ultraThinMaterial").background(.ultraThinMaterial)
                    sample("bar").background(.bar)
                }
                .frame(minWidth: 760, minHeight: 560)
                .navigationTitle("Sidebar Material Check")
            }
        }.windowToolbarStyle(.unified).defaultSize(width: 1280, height: 820)
    }

    private func sample(_ name: String) -> some View {
        Text(name).frame(maxWidth: .infinity).frame(height: 40)
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
