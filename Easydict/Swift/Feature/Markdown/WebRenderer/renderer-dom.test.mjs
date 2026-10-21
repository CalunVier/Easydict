import { afterEach, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';

const bundle = await readFile(new URL('../MarkdownResources/renderer.js', import.meta.url), 'utf8');
let dom;
let window;
beforeEach(() => {
    dom = new JSDOM('<!doctype html><main id="content"></main>', { runScripts: 'outside-only', pretendToBeVisual: true });
    window = dom.window;
    window.ResizeObserver = class { observe() {} };
    Object.defineProperty(window.document, 'fonts', { value: { ready: Promise.resolve() } });
    Object.defineProperty(window.document, 'scrollingElement', { value: window.document.documentElement });
    window.webkit = { messageHandlers: { markdownHeight: { postMessage() {} } } };
    window.eval(bundle);
});
afterEach(() => { window.close(); });
const render = source => window.EDMarkdown.render(source, 14, false, 1);

test('sanitization preserves table structure and KaTeX MathML', () => {
    render('|A|B|\n|-|-|\n|1|2|\n\n$\\frac{1}{2}$');
    assert.equal(window.document.querySelectorAll('table tbody td').length, 2);
    assert.equal(window.document.querySelectorAll('math mfrac').length, 1);
});

test('hostile HTML, script text and image URLs stay inert', () => {
    render('<img src=x onerror="window.pwned=1"><script>window.pwned=1</script>\n![alt](https://example.com)\n[x](javascript:alert(1))\n[x](file:///etc/passwd)');
    assert.equal(window.pwned, undefined);
    assert.equal(window.document.querySelectorAll('#content script, #content img, #content iframe').length, 0);
    assert.equal(window.document.querySelectorAll('a[href^="javascript:"], a[href^="file:"]').length, 0);
});

test('quotes and closing script sequences remain data', () => {
    const source = `</script>\"';window.pwned=1;//`;
    render(source);
    assert.equal(window.pwned, undefined);
    assert.equal(window.document.getElementById('content').textContent.trim(), source);
});

test('safe links remain links and unsafe TeX stays inert', () => {
    render(String.raw`[good](https://example.com) $\href{javascript:alert(1)}{bad}$ $\includegraphics{https://example.com/private}$`);
    assert.equal(window.document.querySelector('a')?.getAttribute('href'), 'https://example.com');
    assert.equal(window.document.querySelectorAll('img, a[href^="javascript:"]').length, 0);
});

test('streaming keeps unchanged math/table nodes and scroll state', () => {
    const prefix = '$$x^2$$\n\n|A|B|\n|-|-|\n|1|2|\n\n';
    render(prefix + 'First');
    const math = window.document.querySelector('.katex-display');
    const table = window.document.querySelector('.table-scroll');
    table.scrollLeft = 10;
    render(prefix + 'First tail');
    assert.equal(window.document.querySelector('.katex-display'), math);
    assert.equal(window.document.querySelector('.table-scroll'), table);
    assert.equal(table.scrollLeft, 10);
});

test('rewritten and removed blocks replace old content without stale nodes', () => {
    render('**old**\n\n$$x$$\n\nend');
    render('**new**');
    assert.equal(window.document.querySelectorAll('.katex').length, 0);
    assert.equal(window.document.querySelector('strong').textContent, 'new');
});

test('late reference definitions update earlier blocks', () => {
    render('[reference][target]\n\n**stable**');
    const stable = window.document.querySelector('strong');
    render('[reference][target]\n\n**stable**\n\n[target]: https://example.com');
    assert.equal(window.document.querySelector('a')?.getAttribute('href'), 'https://example.com');
    assert.equal(window.document.querySelector('strong'), stable);
});

test('math source dollar-backtick is not interpreted as replacement syntax', () => {
    const tex = '\\text{\\$`}';
    render('\\(' + tex + '\\)');
    assert.equal(window.document.querySelector('annotation').textContent, tex);
});


test('malformed TeX containing dollar-ampersand preserves error text', () => {
    const tex = '\\text{\\$&}';
    render('$' + tex + '$');
    assert.equal(window.document.querySelector('.katex-error').textContent, tex);
});
