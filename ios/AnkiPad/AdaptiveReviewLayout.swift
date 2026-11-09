/// Display-only card layout. Embedded with the renderer so it also works when
/// the app runs inside a host whose main resource bundle differs from its own.
enum AdaptiveReviewLayout {
    static let script = #"""
(() => {
    const content = document.getElementById('qa');
    if (!content) return;
    // The HTML parser may close #qa early when an imported card contains a
    // malformed closing tag. Recover only nodes belonging to this card,
    // before this renderer script, keeping their identities and listeners.
    const renderer = document.currentScript;
    if (renderer && renderer.parentNode === content.parentNode) {
        let sibling = content.nextSibling;
        while (sibling && sibling !== renderer) {
            const next = sibling.nextSibling;
            content.appendChild(sibling);
            sibling = next;
        }
    }
    const root = document.documentElement;
    const readingScale = Number(document.body.dataset.readingScale) || 1;
    const minimumFont = 24 * readingScale;
    const preserved = 'script,style,svg,math,mjx-container,.MathJax,canvas,button,select,option,a[href^="ankiplay:"],[data-study-layout-preserve],[data-study-media-group]';
    const mediaLimits = new WeakMap();
    const groupSizes = new WeakMap();
    let pending = false;
    let measuredWidth = -1, measuredHeight = -1;
    let measuredViewport = '';
    let mutations;

    const rules = document.createElement('style');
    rules.textContent = `
        html, body, #qa { -webkit-text-size-adjust:100%; text-size-adjust:100%; }
        html { scrollbar-gutter:stable; }
        #qa { display:flow-root; font-size:var(--study-font); line-height:1.28; overflow-wrap:anywhere; }
        #qa .study-reading-text {
            font-size:var(--study-font) !important;
            line-height:1.28 !important;
            overflow-wrap:anywhere;
        }
        #qa > br.study-section-gap { display:none; }
        #qa > br.study-section-gap + * {
            margin-top:clamp(8px,1.6vh,18px) !important;
        }
        #qa input, #qa textarea, #qa button, #qa select {
            max-width:100%; box-sizing:border-box;
        }
        #qa input, #qa textarea { font-size:var(--study-font) !important; }
        #qa audio, #qa video { max-width:100%; }
        #qa a[href^="ankiplay:"] {
            display:inline-flex; align-items:center; justify-content:center;
            font-size:clamp(28px,4vmin,44px) !important; line-height:1 !important;
            min-width:44px; min-height:44px; text-decoration:none !important;
            vertical-align:middle;
        }
        #qa hr { margin-block:clamp(.5em,3vh,1em); }
    `;
    document.head.append(rules);

    function identifyText() {
        const primary = new Set([content]);
        const supporting = new Set();
        const controls = new Set();
        let hasPrimary = false, afterBreak = false;
        function includeParents(element, targets) {
            for (; element; element = element.parentElement) {
                targets.add(element);
                if (element === content) break;
            }
        }
        for (const block of content.childNodes) {
            if (block.nodeType === Node.ELEMENT_NODE && block.matches('hr#answer')) {
                hasPrimary = false;
                afterBreak = false;
                continue;
            }
            if (block.nodeType === Node.ELEMENT_NODE && block.matches('br')) {
                if (hasPrimary) {
                    afterBreak = true;
                    block.classList.toggle('study-section-gap',
                        !!block.nextElementSibling?.matches('div,p,section,article,blockquote'));
                }
                continue;
            }
            const nodes = [];
            if (block.nodeType === Node.TEXT_NODE) nodes.push(block);
            else {
                const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
                while (walker.nextNode()) nodes.push(walker.currentNode);
            }
            const text = nodes.filter(node => node.textContent.trim() && !node.parentElement.closest(preserved));
            if (!text.length) continue;
            const label = text.map(node => node.textContent).join('').trim();
            const explicit = block.nodeType === Node.ELEMENT_NODE && block.matches('small,.example,[data-study-role="example"]');
            const parenthetical = /^[（(][\s\S]*[）)]$/.test(label);
            const targets = hasPrimary && (afterBreak || explicit || parenthetical) ? supporting : primary;
            for (const node of text) includeParents(node.parentElement, targets);
            hasPrimary = true;
        }
        for (const control of content.querySelectorAll('a[href^="ankiplay:"]')) {
            control.style.setProperty('font-size', 'clamp(28px,4vmin,44px)', 'important');
            control.style.setProperty('line-height', '1', 'important');
            control.style.setProperty('text-decoration', 'none', 'important');
            if (!control.parentElement.closest(preserved)) includeParents(control.parentElement, controls);
        }
        const containers = new Set([...primary, ...supporting, ...controls]);
        for (const element of containers) {
            element.classList.add('study-reading-text');
            element.classList.remove('study-supporting-text');
            let size = 'var(--study-font)', lineHeight = '1.28';
            if (!primary.has(element) && supporting.has(element)) {
                size = 'max(' + (18 * readingScale) + 'px,calc(var(--study-font) * 0.62))';
                element.classList.add('study-supporting-text');
            } else if (!primary.has(element) && !supporting.has(element)) {
                size = 'clamp(28px,4vmin,44px)';
                lineHeight = '1';
            }
            element.style.setProperty('font-size', size, 'important');
            element.style.setProperty('line-height', lineHeight, 'important');
        }
    }

    // An image with positioned masks must shrink as one unit. Changing only
    // the image dimensions would leave its annotation coordinates behind.
    function annotatedGroup(media) {
        let parent = media.parentElement;
        while (parent && parent !== content) {
            if (getComputedStyle(parent).position === 'relative' &&
                Array.from(parent.children).some(child => child !== media &&
                    (getComputedStyle(child).position === 'absolute' || child.tagName === 'CANVAS'))) {
                return parent;
            }
            parent = parent.parentElement;
        }
        return null;
    }

    function constrainMedia(height) {
        const media = Array.from(content.querySelectorAll('img,video'));
        const visible = media.filter(element => element.getClientRects().length > 0);
        const budget = height * Math.min(0.55, 0.8 / Math.max(1, visible.length));
        const groups = new Set();
        for (const element of visible) {
            const group = annotatedGroup(element);
            if (group) {
                groups.add(group);
                continue;
            }
            if (!mediaLimits.has(element)) {
                const maximum = parseFloat(getComputedStyle(element).maxHeight);
                mediaLimits.set(element, Number.isFinite(maximum) ? maximum : Infinity);
            }
            const zoom = parseFloat(getComputedStyle(element).zoom) || 1;
            element.style.setProperty('max-height', Math.min(mediaLimits.get(element), budget / zoom) + 'px', 'important');
            element.style.setProperty('object-fit', 'contain');
        }
        for (const group of groups) {
            if (!groupSizes.has(group)) {
                const zoom = parseFloat(getComputedStyle(group).zoom) || 1;
                groupSizes.set(group, { zoom });
                group.dataset.studyMediaGroup = '';
            }
            const original = groupSizes.get(group);
            group.style.zoom = String(original.zoom);
            const naturalHeight = group.getBoundingClientRect().height;
            group.style.zoom = String(original.zoom * Math.min(1, budget / Math.max(1, naturalHeight)));
        }
    }

    function dimensions() {
        const box = content.getBoundingClientRect();
        let height = Math.max(content.scrollHeight, box.height);
        let width = Math.max(content.scrollWidth, box.width);
        // Include positioned media and controls which may not contribute to
        // their parent's normal-flow height.
        for (const element of content.querySelectorAll('img,video,audio,canvas,iframe,input,textarea,table')) {
            if (!element.getClientRects().length) continue;
            const bounds = element.getBoundingClientRect();
            height = Math.max(height, bounds.bottom - box.top);
            width = Math.max(width, bounds.right - box.left, box.right - bounds.left);
        }
        return { height, width };
    }

    function observeMutations() {
        mutations.observe(content, { childList: true, subtree: true, characterData: true, attributes: true });
    }

    function fit() {
        pending = false;
        if (!content.isConnected || (window.visualViewport?.scale || 1) > 1.05) return;
        mutations.disconnect();
        try {
            const bodyStyle = getComputedStyle(document.body);
            const viewport = window.visualViewport;
            const width = Math.min(root.clientWidth, viewport?.width || innerWidth);
            const height = Math.min(innerHeight, viewport?.height || innerHeight);
            const availableWidth = Math.max(1, width - parseFloat(bodyStyle.marginLeft) - parseFloat(bodyStyle.marginRight));
            const availableHeight = Math.max(1, height - parseFloat(bodyStyle.marginTop) - parseFloat(bodyStyle.marginBottom));
            constrainMedia(availableHeight);
            identifyText();
            const maximumFont = Math.max(minimumFont, Math.min(availableWidth / 12, availableHeight / 6));
            const applyFont = font => content.style.setProperty('--study-font', font + 'px');
            const fits = () => {
                const size = dimensions();
                const currentWidth = Math.min(root.clientWidth, window.visualViewport?.width || innerWidth)
                    - parseFloat(bodyStyle.marginLeft) - parseFloat(bodyStyle.marginRight);
                return size.width <= currentWidth && size.height <= availableHeight - 2;
            };
            let low = minimumFont, high = maximumFont;
            applyFont(low);
            const minimumFits = fits();
            if (minimumFits) {
                // Bounded measured search, including line wrapping, native
                // media controls, fonts and the current document structure.
                for (let step = 0; step < 9; step++) {
                    const candidate = (low + high) / 2;
                    applyFont(candidate);
                    if (fits()) low = candidate;
                    else high = candidate;
                }
            }
            applyFont(low);
            content.dataset.studyLayout = minimumFits ? 'fit' : 'scroll';
            content.dataset.studyFont = low.toFixed(2);
            content.dataset.studyAvailableHeight = availableHeight.toFixed(2);
            const measured = content.getBoundingClientRect();
            measuredWidth = measured.width;
            measuredHeight = measured.height;
            measuredViewport = viewportSignature();
            content.dispatchEvent(new CustomEvent('study-layout', { detail: { font: low, fits: minimumFits } }));
        } finally {
            observeMutations();
        }
    }

    function viewportSignature() {
        const viewport = window.visualViewport;
        return [root.clientWidth, innerHeight, viewport?.width, viewport?.height, viewport?.scale].join('/');
    }

    function viewportChanged() {
        // Candidate font measurements can transiently show a scrollbar and
        // enqueue viewport events even when the final layout is unchanged.
        if (viewportSignature() !== measuredViewport) schedule();
    }

    function schedule() {
        if (!pending) {
            pending = true;
            requestAnimationFrame(fit);
        }
    }
    mutations = new MutationObserver(schedule);
    observeMutations();
    const resize = new ResizeObserver(() => {
        const box = content.getBoundingClientRect();
        if (Math.abs(box.width - measuredWidth) > 0.5 || Math.abs(box.height - measuredHeight) > 0.5) schedule();
    });
    resize.observe(content);
    window.addEventListener('resize', viewportChanged);
    window.visualViewport?.addEventListener('resize', viewportChanged);
    content.addEventListener('load', schedule, true);
    content.addEventListener('error', schedule, true);
    content.addEventListener('loadedmetadata', schedule, true);
    document.fonts?.ready.then(schedule);
    document.fonts?.addEventListener('loadingdone', event => {
        if (event.fontfaces.length > 0) schedule();
    });
    schedule();
})();
"""#
}
