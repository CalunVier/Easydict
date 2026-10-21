import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright-core';

let browser;
let page;
const requests = [];
before(async () => {
    browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', headless: true });
});
after(async () => { await browser?.close(); });
beforeEach(async () => {
    await page?.close();
    requests.length = 0;
    page = await browser.newPage({ viewport: { width: 420, height: 600 } });
    page.on('request', request => requests.push(request.url()));
    await page.addInitScript(() => {
        window.heightMessages = [];
        window.webkit = { messageHandlers: { markdownHeight: { postMessage(value) { window.heightMessages.push(value); } } } };
    });
    await page.goto(new URL('../MarkdownResources/index.html', import.meta.url).href);
    await page.waitForFunction(() => !!window.EDMarkdown);
});
async function render(source, revision = 1, dark = false) {
    await page.evaluate(({ source, revision, dark }) => window.EDMarkdown.render(source, 14, dark, revision), { source, revision, dark });
    await page.waitForFunction(revision => window.heightMessages.some(value => value.revision === revision), revision);
}

test('tables, nested Markdown, links and strikethrough', async () => {
    await render('# Title\n\n| A | B |\n| :- | -: |\n| **bold** | 2 |\n\n- outer\n  - inner\n\n~~removed~~ [link](https://example.com)');
    assert.equal(await page.locator('table tbody tr').count(), 1);
    assert.equal(await page.locator('td strong').textContent(), 'bold');
    assert.equal(await page.locator('ul ul li').textContent(), 'inner');
    assert.equal(await page.locator('s').textContent(), 'removed');
    assert.equal(await page.locator('a').getAttribute('href'), 'https://example.com');
});

test('all four math delimiters with fractions and matrices', async () => {
    await render(String.raw`Inline $x^2$ and \(y_1\).

$$\frac{a}{b}$$

\[\begin{pmatrix}1&2\\3&4\end{pmatrix}\]`);
    assert.equal(await page.locator('.katex').count(), 4);
    assert.equal(await page.locator('math').count(), 4);
    assert.equal(await page.locator('.katex-display').count(), 2);
});

test('math-looking text in code is not interpreted', async () => {
    await render('`$x$`\n\n```latex\n\\[x^2\\]\n```');
    assert.equal(await page.locator('.katex').count(), 0);
    assert.match(await page.locator('pre').textContent(), /x\^2/);
});

test('partial streaming input recovers once complete', async () => {
    await render('A $\\frac{1}{', 1);
    assert.match(await page.locator('#content').textContent(), /frac/);
    await render('A $\\frac{1}{2}$\n\n|A|B|\n|-|-|\n|1|2|', 2);
    assert.equal(await page.locator('.katex').count(), 1);
    assert.equal(await page.locator('table').count(), 1);
    assert.equal(await page.locator('#content').count(), 1);
});

test('untrusted HTML, links, images and TeX cannot execute or fetch', async () => {
    await render(String.raw`<img src="https://example.com/leak" onerror="window.pwned=1">
<script>window.pwned=1</script>
[bad](javascript:alert(1)) [file](file:///etc/passwd)
![secret](https://example.com/secret)
$\href{javascript:alert(1)}{bad}$
$\includegraphics{https://example.com/math}$`);
    assert.equal(await page.evaluate(() => window.pwned), undefined);
    assert.equal(await page.locator('#content script, #content img, #content iframe, #content input').count(), 0);
    assert.equal(await page.locator('#content a[href^="javascript:"], #content a[href^="file:"]').count(), 0);
    assert.equal(requests.filter(url => /^https?:/.test(url)).length, 0);
});

test('wide tables and display equations do not widen the document', async () => {
    await page.setViewportSize({ width: 250, height: 300 });
    await render('|a|b|c|d|e|f|g|h|i|\n|-|-|-|-|-|-|-|-|-|\n|1|2|3|4|5|6|7|8|9|\n\n$$' + 'x+'.repeat(80) + 'x$$');
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    assert.equal(await page.evaluate(() => {
        const container = document.querySelector('.katex-display');
        const formula = container.querySelector('.katex-html');
        container.scrollLeft = 0;
        return formula.getBoundingClientRect().left >= container.getBoundingClientRect().left - 1;
    }), true);
});

test('font changes, dark theme and width changes report height', async () => {
    await render('A long sentence with words that wrap. '.repeat(30));
    const height = await page.locator('#content').evaluate(node => node.getBoundingClientRect().height);
    await page.setViewportSize({ width: 230, height: 600 });
    await page.waitForFunction(height => document.querySelector('#content').getBoundingClientRect().height > height, height);
    await render('**Dark** $x^2$', 2, true);
    assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark');
});

test('selection survives updates and latest pending content is applied', async () => {
    await render('Select this text', 1);
    await page.evaluate(() => {
        const range = document.createRange(); range.selectNodeContents(document.getElementById('content'));
        window.getSelection().addRange(range);
        window.EDMarkdown.render('Intermediate', 14, false, 2);
        window.EDMarkdown.render('Final', 14, false, 3);
    });
    assert.match(await page.locator('#content').textContent(), /Select this text/);
    await page.evaluate(() => window.getSelection().removeAllRanges());
    await page.waitForFunction(() => document.getElementById('content').textContent.includes('Final'));
});

test('large inputs and malformed math remain readable', async () => {
    await render('x'.repeat(250001));
    assert.equal((await page.locator('#content').textContent()).length, 250001);
    await render('$\\notarealcommand{x}$', 2);
    assert.match(await page.locator('#content').textContent(), /notarealcommand/);
});
