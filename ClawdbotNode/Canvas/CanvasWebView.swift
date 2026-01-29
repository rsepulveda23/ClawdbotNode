import WebKit
import SwiftUI

/// WKWebView wrapper for canvas functionality
class CanvasWebView: NSObject, ObservableObject, WKNavigationDelegate {
    private(set) var webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    func load(url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func evaluateJavaScript(_ script: String) async -> Any? {
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("JS evaluation error: \(error)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    func snapshot(format: String, maxWidth: Int, quality: Double) async -> Data? {
        let config = WKSnapshotConfiguration()

        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: config) { image, error in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }

                // Resize if needed
                let resized = self.resizeImage(image, maxWidth: CGFloat(maxWidth))

                // Encode
                let data: Data?
                if format.lowercased() == "png" {
                    data = resized.pngData()
                } else {
                    data = resized.jpegData(compressionQuality: quality)
                }

                continuation.resume(returning: data)
            }
        }
    }

    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }

        let scale = maxWidth / image.size.width
        let newSize = CGSize(width: maxWidth, height: image.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized ?? image
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Canvas loaded: \(webView.url?.absoluteString ?? "")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Canvas navigation failed: \(error)")
    }
}

// MARK: - SwiftUI Wrapper
struct CanvasWebViewRepresentable: UIViewRepresentable {
    let webView: CanvasWebView

    func makeUIView(context: Context) -> WKWebView {
        return webView.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Updates handled by the CanvasWebView class
    }
}
