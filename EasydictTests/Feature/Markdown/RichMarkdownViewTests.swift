//
//  RichMarkdownViewTests.swift
//  EasydictTests
//

import AppKit
import Testing
import WebKit
@testable import Easydict

/// Exercise the bundled renderer through the real macOS bridge, not a second HTML fixture.
@MainActor
@Suite("Rich Markdown WebKit", .serialized)
struct RichMarkdownViewTests {
    @Test("Bundled resources render tables and accessible math")
    func tablesAndMath() async throws {
        let view = RichMarkdownView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
        view.updateMarkdown("| A | B |\n| - | - |\n| 1 | 2 |\n\n$$\\frac{1}{2}$$", fontSize: 14)
        let web = try #require(view.subviews.compactMap { $0 as? WKWebView }.first)
        try await wait(web, for: "document.querySelectorAll('table').length === 1 && document.querySelectorAll('math').length === 1")
        for _ in 0 ..< 160 where view.contentHeight <= 40 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(view.contentHeight > 40)
        let resources = try await web.evaluateJavaScript("performance.getEntriesByType('resource').map(r => r.name).filter(n => /^https?:/.test(n)).length")
        #expect((resources as? Int) == 0)
    }

    @Test("New content wins over pending streaming updates")
    func latestContentWins() async throws {
        let view = RichMarkdownView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view.updateMarkdown("Old $x", fontSize: 14)
        view.updateMarkdown("Final **translation**", fontSize: 16)
        let web = try #require(view.subviews.compactMap { $0 as? WKWebView }.first)
        try await wait(web, for: "document.querySelector('strong')?.textContent === 'translation'")
        let text = try await web.evaluateJavaScript("document.getElementById('content').textContent")
        #expect((text as? String)?.contains("Old") == false)
    }

    @Test("HTML and image input cannot create active elements")
    func untrustedInput() async throws {
        let view = RichMarkdownView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view.updateMarkdown("<script>window.pwned=1</script>\n![alt](https://example.com/private)\n**done**", fontSize: 14)
        let web = try #require(view.subviews.compactMap { $0 as? WKWebView }.first)
        try await wait(web, for: "document.querySelector('strong')?.textContent === 'done'")
        let hasActiveContent = try await web.evaluateJavaScript("!!window.pwned || document.querySelectorAll('#content img, #content script').length > 0")
        #expect((hasActiveContent as? Bool) == false)
    }

    private func wait(_ web: WKWebView, for predicate: String) async throws {
        for _ in 0 ..< 160 {
            if (try? await web.evaluateJavaScript(predicate)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Bundled Markdown renderer did not reach the expected state")
        throw RenderTimeout()
    }

    private struct RenderTimeout: Error {}
}
