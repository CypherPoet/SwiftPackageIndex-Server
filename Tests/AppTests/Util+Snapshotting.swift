@testable import App

import Plot
import SnapshotTesting

#if canImport(WebKit)
import WebKit
#endif


extension Snapshotting where Value == () -> HTML, Format == String {
    public static var html: Snapshotting {
        Snapshotting<String, String>.lines.pullback { node in
            Current.siteURL = { "http://localhost:8080" }
            return node().render(indentedBy: .spaces(2))
        }
    }
}


#if os(macOS)
extension Snapshotting where Value == () -> HTML, Format == NSImage {
    public static func image(precision: Float = 1, size: CGSize? = nil, rootDir: URL) -> Snapshotting {
        Current.siteURL = { String(rootDir.absoluteString.dropLast()) }
        return image(precision: precision, size: size, baseURL: rootDir)
    }

    public static func image(precision: Float = 1, size: CGSize? = nil, baseURL: URL) -> Snapshotting {
        Snapshotting<NSView, NSImage>.image(precision: precision, size: size).pullback { node in
            let html = node().render()
            let webView = WKWebView()

            let htmlURL = baseURL.appendingPathComponent(TempWebRoot.fileName)

            // Save HTML file at root of public directory
            do {
                try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            } catch {
                fatalError("Snapshotting: 💥 Failed to write index.html: \(error)")
            }

            // Load the HTML file into the web view with access to public directory
            webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)

            return webView
        }
    }
}
#endif

