import katex from 'katex';

const maxEntries = 128;
const maxBytes = 1024 * 1024;
const escapeHTML = text => text.replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[char]);

/** Bounded per-view formula cache; policy and macro state never depend on prior translations. */
export class KaTeXRenderer {
    constructor() {
        this.entries = new Map();
        this.bytes = 0;
    }

    render(source, displayMode = false) {
        const key = (displayMode ? 'block:' : 'inline:') + source;
        const cached = this.entries.get(key);
        if (cached) {
            this.entries.delete(key);
            this.entries.set(key, cached);
            return cached.html;
        }
        let html;
        try {
            html = katex.renderToString(source, {
                displayMode, trust: false, throwOnError: false, strict: 'ignore',
                maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml',
                // KaTeX can mutate macros (e.g. \\gdef). Never share them across formulas.
                macros: Object.create(null)
            });
        } catch {
            html = escapeHTML(source);
        }
        const bytes = (key.length + html.length) * 2;
        if (bytes <= maxBytes && source.length <= 8192) {
            while (this.entries.size >= maxEntries || this.bytes + bytes > maxBytes) {
                const oldestKey = this.entries.keys().next().value;
                this.bytes -= this.entries.get(oldestKey).bytes;
                this.entries.delete(oldestKey);
            }
            this.entries.set(key, { html, bytes });
            this.bytes += bytes;
        }
        return html;
    }
}
