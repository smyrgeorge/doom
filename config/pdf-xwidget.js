// $DOOMDIR/config/pdf-xwidget.js
// The page of a PDF in WebKit (config/pdf-xwidget.el): PDF.js's viewer
// (pdfjs-dist 3.11, its plain-script builds) over the PDF's bytes, which a
// data-N.js written by Emacs holds as base64 (a file:// page can't fetch other
// files), with a toolbar and an outline sidebar. Keys go to Emacs, not to the
// page: Emacs drives it through window.pdfx, without waiting for answers,
// except pdfx.selection() (y, Cmd+C) and pdfx.outlineList() (o). The page
// tells Emacs its settings and page in its title ("pdfx {json}"), which Emacs
// reads without JavaScript. Emacs's settings and theme colours come in
// window.PDFX_OPTIONS and the --bg, --bar, --fg... CSS variables.
(function () {
  'use strict';

  const lib = window.pdfjsLib;
  const ui = window.pdfjsViewer;
  const options = window.PDFX_OPTIONS || {};
  const zoomStep = options.zoomStep || 1.25;
  const minScale = 0.25;
  const maxScale = 10;
  const autoScales = ['page-width', 'page-fit', 'page-actual', 'auto'];
  const container = document.getElementById('viewerContainer');
  const findBadge = document.getElementById('find');
  const pageBadge = document.getElementById('page');

  const clamp = (n, lo, hi) => Math.min(Math.max(n, lo), hi);

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  // LOOK
  // Dark pages: inverted, with hues turned back, so white comes out as a dark
  // grey and black text as a light one, like pdf-tools' midnight mode.
  const style = el('style');
  style.textContent = `
    :root { --tb: 32px; --sb: 260px; }
    body.no-toolbar { --tb: 0px; }
    #viewerContainer { top: var(--tb); }
    body.sidebar #viewerContainer { left: var(--sb); }
    #find { top: calc(var(--tb) + 10px); }
    #toolbar, #sidebar {
      position: fixed; z-index: 20; box-sizing: border-box;
      background: var(--bar); color: var(--fg);
      font: 12px -apple-system, sans-serif;
      user-select: none; -webkit-user-select: none; cursor: default;
    }
    #toolbar {
      top: 0; left: 0; right: 0; height: var(--tb); padding: 0 6px;
      display: flex; align-items: center; gap: 2px;
      border-bottom: 1px solid var(--border);
    }
    body.no-toolbar #toolbar { display: none; }
    #toolbar button {
      display: flex; align-items: center; justify-content: center;
      width: 26px; height: 24px; padding: 0; border: 0; border-radius: 5px;
      background: none; color: var(--fg);
    }
    #toolbar button:hover { background: var(--hover); }
    #toolbar button:not(:disabled), #sidebar .item, #sidebar .caret { cursor: pointer; }
    #toolbar button.on { color: var(--accent); background: var(--hover); }
    #toolbar button:disabled { opacity: .35; background: none; }
    #toolbar .info { min-width: 56px; text-align: center; font-variant-numeric: tabular-nums; }
    #toolbar .sep { width: 1px; height: 16px; margin: 0 6px; background: var(--border); }
    #toolbar .grow { flex: 1; }
    #sidebar {
      top: var(--tb); bottom: 0; left: 0; width: var(--sb); padding: 6px 0;
      overflow: auto; display: none; border-right: 1px solid var(--border);
    }
    body.sidebar #sidebar { display: block; }
    #sidebar .item {
      display: flex; align-items: center; gap: 4px; margin: 0 4px;
      padding: 3px 8px 3px 6px; border-radius: 4px; white-space: nowrap;
    }
    #sidebar .item:hover { background: var(--hover); }
    #sidebar .item.current { color: var(--accent); }
    #sidebar .caret { flex: none; width: 12px; text-align: center; color: var(--dim); }
    #sidebar .title { flex: 1; overflow: hidden; text-overflow: ellipsis; }
    #sidebar .pg { flex: none; color: var(--dim); font-variant-numeric: tabular-nums; }
    #sidebar .children.collapsed { display: none; }
    #sidebar .empty { padding: 8px 12px; color: var(--dim); }
    body.dark .pdfViewer .page { background-color: #242424; }
    body.dark .pdfViewer .page canvas { filter: invert(.86) hue-rotate(180deg); }
  `;
  document.head.appendChild(style);

  // 16 px icons in the text's colour.
  const svg = (body) =>
    '<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor"' +
    ' stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>';
  const icons = {
    sidebar: svg('<rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/><path d="M5.5 2.5v11"/>'),
    prev: svg('<path d="M4 10l4-4 4 4"/>'),
    next: svg('<path d="M4 6l4 4 4-4"/>'),
    zoomOut: svg('<path d="M3.5 8h9"/>'),
    zoomIn: svg('<path d="M3.5 8h9M8 3.5v9"/>'),
    fitWidth: svg('<path d="M1.5 8h13M4 5.5L1.5 8 4 10.5M12 5.5l2.5 2.5-2.5 2.5"/>'),
    fitPage: svg('<rect x="3.5" y="1.5" width="9" height="13" rx="1"/><path d="M6 5h4M6 8h4M6 11h2.5"/>'),
    dark: svg('<path d="M13.5 9.5A6 6 0 0 1 6.5 2.5a6 6 0 1 0 7 7z"/>'),
  };

  // THE VIEWER
  const bus = new ui.EventBus();
  const links = new ui.PDFLinkService({ eventBus: bus });
  const finder = new ui.PDFFindController({ eventBus: bus, linkService: links });
  const viewer = new ui.PDFViewer({
    container,
    eventBus: bus,
    linkService: links,
    findController: finder,
    textLayerMode: 1,            // text over the pages, to select and search
    // No annotation editing: its manager, never set up, broke on the next
    // document (a reload: "this.#st.destroy").
    annotationEditorMode: lib.AnnotationEditorType.DISABLE,
    removePageBorders: true,
  });
  links.setViewer(viewer);

  let doc = null;
  let restore = null;            // where a reloaded PDF was: { scale, top, left }
  let query = '';
  let pageTimer = null;
  let outline = [];              // headings in order: { titles, dest, url, page, row, pg }
  const state = {
    dark: !!options.dark,
    toolbar: options.toolbar !== false,
    sidebar: !!options.sidebar,
  };

  const zoom = (factor) => {
    viewer.currentScale = clamp(viewer.currentScale * factor, minScale, maxScale);
  };
  const fit = (value) => { viewer.currentScaleValue = value; };
  const turnPage = (delta) => {
    if (doc) viewer.currentPageNumber = clamp(viewer.currentPageNumber + delta, 1, doc.numPages);
  };

  // TOOLBAR
  const toolbar = el('div');
  toolbar.id = 'toolbar';

  function button(name, title, action) {
    const node = el('button');
    node.innerHTML = icons[name];
    node.title = title;
    node.addEventListener('click', action);
    toolbar.appendChild(node);
    return node;
  }

  const sidebarButton = button('sidebar', 'Outline (O)', () => set({ sidebar: !state.sidebar }));
  toolbar.appendChild(el('span', 'sep'));
  button('prev', 'Previous page (K)', () => turnPage(-1));
  const pageInfo = toolbar.appendChild(el('span', 'info'));
  button('next', 'Next page (J)', () => turnPage(1));
  toolbar.appendChild(el('span', 'sep'));
  button('zoomOut', 'Zoom out (Cmd+-)', () => zoom(1 / zoomStep));
  const zoomInfo = toolbar.appendChild(el('span', 'info'));
  button('zoomIn', 'Zoom in (Cmd+=)', () => zoom(zoomStep));
  button('fitWidth', 'Fit width (W)', () => fit('page-width'));
  button('fitPage', 'Fit page (P)', () => fit('page-fit'));
  toolbar.appendChild(el('span', 'grow'));
  const darkButton = button('dark', 'Dark pages (SPC m d)', () => set({ dark: !state.dark }));

  // OUTLINE SIDEBAR
  const sidebar = el('div');
  sidebar.id = 'sidebar';
  const list = sidebar.appendChild(el('div'));
  document.body.append(toolbar, sidebar);

  // SETTINGS: the toolbar's buttons, Emacs's SPC m d / t, O.
  function publish() {
    document.title = 'pdfx ' + JSON.stringify({
      dark: state.dark,
      toolbar: state.toolbar,
      sidebar: state.sidebar,
      outline: outline.length,
      page: doc ? viewer.currentPageNumber : 0,
      pages: doc ? doc.numPages : 0,
      cursor,
    });
  }

  // THE MOUSE POINTER: Emacs draws its own over the whole page (CSS cursors
  // never show), so the page says in its title which one it wants under the
  // mouse, for Emacs to show: hand (buttons, headings, links), text (the
  // PDF's text) or arrow.
  let cursor = 'arrow';
  document.addEventListener('mousemove', (e) => {
    const target = e.target instanceof Element ? e.target : null;
    let next = 'arrow';
    if (target) {
      const css = getComputedStyle(target).cursor;
      if (css === 'pointer' || target.closest('a[href]')) next = 'hand';
      else if (css === 'text') next = 'text';
    }
    if (next !== cursor) {
      cursor = next;
      publish();
    }
  }, { passive: true });

  function apply() {
    const body = document.body;
    const showSidebar = state.sidebar && outline.length > 0;
    body.classList.toggle('dark', state.dark);
    body.classList.toggle('no-toolbar', !state.toolbar);
    body.classList.toggle('sidebar', showSidebar);
    darkButton.classList.toggle('on', state.dark);
    sidebarButton.classList.toggle('on', showSidebar);
    sidebarButton.disabled = outline.length === 0;
    if (showSidebar) markCurrent();
    publish();
  }

  function set(changes) {
    Object.assign(state, changes);
    apply();
  }

  // Fitting the width (or page) again when there's more or less room: the
  // window resized, the toolbar or the sidebar shown or hidden.
  new ResizeObserver(() => {
    const value = viewer.currentScaleValue;
    if (doc && autoScales.includes(value)) viewer.currentScaleValue = value;
  }).observe(container);

  // THE OUTLINE
  async function pageOf(pdf, dest) {
    try {
      const explicit = typeof dest === 'string' ? await pdf.getDestination(dest) : dest;
      if (!Array.isArray(explicit)) return null;
      const ref = explicit[0];
      const index = ref && typeof ref === 'object' ? await pdf.getPageIndex(ref) : ref;
      return Number.isInteger(index) ? index + 1 : null;
    } catch (e) {
      return null;
    }
  }

  function go(heading) {
    if (heading.dest) links.goToDestination(heading.dest);
    else if (heading.url) window.location.href = heading.url;  // Emacs opens it in the browser
  }

  const countHeadings = (nodes) =>
    nodes.reduce((n, node) => n + 1 + countHeadings(node.items || []), 0);

  // A long outline (over 100 headings) shows its first level, the others
  // when opened (▸).
  async function loadOutline(pdf) {
    outline = [];
    list.textContent = '';
    let nodes = null;
    try {
      nodes = await pdf.getOutline();
    } catch (e) {
      nodes = null;
    }
    if (pdf !== doc) return;
    if (!nodes || !nodes.length) {
      list.appendChild(el('div', 'empty', 'No outline'));
      apply();
      return;
    }
    const collapse = countHeadings(nodes) > 100;
    const walk = (items, parents, into, depth) => {
      for (const node of items) {
        const titles = parents.concat(node.title || '');
        const heading = { titles, dest: node.dest, url: node.url, page: null };
        const row = into.appendChild(el('div', 'item'));
        row.style.paddingLeft = 6 + depth * 14 + 'px';
        row.title = node.title || '';
        const caret = row.appendChild(el('span', 'caret'));
        row.appendChild(el('span', 'title', node.title || ''));
        heading.pg = row.appendChild(el('span', 'pg'));
        heading.row = row;
        row.addEventListener('click', () => go(heading));
        outline.push(heading);
        if (node.items && node.items.length) {
          const children = into.appendChild(el('div', 'children'));
          children.classList.toggle('collapsed', collapse);
          caret.textContent = collapse ? '▸' : '▾';
          caret.addEventListener('click', (e) => {
            e.stopPropagation();
            caret.textContent = children.classList.toggle('collapsed') ? '▸' : '▾';
          });
          walk(node.items, titles, children, depth + 1);
        }
      }
    };
    walk(nodes, [], list, 0);
    apply();
    for (const heading of outline) {
      heading.page = await pageOf(pdf, heading.dest);
      if (pdf !== doc) return;
      if (heading.page) heading.pg.textContent = heading.page;
    }
    markCurrent();
  }

  // The current heading: the last one at or before the page shown.
  function markCurrent() {
    if (!doc || !outline.length) return;
    const page = viewer.currentPageNumber;
    let current = null;
    for (const heading of outline) if (heading.page && heading.page <= page) current = heading;
    for (const heading of outline) heading.row.classList.toggle('current', heading === current);
    if (current && document.body.classList.contains('sidebar')) {
      current.row.scrollIntoView({ block: 'nearest' });
    }
  }

  // BADGES: the page number for a moment while it changes; the search's
  // query and matches while it lasts (Esc in Emacs ends it).
  function badge(node, text) {
    node.textContent = text || '';
    node.classList.toggle('on', !!text);
  }

  bus.on('pagechanging', (e) => {
    if (!doc) return;
    pageInfo.textContent = e.pageNumber + ' / ' + doc.numPages;
    if (!state.toolbar) {
      badge(pageBadge, e.pageNumber + ' / ' + doc.numPages);
      clearTimeout(pageTimer);
      pageTimer = setTimeout(() => badge(pageBadge, ''), 1200);
    }
    markCurrent();
    publish();
  });

  bus.on('scalechanging', (e) => {
    zoomInfo.textContent = Math.round(e.scale * 100) + '%';
  });

  const matches = (m) => (m && m.total ? query + '   ' + m.current + ' / ' + m.total : query);

  bus.on('updatefindmatchescount', (e) => {
    if (query) badge(findBadge, matches(e.matchesCount));
  });

  bus.on('updatefindcontrolstate', (e) => {
    if (!query) return;
    // FindState: 0 found, 1 not found, 2 wrapped, 3 pending.
    if (e.state === 1) badge(findBadge, query + '   not found');
    else badge(findBadge, matches(e.matchesCount) + (e.state === 2 ? '   (wrapped)' : ''));
  });

  bus.on('pagesinit', () => {
    const at = restore;
    restore = null;
    viewer.currentScaleValue = at ? at.scale : 'page-width';
    if (at) {
      container.scrollTop = at.top;
      container.scrollLeft = at.left;
    }
    pageInfo.textContent = viewer.currentPageNumber + ' / ' + doc.numPages;
    publish();
  });

  // OPENING: data-N.js sets window.PDFX_DATA.
  function load(src) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.onload = () => {
        const data = window.PDFX_DATA;
        window.PDFX_DATA = null;
        script.remove();
        resolve(data);
      };
      script.onerror = () => reject(new Error('could not read ' + src));
      document.head.appendChild(script);
    });
  }

  function bytes(base64) {
    const raw = atob(base64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  async function open(src, keepPlace) {
    try {
      const next = await lib.getDocument({ data: bytes(await load(src)) }).promise;
      if (keepPlace && doc) {
        restore = { scale: viewer.currentScaleValue, top: container.scrollTop, left: container.scrollLeft };
      }
      const old = doc;
      doc = next;
      endFind();
      viewer.setDocument(doc);
      links.setDocument(doc);
      if (old) old.destroy();
      loadOutline(doc);
    } catch (e) {
      badge(findBadge, 'PDF.js: ' + (e && e.message ? e.message : e));
    }
  }

  // SEARCH: smart case, like Doom's Evil search (a capital: case-sensitive).
  function dispatchFind(type, backward) {
    bus.dispatch('find', {
      source: window,
      type,
      query,
      caseSensitive: /[A-Z]/.test(query),
      entireWord: false,
      highlightAll: true,
      findPrevious: !!backward,
      matchDiacritics: false,
    });
  }

  function endFind() {
    const was = !!query;
    query = '';
    bus.dispatch('findbarclose', { source: window });
    badge(findBadge, '');
    return was;
  }

  // ZOOM: also Cmd+scroll (a step per 40 px of scrolling) and pinching.
  let wheel = 0;
  container.addEventListener('wheel', (e) => {
    if (!e.metaKey && !e.ctrlKey) return;
    e.preventDefault();
    wheel += e.deltaY;
    while (Math.abs(wheel) >= 40) {
      zoom(wheel < 0 ? 1.1 : 1 / 1.1);
      wheel -= Math.sign(wheel) * 40;
    }
  }, { passive: false });

  let pinchFrom = 1;
  window.addEventListener('gesturestart', (e) => {
    e.preventDefault();
    pinchFrom = viewer.currentScale;
  });
  window.addEventListener('gesturechange', (e) => {
    e.preventDefault();
    viewer.currentScale = clamp(pinchFrom * e.scale, minScale, maxScale);
  });

  const scrollBy = (left, top, smooth) =>
    container.scrollBy({ left, top, behavior: smooth ? 'smooth' : 'auto' });

  apply();

  window.pdfx = {
    open: (src) => open(src, false),
    reload: (src) => open(src, true),
    scroll: (dx, dy) => scrollBy(dx, dy, false),
    screen: (fraction) => scrollBy(0, fraction * container.clientHeight, true),
    top: () => container.scrollTo({ top: 0 }),
    bottom: () => container.scrollTo({ top: container.scrollHeight }),
    goto: (n) => { if (doc) viewer.currentPageNumber = clamp(n, 1, doc.numPages); },
    page: turnPage,
    zoom,
    fit,
    set,
    find: (q, backward) => {
      if (!q) return endFind();
      query = q;
      dispatchFind('', backward);
    },
    again: (backward) => { if (query) dispatchFind('again', backward); },
    endFind,
    selection: () => String(window.getSelection()),
    outlineList: () => JSON.stringify(outline.map((h) => ({ t: h.titles, p: h.page }))),
    outlineGo: (i) => { if (outline[i]) go(outline[i]); },
    viewer,                      // for debugging, e.g. in WebKit's inspector
  };
})();
