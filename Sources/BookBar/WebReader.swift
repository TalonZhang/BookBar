import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct WebReader: NSViewRepresentable {
    let book: Book
    let folder: URL
    let request: ReaderRequest
    let preferences: ReaderPreferences
    let palette: Palette
    let visible: Bool
    let onPosition: (ReadingPosition, UUID) -> Void
    let onLink: (Int, String?) -> Void
    let onError: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(coordinator.resources, forURLScheme: BookResources.scheme)
        configuration.userContentController.add(coordinator.messages, contentWorld: Coordinator.world, name: "progress")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        coordinator.prepareBackground(in: view)
        coordinator.installContentRules(in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.isHidden == visible { view.isHidden = !visible }
        context.coordinator.parent = self
        context.coordinator.update(view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "progress", contentWorld: Coordinator.world)
        view.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        static let world = WKContentWorld.world(name: "BookBarReader")

        var parent: WebReader
        let resources: BookResources
        fileprivate lazy var messages = ProgressReceiver(self)
        private var rulesReady = false
        private var loadedToken: UUID?
        private var navigation: WKNavigation?
        private var initialURL: URL?
        private var displayed = false
        private var styled: (ReaderPreferences, Palette)?
        private var hasTransparentBacking = false
        private var reported: ReadingPosition?

        init(_ parent: WebReader) {
            self.parent = parent
            resources = BookResources(folder: parent.folder, bookID: parent.book.id,
                                      chapters: Set(parent.book.chapters.map(\.path)))
        }

        func installContentRules(in view: WKWebView) {
            let rules = "[" + ["http", "https", "file", "ftp", "ws", "wss"].map { scheme in
                """
                {"trigger":{"url-filter":"^\(scheme):"},"action":{"type":"block"}}
                """
            }.joined(separator: ",") + "]"
            let identifier = "BookBarOffline_v2"
            guard let rulesStore = WKContentRuleListStore.default() else {
                DispatchQueue.main.async { [weak self] in self?.parent.onError("无法初始化本地阅读视图。") }
                return
            }
            let install: (WKContentRuleList?, Error?) -> Void = { [weak self, weak view] list, error in
                guard let self, let view else { return }
                guard let list else {
                    NSLog("BookBar content rules: %@", error?.localizedDescription ?? "unknown error")
                    self.parent.onError("无法初始化本地阅读视图。")
                    return
                }
                view.configuration.userContentController.add(list)
                self.rulesReady = true
                self.update(view)
            }
            rulesStore.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                if let list { install(list, nil) }
                else { rulesStore.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules, completionHandler: install) }
            }
        }

        func update(_ view: WKWebView) {
            guard rulesReady else { return }
            let request = parent.request
            if loadedToken != request.token {
                guard parent.book.chapters.indices.contains(request.chapter),
                      let url = resources.url(for: parent.book.chapters[request.chapter].path) else { return }
                loadedToken = request.token
                displayed = false
                reported = nil
                styled = nil
                initialURL = url
                configureBackground(in: view)
                navigation = view.load(URLRequest(url: url))
            } else if displayed, styled?.0 != parent.preferences || styled?.1 != parent.palette {
                applyStyle(to: view, initial: false)
            }
        }

        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.navigationType == .linkActivated {
                if let resource = resources.resolve(url),
                   let index = parent.book.chapters.firstIndex(where: { $0.path == resource.path }) {
                    DispatchQueue.main.async { [weak self] in self?.parent.onLink(index, resource.fragment) }
                }
                decisionHandler(.cancel)
                return
            }
            let allow = action.targetFrame?.isMainFrame == true && !displayed && url == initialURL
            decisionHandler(allow ? .allow : .cancel)
        }

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === self.navigation else { return }
            displayed = true
            parent.onError(nil)
            applyStyle(to: view, initial: true)
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(for: navigation, error: error)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showError(for: navigation, error: error)
        }

        func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
            loadedToken = nil
            update(view)
        }

        private func showError(for navigation: WKNavigation?, error: Error) {
            guard navigation === self.navigation, (error as NSError).code != NSURLErrorCancelled else { return }
            parent.onError("这一节暂时无法显示。")
        }

        private func applyStyle(to view: WKWebView, initial: Bool) {
            let request = parent.request
            let preferences = parent.preferences
            let palette = parent.palette
            styled = (preferences, palette)
            let transparent = configureBackground(in: view)
            let arguments: [String: Any] = [
                "css": Self.styles(preferences, theme: palette.colors, transparent: transparent),
                "position": initial ? request.fraction : (reported?.fraction ?? request.fraction),
                "fragment": initial ? (request.fragment ?? "") : "",
                "generation": request.token.uuidString
            ]
            Task { [weak self, weak view] in
                guard let self, let view, self.loadedToken == request.token else { return }
                do {
                    _ = try await view.callAsyncJavaScript(Self.configure, arguments: arguments, in: nil, contentWorld: Self.world)
                } catch where self.loadedToken == request.token {
                    self.parent.onError("无法应用正文排版。")
                } catch {}
            }
        }

        fileprivate func receive(_ message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any],
                  let token = body["token"] as? String, parent.request.token.uuidString == token,
                  let fraction = body["fraction"] as? Double, fraction.isFinite else { return }
            let position = ReadingPosition(chapter: parent.request.chapter, fraction: min(1, max(0, fraction)))
            reported = position
            parent.onPosition(position, parent.request.token)
        }

        func prepareBackground(in view: WKWebView) {
            // Keep the backing mode fixed so switching colors does not reset WebKit's scroll view.
            if view.responds(to: NSSelectorFromString("_setDrawsBackground:")) {
                view.setValue(false, forKey: "drawsBackground")
                hasTransparentBacking = true
            }
            configureBackground(in: view)
        }

        @discardableResult
        private func configureBackground(in view: WKWebView) -> Bool {
            let palette = parent.palette
            let transparent = palette.isTranslucent && hasTransparentBacking
            view.underPageBackgroundColor = transparent ? .clear : NSColor(hex: palette.colors.background)
            return transparent
        }

        private static func styles(_ prefs: ReaderPreferences, theme: ReadingTheme, transparent: Bool) -> String {
            let background = transparent ? "transparent" : theme.background
            return """
            :root, html, body {
              color: \(theme.ink) !important;
              background: \(background) !important;
              color-scheme: \(theme == .night ? "dark" : "light");
              overflow-wrap: anywhere;
            }
            html { margin: 0 !important; padding: 0 !important; }
            body {
              box-sizing: border-box !important;
              margin: 0 auto !important; padding: 22px clamp(18px, 6vw, 38px) 28px !important;
              width: auto !important; min-width: 0 !important; max-width: 740px !important;
              font: \(prefs.fontSize)px/\(prefs.lineHeight) "New York", "Songti SC", Georgia, serif !important;
              text-align: start !important;
            }
            body :where(p, div, section, article, span, li, blockquote, td, th, dt, dd) {
              font-size: inherit !important;
              line-height: inherit !important;
              color: inherit !important;
              background-color: transparent !important;
            }
            p { margin-block: 0 0.85em !important; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.35 !important; color: inherit !important; }
            h1 { font-size: 1.55em !important; margin-block: 0.15em 0.75em !important; }
            h2 { font-size: 1.3em !important; }
            h3 { font-size: 1.15em !important; }
            img, svg, video { max-width: 100% !important; height: auto !important; }
            pre { white-space: pre-wrap !important; }
            a { color: \(theme.accent) !important; text-underline-offset: 0.15em; }
            table { max-width: 100% !important; }
            .pb-plain { white-space: pre-wrap; }
            """
        }

        private static let configure = """
        const style = document.getElementById("__bookbar_style") || document.createElement("style");
        style.id = "__bookbar_style";
        style.textContent = css;
        (document.head || document.documentElement).appendChild(style);
        const root = document.scrollingElement;
        if (!root) return;
        const range = () => Math.max(0, root.scrollHeight - root.clientHeight);
        const current = () => range() > 1 ? Math.max(0, Math.min(1, root.scrollTop / range())) : 1;
        const existing = globalThis.bookBarReader;
        if (existing) existing.stop();
        let timer = 0;
        let active = false;
        const report = () => {
          if (active) window.webkit.messageHandlers.progress.postMessage({token: generation, fraction: current()});
        };
        const scrolled = () => {
          if (!timer && active) timer = setTimeout(() => { timer = 0; report(); }, 70);
        };
        window.addEventListener("scroll", scrolled, {passive: true});
        globalThis.bookBarReader = {stop() {
          active = false;
          clearTimeout(timer);
          window.removeEventListener("scroll", scrolled);
        }};
        const handler = globalThis.bookBarReader;
        await new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)));
        if (globalThis.bookBarReader !== handler) return;
        const destination = fragment && (document.getElementById(fragment) || document.getElementsByName(fragment)[0]);
        if (destination) destination.scrollIntoView({block: "start", behavior: "instant"});
        else root.scrollTo({top: position * range(), behavior: "instant"});
        active = true;
        report();
        """
    }
}

