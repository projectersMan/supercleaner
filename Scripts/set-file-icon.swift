import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: set-file-icon.swift /absolute/path/icon.icns /absolute/path/file\n", stderr)
    exit(64)
}

let iconPath = CommandLine.arguments[1]
let targetPath = CommandLine.arguments[2]
guard let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("FAIL: could not load icon at \(iconPath)\n", stderr)
    exit(1)
}

guard NSWorkspace.shared.setIcon(icon, forFile: targetPath, options: []) else {
    fputs("FAIL: could not set custom icon on \(targetPath)\n", stderr)
    exit(1)
}
