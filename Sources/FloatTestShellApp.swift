import SwiftUI

/// Independent test shell. It does NOT share a data container with the existing PWA.
@main
struct FloatTestShellApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserHost()
                .ignoresSafeArea()
                .onChange(of: scenePhase) { phase in
                    NativeDiagnostics.shared.record("scene_\(phase)")
                }
        }
    }
}

struct BrowserHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BrowserViewController {
        BrowserViewController()
    }

    func updateUIViewController(_ uiViewController: BrowserViewController, context: Context) {
        // Never recreate the WKWebView for a SwiftUI state update.
    }
}
