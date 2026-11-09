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
    const pendingAnswer = document.getElementById('study-pending-answer');
    if (pendingAnswer) {
        document.body.dataset.studyStableReveal = '';
        window.ankiPadRevealAnswer = () => {
            pendingAnswer.removeAttribute('inert');
            pendingAnswer.removeAttribute('aria-hidden');
            pendingAnswer.dataset.revealed = '';
            return true;
        };
    }
    let stableFont = null, stableWidth = null;
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
        body[data-study-stable-reveal] { justify-content:flex-start; }
        #study-pending-answer { display:contents; }
        #study-pending-answer:not([data-revealed]), #study-pending-answer:not([data-revealed]) * { visibility:hidden !important; pointer-events:none !important; }
        #qa { display:flow-root; overflow-wrap:anywhere; }
        :is(#qa,#study-pending-answer) > br.study-section-gap { display:none; }
        :is(#qa,#study-pending-answer) > br.study-section-gap + * {
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

    // Restore only properties still owned by us. Template scripts may change
    // inline styles between layouts, and their new values become the baseline.
    const managedStyles = new Map();
    function setStyle(element, property, value) {
        let properties = managedStyles.get(element);
        if (!properties) { properties = new Map(); managedStyles.set(element, properties); }
        if (!properties.has(property)) properties.set(property, {
            original: element.style.getPropertyValue(property),
            priority: element.style.getPropertyPriority(property)
        });
        const entry = properties.get(property);
        element.style.setProperty(property, value, 'important');
        entry.applied = element.style.getPropertyValue(property);
    }

    function restoreAuthoredStyles() {
        for (const [element, properties] of managedStyles) {
            for (const [property, entry] of properties) {
                if (element.style.getPropertyValue(property) === entry.applied &&
                    element.style.getPropertyPriority(property) === 'important') {
                    if (entry.original) element.style.setProperty(property, entry.original, entry.priority);
                    else element.style.removeProperty(property);
                }
            }
            element.classList.remove('study-reading-text', 'study-supporting-text');
            element.removeAttribute('data-study-layout-label');
            element.removeAttribute('data-study-layout-control');
        }
        managedStyles.clear();
        content.style.removeProperty('--study-font');
    }

    function identifyText(availableWidth) {
        restoreAuthoredStyles();
        const styles = new Map();
        const elements = [content, ...content.querySelectorAll('*')];
        for (const element of elements) {
            const style = getComputedStyle(element);
            styles.set(element, {
                font: parseFloat(style.fontSize), display: style.display,
                background: style.backgroundColor, border: parseFloat(style.borderTopWidth),
                padding: parseFloat(style.paddingLeft) + parseFloat(style.paddingRight),
                radius: parseFloat(style.borderRadius), cursor: style.cursor,
                maxWidth: parseFloat(style.maxWidth), position: style.position
            });
        }
        const controls = new Set();
        const labels = new Set();
        const compact = element => {
            const style = styles.get(element);
            return style && ['inline-block', 'inline-flex'].includes(style.display)
                && style.font <= 20 && element.textContent.trim().length <= 32
                && (style.radius > 0 || style.padding > 0)
                && (style.border > 0 || !['transparent', 'rgba(0, 0, 0, 0)'].includes(style.background));
        };
        for (const element of elements) {
            if (element.closest('svg,math,mjx-container,.MathJax,canvas,[data-study-layout-preserve],[data-study-media-group]')) continue;
            const focusableLabel = element.hasAttribute('tabindex') && element.textContent.trim().length <= 32;
            if (focusableLabel || element.matches('button,select,textarea,input,summary,a[href^="ankiplay:"],[role="button"],[role="tab"],[role="switch"]') || (element.matches('a[href]') && compact(element))) {
                controls.add(element);
            }
            // Repeated compact clickable siblings are a control group. A lone
            // styled category badge remains metadata, including cursor:pointer.
            const siblings = Array.from(element.children).filter(child => compact(child) && styles.get(child).cursor === 'pointer');
            if (siblings.length >= 2) for (const sibling of siblings) controls.add(sibling);
        }
        for (const element of elements) {
            if (compact(element) && !controls.has(element) && !element.closest(preserved)) labels.add(element);
        }
        const excluded = element => element.closest(preserved)
            || Array.from(controls).some(control => control === element || control.contains(element))
            || Array.from(labels).some(label => label === element || label.contains(element));
        const textParents = new Map();
        const references = new Map();
        let section = 0;
        const walker = document.createTreeWalker(content, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
            const node = walker.currentNode;
            if (node.nodeType === Node.ELEMENT_NODE && node.matches('hr#answer')) section++;
            if (node.nodeType !== Node.TEXT_NODE || !node.textContent.trim() || excluded(node.parentElement)) continue;
            const element = node.parentElement;
            const authored = styles.get(element).font;
            if (!(authored > 0)) continue;
            textParents.set(element, { authored, section, supporting: false });
        }
        // Flat templates often give every field the same font. Retain their
        // explicit line-break/parenthetical example grouping as a fallback.
        function markFlatExamples(parent) {
            let hasPrimary = false, afterBreak = false;
            for (const block of parent.childNodes) {
                if (block.nodeType !== Node.ELEMENT_NODE) continue;
                if (block.matches('hr#answer')) { hasPrimary = false; afterBreak = false; continue; }
                if (block.matches('br')) {
                    if (hasPrimary) {
                        afterBreak = true;
                        block.classList.toggle('study-section-gap', !!block.nextElementSibling?.matches('div,p,section,article,blockquote'));
                    }
                    continue;
                }
                if (block === pendingAnswer) { markFlatExamples(block); continue; }
                const entries = Array.from(textParents).filter(([element]) => element === block || block.contains(element));
                if (!entries.length) continue;
                const label = block.textContent.trim();
                const supporting = hasPrimary && (afterBreak || block.matches('small,[data-study-role="example"]') || /^[（(][\s\S]*[）)]$/.test(label));
                if (supporting) for (const [, entry] of entries) entry.supporting = true;
                hasPrimary = true;
            }
        }
        markFlatExamples(content);
        for (const entry of textParents.values()) {
            if (!entry.supporting) references.set(entry.section, Math.max(references.get(entry.section) || 0, entry.authored));
        }
        const ratios = new Map();
        const ownRatios = new Map();
        function includeParents(element, ratio, minimum) {
            for (; element; element = element.parentElement) {
                const previous = ratios.get(element);
                if (styles.get(element)?.font !== 0) ratios.set(element, ownRatios.get(element) || {
                    ratio: Math.max(previous?.ratio || 0, ratio),
                    minimum: Math.max(previous?.minimum || 0, minimum)
                });
                if (element === content) break;
            }
        }
        for (const [element, entry] of textParents) {
            const reference = references.get(entry.section) || entry.authored;
            let ratio = entry.authored / reference;
            if (entry.supporting) ratio = Math.min(ratio, 0.62);
            ratio = Math.max(0.35, Math.min(1, ratio));
            ownRatios.set(element, { ratio, minimum: (entry.supporting || ratio < 0.7 ? 18 : 24) * readingScale });
        }
        for (const [element, value] of ownRatios) includeParents(element, value.ratio, value.minimum);
        for (const [element, value] of ratios) {
            element.classList.add('study-reading-text');
            setStyle(element, 'font-size', 'max(' + value.minimum + 'px,calc(var(--study-font) * ' + value.ratio + '))');
            setStyle(element, 'line-height', '1.3');
            setStyle(element, 'overflow-wrap', 'anywhere');
        }
        const reference = Math.max(24, ...references.values());
        for (const [element, style] of styles) {
            // Enlarge authored reading columns with their text. Keep the
            // viewport bound and leave positioned annotation/media groups alone.
            if (element === content || !ratios.has(element) || !(style.maxWidth >= 240 && style.maxWidth < availableWidth)) continue;
            const positioned = Array.from(element.querySelectorAll('*')).some(child =>
                ['absolute', 'fixed'].includes(styles.get(child)?.position) || child.matches('img,video,canvas,svg,math,mjx-container,iframe,[data-study-layout-preserve]'));
            if (!positioned) setStyle(element, 'max-width', 'min(100%,calc(var(--study-font) * ' + (style.maxWidth / reference) + '))');
        }
        for (const label of labels) {
            label.dataset.studyLayoutLabel = '';
            setStyle(label, 'font-size', Math.max(12, Math.min(20, styles.get(label).font)) * readingScale + 'px');
            setStyle(label, 'line-height', '1.3');
        }
        for (const control of controls) {
            if (control.matches('input:not([type="button"]):not([type="submit"]),textarea,select')) continue;
            control.dataset.studyLayoutControl = '';
            const replay = control.matches('a[href^="ankiplay:"]');
            setStyle(control, 'font-size', styles.get(control).font === 0 ? '0px' : (replay ? 'clamp(28px,4vmin,44px)' : Math.max(18, Math.min(28, styles.get(control).font)) * readingScale + 'px'));
            setStyle(control, 'line-height', '1.2');
            setStyle(control, 'min-width', '44px');
            setStyle(control, 'min-height', '44px');
            setStyle(control, 'box-sizing', 'border-box');
            setStyle(control, 'max-width', '100%');
            if (['inline', 'inline-block', 'inline-flex'].includes(styles.get(control).display)) {
                setStyle(control, 'display', 'inline-flex');
                setStyle(control, 'align-items', 'center');
                setStyle(control, 'justify-content', 'center');
                setStyle(control, 'vertical-align', 'middle');
            }
            if (replay) setStyle(control, 'text-decoration', 'none');
            const parent = control.parentElement;
            if (parent !== content && !ratios.has(parent) && !parent.closest(preserved)) {
                setStyle(parent, 'font-size', 18 * readingScale + 'px');
                setStyle(parent, 'line-height', '1.3');
            }
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
            identifyText(availableWidth);
            constrainMedia(availableHeight);
            const maximumFont = Math.max(minimumFont, Math.min(availableWidth / 12, availableHeight / 6, 72 * readingScale));
            const applyFont = font => content.style.setProperty('--study-font', font + 'px');
            const fits = () => {
                const size = dimensions();
                const currentWidth = Math.min(root.clientWidth, window.visualViewport?.width || innerWidth)
                    - parseFloat(bodyStyle.marginLeft) - parseFloat(bodyStyle.marginRight);
                return size.width <= currentWidth && size.height <= availableHeight - 2;
            };
            let low = pendingAnswer && stableWidth === availableWidth ? stableFont : minimumFont;
            let high = pendingAnswer && stableWidth === availableWidth ? low : maximumFont;
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
            if (pendingAnswer) { stableFont = low; stableWidth = availableWidth; }
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
