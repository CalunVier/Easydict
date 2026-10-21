//
//  RichMarkdownView.swift
//  Easydict
//
//  Offline Markdown presentation, isolated from dictionary HTML rendering.
//

import AppKit
import WebKit

/// Displays untrusted Markdown using bundled assets and an isolated, ephemeral web view.
/// The owner controls the viewport height; content height is reported asynchronously.
@objc(EDRichMarkdownView)
final class RichMarkdownView: NSView, WKNavigationDelegate {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureWebView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureWebView()
    }

    // MARK: Internal

    @objc var heightDidChange: ((CGFloat) -> Void)?
    @objc private(set) var contentHeight: CGFloat = 24

    /// Updates source without reloading the document. Arguments cross the JS bridge as data,
    /// never as interpolated executable source. Intermediate streaming updates are coalesced.
    @objc(updateMarkdown:fontSize:)
    func updateMarkdown(_ source: String, fontSize: CGFloat) {
        guard self.source != source || self.fontSize != fontSize else { return }
        self.source = source
        self.fontSize = fontSize
        revision += 1
        scheduleRender()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        revision += 1
        scheduleRender()
    }

    override func layout() {
        super.layout()
        if failed { updateFallback() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        scheduleRender()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showFallback()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFallback()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showFallback()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // Only the initial bundled document can navigate inside this view.
        if navigationAction.navigationType == .other,
           navigationAction.targetFrame?.isMainFrame == true,
           url == documentURL {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated,
           let scheme = url.scheme?.lowercased(),
           ["https", "http", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    // MARK: Private

    private var webView: WKWebView?
    private var documentURL: URL?
    private var source = ""
    private var fontSize: CGFloat = 14
    private var revision = 0
    private var ready = false
    private var failed = false
    private var rendering = false
    private var scheduledRender: DispatchWorkItem?
    private var fallback: EZLabel?
    private var fallbackScrollView: NSScrollView?
    private var contextSelection = ""

    private func configureWebView() {
        guard let directory = Bundle.main.url(forResource: "MarkdownResources", withExtension: nil),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path)
        else {
            showFallback()
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let handler = HeightMessageHandler(owner: self)
        configuration.userContentController.add(handler, name: "markdownHeight")
        configuration.userContentController.add(handler, name: "markdownContextMenu")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.webView = webView
        let url = directory.appendingPathComponent("index.html")
        documentURL = url
        webView.loadFileURL(url, allowingReadAccessTo: directory)
    }

    private func scheduleRender() {
        scheduledRender?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if failed { updateFallback() } else { renderIfReady() }
        }
        scheduledRender = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func renderIfReady() {
        guard ready, !rendering, let webView else { return }
        rendering = true
        let submittedRevision = revision
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        webView.callAsyncJavaScript(
            "window.EDMarkdown.render(source, fontSize, dark, revision);",
            arguments: ["source": source, "fontSize": Double(fontSize), "dark": dark, "revision": revision],
            in: nil,
            contentWorld: .page
        ) { [weak self] result in
            guard let self else { return }
            rendering = false
            if case .failure = result {
                showFallback()
            } else if submittedRevision != revision {
                scheduleRender()
            }
        }
    }

    fileprivate func receiveHeight(_ message: WKScriptMessage) {
        guard !failed, message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        if message.name == "markdownContextMenu" {
            showContextMenu(body)
            return
        }
        guard let messageRevision = body["revision"] as? Int, messageRevision == revision,
              let number = body["height"] as? NSNumber else { return }
        publishHeight(CGFloat(number.doubleValue))
    }

    private func publishHeight(_ height: CGFloat) {
        guard height.isFinite, height >= 0 else { return }
        let height = max(24, ceil(height))
        guard abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
        heightDidChange?(height)
    }

    private func showContextMenu(_ body: [String: Any]) {
        guard let text = body["text"] as? String, !text.isEmpty,
              let x = body["x"] as? Double, let y = body["y"] as? Double,
              x.isFinite, y.isFinite, let webView, window != nil else { return }
        contextSelection = text
        let menu = NSMenu()
        let query = NSMenuItem(title: NSLocalizedString("query_in_app", comment: ""),
                               action: #selector(querySelection), keyEquivalent: "")
        query.target = self
        menu.addItem(query)
        let copy = NSMenuItem(title: NSLocalizedString("copy_text", comment: ""),
                              action: #selector(copySelection), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        let pointX = min(max(0, CGFloat(x)), webView.bounds.width)
        let pointY = min(max(0, CGFloat(y)), webView.bounds.height)
        let point = NSPoint(x: pointX,
                            y: webView.isFlipped ? pointY : webView.bounds.height - pointY)
        menu.popUp(positioning: nil, at: point, in: webView)
    }

    @objc private func copySelection() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextSelection, forType: .string)
    }

    @objc private func querySelection() {
        EZQueryMenuTextView.queryInApp(contextSelection)
    }

    /// Keep the original translation available if resources or the web process fail.
    private func showFallback() {
        failed = true
        webView?.stopLoading()
        webView?.isHidden = true
        if fallback == nil {
            let label = EZLabel(frame: .zero)
            let scrollView = NSScrollView(frame: bounds)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            label.isVerticallyResizable = true
            label.isHorizontallyResizable = false
            label.autoresizingMask = [.width]
            scrollView.documentView = label
            addSubview(scrollView)
            fallback = label
            fallbackScrollView = scrollView
        }
        updateFallback()
    }

    private func updateFallback() {
        guard let fallback else { return }
        fallback.font = .systemFont(ofSize: fontSize)
        fallback.text = source
        guard bounds.width > 0, let layoutManager = fallback.layoutManager,
              let textContainer = fallback.textContainer else { return }
        let width = fallbackScrollView?.contentSize.width ?? bounds.width
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + 8
        fallback.setFrameSize(NSSize(width: width, height: max(height, bounds.height)))
        // Avoid modifying the parent's constraints inside its layout pass.
        let expectedRevision = revision
        DispatchQueue.main.async { [weak self] in
            guard let self, revision == expectedRevision else { return }
            publishHeight(height)
        }
    }
}

/// WKUserContentController retains its handler; this weak proxy breaks the view retain cycle.
private final class HeightMessageHandler: NSObject, WKScriptMessageHandler {
    init(owner: RichMarkdownView) { self.owner = owner }
    private weak var owner: RichMarkdownView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receiveHeight(message)
    }
}
