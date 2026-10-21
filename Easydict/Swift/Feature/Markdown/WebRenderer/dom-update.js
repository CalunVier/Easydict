/** Preserve unchanged top-level blocks (including math DOM) during streaming updates.
 * The incoming fragment must already be sanitized and presentation-normalized.
 * Full Markdown parsing is intentional: a new delimiter can change earlier block structure.
 */
export function updateContent(root, fragment) {
    const incoming = [...fragment.childNodes];
    incoming.forEach((node, index) => {
        const current = root.childNodes[index];
        if (!current) root.append(node);
        else if (!current.isEqualNode(node)) current.replaceWith(node);
    });
    while (root.childNodes.length > incoming.length) root.lastChild.remove();
}
