import DOMPurify from 'dompurify';
import { renderMarkdown } from './markdown-engine.js';
import { updateContent } from './dom-update.js';

const root = document.getElementById('content');
let revision = 0;
let pending = null;
let heightFrame = 0;

function reportHeight() {
    cancelAnimationFrame(heightFrame);
    heightFrame = requestAnimationFrame(() => {
        window.webkit?.messageHandlers.markdownHeight.postMessage({
            revision, height: Math.ceil(root.getBoundingClientRect().height)
        });
    });
}

function hasSelection() {
    const selection = window.getSelection();
    return selection && !selection.isCollapsed && root.contains(selection.anchorNode);
}

function render(source, fontSize, dark, nextRevision) {
    if (hasSelection()) {
        pending = [source, fontSize, dark, nextRevision];
        return;
    }
    pending = null;
    revision = nextRevision;
    document.documentElement.style.fontSize = `${Math.max(8, Math.min(72, fontSize))}px`;
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    const scrolling = document.scrollingElement;
    const previousTop = scrolling.scrollTop;
    const wasAtBottom = scrolling.scrollHeight > scrolling.clientHeight &&
        scrolling.scrollHeight - scrolling.clientHeight - previousTop < 4;
    try {
        // Large outputs remain readable without spending unbounded time parsing them.
        if (source.length > 250000) {
            root.textContent = source;
            root.classList.add('plain');
        } else {
            root.classList.remove('plain');
            const fragment = DOMPurify.sanitize(renderMarkdown(source), {
                RETURN_DOM_FRAGMENT: true,
                USE_PROFILES: { html: true, mathMl: true, svg: true },
                // Preserve KaTeX's inert TeX annotation for accessible MathML.
                // Do not allow annotation-xml (an HTML integration point).
                ADD_TAGS: ['semantics', 'annotation'],
                FORBID_TAGS: ['style', 'script', 'iframe', 'object', 'embed', 'form', 'img', 'input'],
                FORBID_ATTR: ['src', 'srcset', 'formaction', 'action', 'id', 'name'],
                ALLOW_DATA_ATTR: false
            });
            for (const link of fragment.querySelectorAll('a')) {
                const href = link.getAttribute('href') || '';
                if (!/^(https?:|mailto:|#)/i.test(href)) link.removeAttribute('href');
                link.setAttribute('rel', 'noreferrer noopener');
            }
            for (const table of fragment.querySelectorAll('table')) {
                const wrapper = document.createElement('div');
                wrapper.className = 'table-scroll';
                table.replaceWith(wrapper);
                wrapper.append(table);
            }
            updateContent(root, fragment);
        }
    } catch {
        // A malformed / unfinished expression must not blank the translation.
        root.textContent = source;
        root.classList.add('plain');
    }
    scrolling.scrollTop = wasAtBottom ? scrolling.scrollHeight : previousTop;
    reportHeight();
    document.fonts.ready.then(reportHeight);
}

new ResizeObserver(reportHeight).observe(root);
document.addEventListener('selectionchange', () => {
    if (pending && !hasSelection()) render(...pending);
});
window.EDMarkdown = Object.freeze({ render });

// Preserve selection lookup without exposing arbitrary web navigation to native code.
document.addEventListener('contextmenu', event => {
    if (!event.isTrusted) return;
    let text = window.getSelection()?.toString().trim();
    if (!text) {
        const range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
        const node = range?.startContainer;
        if (node?.nodeType === Node.TEXT_NODE && root.contains(node)) {
            const words = new Intl.Segmenter(undefined, { granularity: 'word' }).segment(node.textContent);
            const word = [...words].find(word => word.isWordLike && word.index <= range.startOffset &&
                range.startOffset < word.index + word.segment.length);
            if (word) text = word.segment;
        }
    }
    if (!text) return;
    event.preventDefault();
    window.webkit?.messageHandlers.markdownContextMenu.postMessage({
        text, x: event.clientX, y: event.clientY
    });
});
