import AppKit
import SwiftUI
import XCTest
@testable import CleanerApp

final class ReviewToolbarTests: XCTestCase {
    @MainActor
    func testAgentSearchPreservesHiddenSelectionsAndComposesWithPlatform() throws {
        try AppModel.checkAgentSearchFiltering()
    }

    @MainActor
    func testSearchFieldClearButtonUpdatesTheQuery() throws {
        _ = NSApplication.shared
        var query = "moleapp"
        let binding = Binding<String>(get: { query }, set: { query = $0 })
        let host = NSHostingView(rootView: ReviewToolbar(query: binding, prompt: "Toolbar search") { _ in EmptyView() })
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 760, height: 44),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = .init(x: 0, y: 0, width: 760, height: 44)
        host.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(Self.descendants(host).compactMap { $0 as? NSSearchField }.first,
            "All review pages must provide the native inline clear control")
        XCTAssertEqual(field.stringValue, "moleapp")
        let cell = try XCTUnwrap(field.cell as? NSSearchFieldCell)
        let cancel = try XCTUnwrap(cell.cancelButtonCell)
        cancel.performClick(field)
        XCTAssertEqual(query, "")
        XCTAssertEqual(field.stringValue, "")
        field.stringValue = "zflow"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        XCTAssertEqual(query, "zflow", "Filtering updates as the query is edited")
        cancel.performClick(field)
        XCTAssertEqual(query, "", "Clearing works after subsequent input")
    }

    @MainActor
    func testEveryControlFitsWithoutScrollingAtAllSupportedWidths() throws {
        _ = NSApplication.shared
        for width in [CGFloat(760), 800, 900, 1099, 1100, 1600] {
            for chinese in [false, true] {
                for page in ToolbarFixture.Page.allCases {
                    let host = NSHostingView(rootView: ToolbarFixture(page: page, chinese: chinese))
                    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 44),
                        styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    host.frame = .init(x: 0, y: 0, width: width, height: 44)
                    host.layoutSubtreeIfNeeded()
                    let descendants = Self.descendants(host)
                    let search = try XCTUnwrap(descendants.compactMap { $0 as? NSTextField }
                        .first { $0.placeholderString == "Toolbar search" })
                    let searchFrame = search.convert(search.bounds, to: host)
                    let probes = descendants.filter { $0 is NSSegmentedControl || $0.identifier?.rawValue.hasPrefix("toolbar-probe-") == true
                            || ($0 as? NSButton)?.title == (chinese ? "全选" : "Select All") }
                        .sorted { $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX }
                    let context = "\(page), width \(width), Chinese \(chinese)"
                    XCTAssertFalse(probes.isEmpty, context)
                    XCTAssertFalse(descendants.contains { $0 is NSScrollView || $0 is NSBox }, context)
                    XCTAssertEqual(host.fittingSize.height, 44, accuracy: 1, context)
                    XCTAssertEqual(searchFrame.width, width < 1100 ? 170 : 260, accuracy: 2, context)
                    XCTAssertEqual(searchFrame.maxX, width - (width < 1100 ? 12 : 20), accuracy: 2, context)
                    var previousMaxX = CGFloat(width < 1100 ? 11 : 17)
                    for probe in probes {
                        let frame = probe.convert(probe.bounds, to: host)
                        XCTAssertEqual(frame.midY, searchFrame.midY, accuracy: 2, context)
                        XCTAssertGreaterThanOrEqual(frame.minX, previousMaxX, context)
                        XCTAssertLessThanOrEqual(frame.maxX, searchFrame.minX - 4, context)
                        previousMaxX = frame.maxX
                        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                        if let segments = probe as? NSSegmentedControl {
                            XCTAssertGreaterThanOrEqual(frame.width + 0.5, segments.intrinsicContentSize.width, context)
                            for index in 0..<segments.segmentCount {
                                let textWidth = (segments.label(forSegment: index)! as NSString)
                                    .size(withAttributes: [.font: font]).width
                                XCTAssertGreaterThanOrEqual(frame.width / CGFloat(segments.segmentCount), textWidth + 16, context)
                            }
                        } else if let button = probe as? NSButton {
                            if button is NSPopUpButton {
                                XCTAssertEqual(frame.width, width < 1100 ? 120 : 140, accuracy: 1, context)
                            }
                            XCTAssertGreaterThanOrEqual(frame.width + 0.5, button.intrinsicContentSize.width, context)
                            let textWidth = (button.title as NSString).size(withAttributes: [.font: font]).width
                            XCTAssertGreaterThanOrEqual(frame.width, textWidth + 24, context)
                        }
                    }
                    window.close()
                }
            }
        }
    }

    @MainActor
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct ToolbarFixture: View {
    enum Page: CaseIterable { case largeFiles, models, projects, applications, agent }
    let page: Page
    let chinese: Bool
    func text(_ en: String, _ zh: String) -> String { chinese ? zh : en }
    var body: some View {
        ReviewToolbar(query: .constant(""), prompt: "Toolbar search") { metrics in
            if page != .applications {
                ResourceSelectionCheckbox(state: .none, isEnabled: true, title: text("Select All", "全选"),
                    label: text("Select All", "全选"), action: {})
                    .frame(width: metrics.selectAllWidth, height: 18)
            }
            switch page {
            case .largeFiles:
                ScopeProbe(labels: text("All Large Files · Duplicate Large Files", "全部大文件 · 重复大文件"))
                    .frame(width: metrics.largeFileScopeWidth, height: 24)
            case .models, .projects:
                ScopeProbe(labels: page == .models
                    ? text("All · Cleanable · Protected · Selected", "全部 · 可清理 · 受保护 · 已选中")
                    : text("All · Protected · Selected", "全部 · 受保护 · 已选中"))
                    .frame(width: metrics.scopeWidth(count: page == .models ? 4 : 3), height: 24)
            case .applications:
                ScopeProbe(labels: text("All · Uninstallable · Running · Protected", "全部 · 可卸载 · 运行中 · 受保护"))
                    .frame(width: metrics.applicationScopeWidth, height: 24)
            case .agent:
                HStack(spacing: metrics.labelSpacing) {
                    if !metrics.isCompact { Text(text("Type", "类型")) }
                    ScopeProbe(labels: "Skills · MCP").frame(width: metrics.agentTypeWidth, height: 24)
                }
                HStack(spacing: metrics.labelSpacing) {
                    if !metrics.isCompact { Text(text("Platform", "平台")) }
                    LayoutProbe(name: text("Shared / Global", "共享 / Global"), kind: .menu).frame(width: metrics.dropdownWidth, height: 24)
                }
                HStack(spacing: metrics.labelSpacing) {
                    if !metrics.isCompact { Text(text("Show", "显示")) }
                    LayoutProbe(name: text("Selected", "已选中"), kind: .menu).frame(width: metrics.dropdownWidth, height: 24)
                }
            }
            if page != .agent {
                HStack(spacing: metrics.labelSpacing) {
                    if !metrics.isCompact { Text(text("Sort", "排序")) }
                    LayoutProbe(name: text("By directory", "按目录"), kind: .menu).frame(width: metrics.dropdownWidth, height: 24)
                }
            }
            if page == .applications {
                LayoutProbe(name: text("Quitting…", "正在退出…"), kind: .button)
                    .frame(width: metrics.isCompact ? 80 : 100, height: 24)
            }
        }
    }
}

private struct LayoutProbe: NSViewRepresentable {
    enum Kind { case menu, button }
    let name: String
    let kind: Kind
    func makeNSView(context: Context) -> NSView {
        let view: NSControl
        switch kind {
        case .menu:
            let menu = NSPopUpButton()
            menu.addItem(withTitle: name)
            view = menu
        case .button:
            view = NSButton(title: name, target: nil, action: nil)
        }
        view.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        view.controlSize = .small
        view.identifier = .init("toolbar-probe-" + name)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct ScopeProbe: View {
    let labels: String
    var body: some View {
        ScopePicker(labels: labels.components(separatedBy: " · "), selection: .constant(0))
    }
}
