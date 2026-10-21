import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from './markdown-engine.js';

test('Markdown tables, nesting and strike are parsed', () => {
    const html = renderMarkdown('|A|B|\n|-|-|\n|**one**|two|\n\n- Outer\n  - Inner\n\n~~gone~~');
    assert.match(html, /<table>/);
    assert.match(html, /<strong>one<\/strong>/);
    assert.match(html, /<ul>[\s\S]*<ul>/);
    assert.match(html, /<s>gone<\/s>/);
});

test('all math delimiters produce accessible KaTeX output', () => {
    const html = renderMarkdown(String.raw`Inline $x^2$ and \(y_1\).

$$\frac{a}{b}$$

\[\begin{pmatrix}1&2\\3&4\end{pmatrix}\]`);
    assert.equal((html.match(/class="katex"/g) || []).length, 4);
    assert.equal((html.match(/<math /g) || []).length, 4);
});

test('math inside fenced and inline code stays code', () => {
    const html = renderMarkdown('`$x$`\n\n```latex\n\\[a+b\\]\n```');
    assert.doesNotMatch(html, /class="katex"/);
    assert.match(html, /<code>\$x\$<\/code>/);
});

test('unfinished streaming math is preserved and later rendered', () => {
    assert.match(renderMarkdown('Text $\\frac{1}{'), /frac/);
    assert.match(renderMarkdown('Text $\\frac{1}{2}$'), /class="katex"/);
});

test('raw HTML, dangerous links and images remain inactive', () => {
    const html = renderMarkdown('<script>alert(1)</script>\n![alt](https://example.com/private)\n[bad](javascript:alert(1))\n[file](file:///etc/passwd)');
    assert.doesNotMatch(html, /<script|<img|href="(?:javascript|file):/);
    assert.match(html, /&lt;script&gt;/);
});

test('TeX cannot enable trusted URL/HTML extensions', () => {
    const html = renderMarkdown(String.raw`$\href{javascript:alert(1)}{bad}$ $\includegraphics{https://example.com/leak}$`);
    assert.doesNotMatch(html, /href="javascript:|<img/);
});

test('invalid TeX is readable rather than throwing', () => {
    assert.match(renderMarkdown('$\\notarealcommand{x}$'), /notarealcommand/);
});

test('TeX macros do not leak into later translations', () => {
    renderMarkdown(String.raw`$\gdef\myprivateword{SECRET}\myprivateword$`);
    assert.doesNotMatch(renderMarkdown(String.raw`$\myprivateword$`), /SECRET/);
});

test('TeX annotation preserves dollar replacement patterns verbatim', () => {
    const html = renderMarkdown(String.raw`\(\text{\$\&}\)`);
    assert.match(html, /\\text\{\\\$\\&amp;\}/);
    const backtick = renderMarkdown(String.raw`\(\text{\$\x60}\)`.replace('\\x60', '`'));
    assert.doesNotMatch(backtick, /&lt;eq&gt;|<eq>/);
});
