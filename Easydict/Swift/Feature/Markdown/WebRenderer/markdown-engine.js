import MarkdownIt from 'markdown-it';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import { KaTeXRenderer } from './katex-renderer.js';

// Never interpret model output as HTML or let TeX access URLs / HTML extensions.
const parser = new MarkdownIt({ html: false, linkify: true, typographer: false, maxNesting: 20 });
parser.use(texmath, {
    engine: katex,
    delimiters: ['dollars', 'brackets']
});
// Own the token-to-HTML boundary: texmath's replacement-string templates interpret
// dollar replacement patterns in KaTeX output (including the original TeX annotation).
// Direct concatenation preserves the original source and gives a bounded formula cache.
const formulas = new KaTeXRenderer();
parser.renderer.rules.math_inline = (tokens, index) => formulas.render(tokens[index].content);
parser.renderer.rules.math_inline_double = (tokens, index) => formulas.render(tokens[index].content, true);
parser.renderer.rules.math_block = (tokens, index) => formulas.render(tokens[index].content, true);
parser.renderer.rules.math_block_eqno = (tokens, index) => {
    const token = tokens[index];
    return '<div class="math-numbered">' + formulas.render(token.content, true) +
        '<span class="math-equation-number">(' + parser.utils.escapeHtml(token.info || '') + ')</span></div>';
};
// Images are intentionally text-only: even displaying an external image leaks data.
parser.renderer.rules.image = (tokens, index) => parser.utils.escapeHtml(tokens[index].content);
parser.validateLink = value => /^(https?:|mailto:|#)/i.test(value);

/** Parse source only. The presentation layer must sanitize before DOM insertion. */
export function renderMarkdown(source) {
    return parser.render(source);
}