@MainActor
private final class ProgressReceiver: NSObject, WKScriptMessageHandler {
    weak var coordinator: WebReader.Coordinator?

    init(_ coordinator: WebReader.Coordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        coordinator?.receive(message)
    }
}

@MainActor
final class BookResources: NSObject, WKURLSchemeHandler {
    static let scheme = "pb-book"
    private let folder: URL
    private let host: String
    private let chapters: Set<String>

    init(folder: URL, bookID: UUID, chapters: Set<String>) {
        self.folder = folder
        host = bookID.uuidString.lowercased()
        self.chapters = chapters
    }

    func url(for path: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = host
        parts.path = "/" + path
        return parts.url
    }

    func resolve(_ url: URL) -> BookResource? {
        guard url.scheme == Self.scheme, url.host == host,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = parts.percentEncodedPath.removingPercentEncoding,
              path.hasPrefix("/"), ZipArchive.isSafe(String(path.dropFirst())) else { return nil }
        return BookResource(path: String(path.dropFirst()), fragment: parts.fragment)
    }

    func webView(_ view: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let resource = resolve(url) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        do {
            let file = folder.appendingPathComponent(resource.path)
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let mime: String
            if chapters.contains(resource.path) {
                // EPUB XHTML is UTF-8 or UTF-16. A byte-order mark takes precedence in WebKit.
                mime = "text/html; charset=utf-8"
            } else {
                mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            }
            let policy = "default-src 'none'; style-src 'unsafe-inline' pb-book:; img-src pb-book: data:; font-src pb-book: data:; media-src pb-book:; base-uri 'none'; form-action 'none'"
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": mime, "Content-Security-Policy": policy]) else {
                throw URLError(.badServerResponse)
            }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ view: WKWebView, stop task: WKURLSchemeTask) {}
}
