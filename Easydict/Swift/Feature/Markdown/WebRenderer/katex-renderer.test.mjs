import { test, afterEach } from 'node:test';
import katex from 'katex';
import assert from 'node:assert/strict';
import { KaTeXRenderer } from './katex-renderer.js';

const originalRender = katex.renderToString;
afterEach(() => { katex.renderToString = originalRender; });
function withEngine(engine) {
    katex.renderToString = engine.renderToString;
    return new KaTeXRenderer();
}

test('unchanged formulas reuse work but inline/display modes remain distinct', () => {
    let calls = 0;
    const engine = withEngine({ renderToString(source, options) { calls++; return source + options.displayMode; } });
    for (let index = 0; index < 20; index++) {
        for (let formula = 0; formula < 40; formula++) engine.render(`x_${formula}`);
    }
    assert.equal(calls, 40);
    engine.render('x_0', true);
    assert.equal(calls, 41);
});

test('LRU evicts oldest formulas at entry bound', () => {
    let calls = 0;
    const renderer = withEngine({ renderToString(source) { calls++; return source; } });
    for (let index = 0; index < 129; index++) renderer.render(String(index));
    renderer.render('128');
    assert.equal(calls, 129);
    renderer.render('0');
    assert.equal(calls, 130);
});

test('byte budget evicts large entries and oversized entries are never cached', () => {
    let calls = 0;
    const renderer = withEngine({ renderToString() { calls++; return 'x'.repeat(300000); } });
    renderer.render('a'); renderer.render('b'); renderer.render('a');
    assert.equal(calls, 3);
    let hugeCalls = 0;
    const huge = withEngine({ renderToString() { hugeCalls++; return 'x'.repeat(600000); } });
    huge.render('x'); huge.render('x');
    assert.equal(hugeCalls, 2);
});

test('macro state and trust policy are fresh on every cache miss', () => {
    const macros = [];
    const renderer = withEngine({ renderToString(source, options) {
        assert.equal(options.trust, false);
        assert.equal(options.maxExpand, 1000);
        assert.equal(options.macros.secret, undefined);
        macros.push(options.macros);
        options.macros.secret = source;
        return source;
    } });
    renderer.render('a'); renderer.render('b');
    assert.notEqual(macros[0], macros[1]);
});

test('renderer exceptions preserve escaped source', () => {
    const renderer = withEngine({ renderToString() { throw Error('invalid'); } });
    assert.equal(renderer.render('<img> &'), '&lt;img&gt; &amp;');
});
