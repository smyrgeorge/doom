// $DOOMDIR/config/pdf/pdf.js
// The page of a PDF in WebKit (config/pdf.el): PDF.js's viewer
// (pdfjs-dist 3.11, its plain-script builds) over the PDF's bytes, which a
// data-N.js written by Emacs holds as base64 (a file:// page can't fetch other
// files), with a toolbar and a sidebar (outline, page thumbnails).
// Keys go to Emacs, not to the page: Emacs drives it through window.pdfx,
// without waiting for answers, except pdfx.selection() (y, Cmd+C, Option+Enter)
// and pdfx.outlineList() (o). The page can't call Emacs: it says its settings,
// page, place, the pointer it wants and the toolbar's requests to Emacs
// (Preview, print) in its title ("pdfx {json}"), which Emacs reads every 0.1 s
// without JavaScript. Emacs's settings and theme colours come in
// window.PDFX_OPTIONS and the --bg, --bar, --fg... CSS variables.
(function () {
  'use strict';

  const lib = window.pdfjsLib;
  const ui = window.pdfjsViewer;
  const options = window.PDFX_OPTIONS || {};
  const zoomStep = options.zoomStep || 1.25;
  // Words that differ between macOS and Linux (config/pdf/page.el).
  const labels = Object.assign({ mod: 'Cmd', viewer: 'Preview' }, options.labels);
  const minScale = 0.25;
  const maxScale = 10;
  const autoScales = ['page-width', 'page-fit', 'page-actual', 'auto'];
  const container = document.getElementById('viewerContainer');
  const findBadge = document.getElementById('find');
  const pageBadge = document.getElementById('page');

  const clamp = (n, lo, hi) => Math.min(Math.max(n, lo), hi);
  // A pane too narrow for the sidebar beside the page (260 px each): it goes
  // over the page instead, and a pick closes it.
  const narrow = '(max-width: 519px)';

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  // LOOK
  // Dark pages: inverted, with hues turned back, so white comes out as a dark
  // grey and black text as a light one, like pdf-tools' midnight mode. The
  // sidebar beside the page, or over it in a narrow pane.
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
      top: 0; left: 0; right: 0; height: var(--tb); padding: 0 6px; overflow: hidden;
      display: flex; align-items: center; gap: 2px;
      border-bottom: 1px solid var(--border);
    }
    body.no-toolbar #toolbar { display: none; }
    #toolbar button {
      flex: none; display: flex; align-items: center; justify-content: center;
      width: 26px; height: 24px; padding: 0; border: 0; border-radius: 5px;
      background: none; color: var(--fg);
    }
    #toolbar button:hover { background: var(--hover); }
    #toolbar button.on { color: var(--accent); background: var(--hover); }
    #toolbar button:disabled { opacity: .35; background: none; }
    #toolbar .info { flex: none; min-width: 56px; text-align: center; font-variant-numeric: tabular-nums; }
    #toolbar .sep { flex: none; width: 1px; height: 16px; margin: 0 6px; background: var(--border); }
    #toolbar .grow { flex: 1; }
    #sidebar {
      top: var(--tb); bottom: 0; left: 0; width: var(--sb);
      overflow: auto; display: none; border-right: 1px solid var(--border);
    }
    body.sidebar #sidebar { display: block; }
    #sidebar [hidden] { display: none !important; }
    #sidebar .tabs {
      position: sticky; top: 0; z-index: 1; display: flex; gap: 4px; padding: 6px 8px;
      background: var(--bar); border-bottom: 1px solid var(--border);
    }
    #sidebar .tabs button {
      flex: 1; padding: 3px 0; border: 0; border-radius: 5px;
      background: none; color: var(--dim); font: inherit;
    }
    #sidebar .tabs button:hover { background: var(--hover); }
    #sidebar .tabs button.on { background: var(--hover); color: var(--fg); }
    #sidebar .tabs button:disabled { opacity: .4; background: none; }
    #sidebar .view { padding: 6px 0; }
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
    #sidebar .thumb { width: 150px; max-width: calc(100% - 24px); margin: 6px auto 12px; text-align: center; }
    #sidebar .thumb .box {
      background: #fff; box-shadow: 0 1px 4px rgba(0, 0, 0, .45); overflow: hidden;
      outline: 2px solid transparent; outline-offset: 2px;
    }
    #sidebar .thumb:hover .box { outline-color: var(--hover); }
    #sidebar .thumb.current .box { outline-color: var(--accent); }
    #sidebar .thumb canvas { display: block; width: 100%; height: 100%; }
    #sidebar .thumb .num { margin-top: 4px; color: var(--dim); font-variant-numeric: tabular-nums; }
    #sidebar .thumb.current .num { color: var(--accent); }
    #toolbar button:not(:disabled), #sidebar .tabs button:not(:disabled),
    #sidebar .item, #sidebar .caret, #sidebar .thumb { cursor: pointer; }
    body.dark .pdfViewer .page, body.dark #sidebar .thumb .box { background-color: #242424; }
    body.dark .pdfViewer .page canvas, body.dark #sidebar .thumb canvas {
      filter: invert(.86) hue-rotate(180deg);
    }
    @media ${narrow} {
      :root { --sb: min(260px, 85vw); }
      body.sidebar #viewerContainer { left: 0; }
      #sidebar { box-shadow: 2px 0 10px rgba(0, 0, 0, .4); }
    }
  `;
  document.head.appendChild(style);

  // 16 px icons in the text's colour.
  const svg = (body) =>
    '<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor"' +
    ' stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>';
  const icons = {
    sidebar: svg('<rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/><path d="M5.5 2.5v11"/>'),
    back: svg('<path d="M13 8H3M7 4L3 8l4 4"/>'),
    forward: svg('<path d="M3 8h10M9 4l4 4-4 4"/>'),
    prev: svg('<path d="M4 10l4-4 4 4"/>'),
    next: svg('<path d="M4 6l4 4 4-4"/>'),
    zoomOut: svg('<path d="M3.5 8h9"/>'),
    zoomIn: svg('<path d="M3.5 8h9M8 3.5v9"/>'),
    fitWidth: svg('<path d="M1.5 8h13M4 5.5L1.5 8 4 10.5M12 5.5l2.5 2.5-2.5 2.5"/>'),
    fitPage: svg('<rect x="3.5" y="1.5" width="9" height="13" rx="1"/><path d="M6 5h4M6 8h4M6 11h2.5"/>'),
    dark: svg('<path d="M13.5 9.5A6 6 0 0 1 6.5 2.5a6 6 0 1 0 7 7z"/>'),
    preview: svg('<path d="M9.5 2.5h4v4M13.5 2.5l-6 6M12 9.5V13a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h3.5"/>'),
    print: svg('<path d="M4.5 6V2.5h7V6M4.5 11.5h-2a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v3.5a1 1 0 0 1-1 1h-2"/>' +
               '<rect x="4.5" y="9" width="7" height="5" rx=".5"/>'),
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
  let place = options.place || null;  // where it was when last closed: { p, t, l, s }
  let query = '';
  let pageTimer = null;
  let publishTimer = null;
  let outline = [];              // headings in order: { titles, dest, url, page, row, pg }
  let thumbs = [];               // pages: { n, item, box, pdf, done, queued }
  let cursor = 'arrow';
  let action = { n: 0, name: '' };
  const state = {
    dark: !!options.dark,
    toolbar: options.toolbar !== false,
    sidebar: !!options.sidebar,
    view: options.view === 'pages' ? 'pages' : 'outline',
  };

  const zoom = (factor) => {
    viewer.currentScale = clamp(viewer.currentScale * factor, minScale, maxScale);
  };
  const fit = (value) => { viewer.currentScaleValue = value; };
  const turnPage = (delta) => {
    if (doc) viewer.currentPageNumber = clamp(viewer.currentPageNumber + delta, 1, doc.numPages);
  };

  // HISTORY: where jumps (links, the outline, thumbnails, gg / G, a new
  // search) left from, for C-o / C-i and the toolbar's ← →.
  const back = [];
  const forward = [];

  // Where the view is: the page at its top, the point of that page at the
  // view's top left (PDF units), the zoom (a percentage or 'page-width'...).
  // Worked out here, as PDF.js does for its location, not read from that:
  // PDF.js updates it in an animation frame, which WebKit holds back while it
  // thinks the page hidden (as in Emacs, at times).
  function here() {
    if (!doc) return null;
    const top = container.scrollTop;
    const left = container.scrollLeft;
    let view = null;
    for (let i = 0; i < doc.numPages; i++) {
      const candidate = viewer.getPageView(i);
      if (!candidate || !candidate.div) continue;
      const div = candidate.div;
      if (div.offsetTop + div.clientTop + div.offsetHeight > top) {
        view = candidate;
        break;
      }
    }
    if (!view) return null;
    const div = view.div;
    const [x, y] = view.getPagePoint(left - div.offsetLeft - div.clientLeft,
                                     top - div.offsetTop - div.clientTop);
    const value = viewer.currentScaleValue;
    return {
      p: view.id,
      t: Math.round(y),
      l: Math.round(x),
      s: autoScales.includes(value) ? value : Math.round(viewer.currentScale * 10000) / 100,
    };
  }

  function goTo(pos) {
    if (!doc || !pos) return;
    viewer.scrollPageIntoView({
      pageNumber: clamp(pos.p, 1, doc.numPages),
      destArray: [null, { name: 'XYZ' }, pos.l, pos.t, null],
      allowNegativeOffset: true,
    });
  }

  function jump(go) {
    const from = here();
    if (from) {
      back.push(from);
      if (back.length > 100) back.shift();
      forward.length = 0;
    }
    go();
    historyButtons();
  }

  function goBack() {
    if (!back.length) return;
    const from = here();
    if (from) forward.push(from);
    goTo(back.pop());
    historyButtons();
  }

  function goForward() {
    if (!forward.length) return;
    const from = here();
    if (from) back.push(from);
    goTo(forward.pop());
    historyButtons();
  }

  // Links in the PDF go through the link service, as the outline does.
  const goToDestination = links.goToDestination.bind(links);
  links.goToDestination = (dest) => jump(() => goToDestination(dest));
  const goToPage = links.goToPage.bind(links);
  links.goToPage = (page) => jump(() => goToPage(page));

  // A request for Emacs (Preview, print): numbered, so Emacs runs each once.
  function request(name) {
    action = { n: action.n + 1, name };
    publish();
  }

  // TOOLBAR
  const toolbar = el('div');
  toolbar.id = 'toolbar';

  function button(name, title, fn) {
    const node = el('button');
    node.innerHTML = icons[name];
    node.title = title;
    node.addEventListener('click', fn);
    toolbar.appendChild(node);
    return node;
  }

  const sep = () => toolbar.appendChild(el('span', 'sep'));

  const sidebarButton = button('sidebar', 'Sidebar: outline, pages (O)', () => set({ sidebar: !state.sidebar }));
  sep();
  const backButton = button('back', 'Back (C-o)', goBack);
  const forwardButton = button('forward', 'Forward (C-i)', goForward);
  sep();
  button('prev', 'Previous page (K)', () => turnPage(-1));
  const pageInfo = toolbar.appendChild(el('span', 'info'));
  button('next', 'Next page (J)', () => turnPage(1));
  sep();
  button('zoomOut', `Zoom out (${labels.mod}+-)`, () => zoom(1 / zoomStep));
  const zoomInfo = toolbar.appendChild(el('span', 'info'));
  button('zoomIn', `Zoom in (${labels.mod}+=)`, () => zoom(zoomStep));
  button('fitWidth', 'Fit width (W)', () => fit('page-width'));
  button('fitPage', 'Fit page (P)', () => fit('page-fit'));
  toolbar.appendChild(el('span', 'grow'));
  const darkButton = button('dark', 'Dark pages (SPC m d)', () => set({ dark: !state.dark }));
  button('preview', `Open in ${labels.viewer} (SPC m p)`, () => request('preview'));
  button('print', `Print (${labels.mod}+P)`, () => request('print'));

  function historyButtons() {
    backButton.disabled = !back.length;
    forwardButton.disabled = !forward.length;
  }

  // SIDEBAR: the outline, the pages.
  const sidebar = el('div');
  sidebar.id = 'sidebar';
  const tabs = sidebar.appendChild(el('div', 'tabs'));
  const outlineTab = tabs.appendChild(el('button', '', 'Outline'));
  const pagesTab = tabs.appendChild(el('button', '', 'Pages'));
  outlineTab.addEventListener('click', () => set({ view: 'outline' }));
  pagesTab.addEventListener('click', () => set({ view: 'pages' }));
  const outlineView = sidebar.appendChild(el('div', 'view'));
  const pagesView = sidebar.appendChild(el('div', 'view'));
  document.body.append(toolbar, sidebar);

  // SETTINGS: the toolbar's buttons, Emacs's SPC m d / t, O.
  function publish() {
    clearTimeout(publishTimer);
    publishTimer = null;
    document.title = 'pdfx ' + JSON.stringify({
      dark: state.dark,
      toolbar: state.toolbar,
      sidebar: state.sidebar,
      view: state.view,
      outline: outline.length,
      page: doc ? viewer.currentPageNumber : 0,
      pages: doc ? doc.numPages : 0,
      place: here(),
      cursor,
      action,
    });
  }

  // While scrolling: once the place settles a little.
  function publishSoon() {
    if (!publishTimer) publishTimer = setTimeout(publish, 150);
  }

  // The outline view, unless the PDF has none.
  const sidebarView = () => (state.view === 'outline' && outline.length ? 'outline' : 'pages');

  function apply() {
    const body = document.body;
    const view = sidebarView();
    body.classList.toggle('dark', state.dark);
    body.classList.toggle('no-toolbar', !state.toolbar);
    body.classList.toggle('sidebar', state.sidebar);
    darkButton.classList.toggle('on', state.dark);
    sidebarButton.classList.toggle('on', state.sidebar);
    outlineTab.disabled = !outline.length;
    outlineTab.classList.toggle('on', view === 'outline');
    pagesTab.classList.toggle('on', view === 'pages');
    outlineView.hidden = view !== 'outline';
    pagesView.hidden = view !== 'pages';
    markCurrent();
    markThumb();
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

  // A heading or a page picked: the sidebar over the page closed (see LOOK).
  const overPage = window.matchMedia(narrow);
  function picked() {
    if (overPage.matches && state.sidebar) set({ sidebar: false });
  }

  function go(heading) {
    if (heading.dest) links.goToDestination(heading.dest);
    else if (heading.url) window.location.href = heading.url;  // Emacs opens it in the browser
    picked();
  }

  const countHeadings = (nodes) =>
    nodes.reduce((n, node) => n + 1 + countHeadings(node.items || []), 0);

  // A long outline (over 100 headings) shows its first level, the others
  // when opened (▸).
  async function loadOutline(pdf) {
    outline = [];
    outlineView.textContent = '';
    let nodes = null;
    try {
      nodes = await pdf.getOutline();
    } catch (e) {
      nodes = null;
    }
    if (pdf !== doc) return;
    if (!nodes || !nodes.length) {
      outlineView.appendChild(el('div', 'empty', 'No outline'));
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
    walk(nodes, [], outlineView, 0);
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
    if (current && state.sidebar && sidebarView() === 'outline') {
      current.row.scrollIntoView({ block: 'nearest' });
    }
  }

  // THUMBNAILS: drawn when they come into view, one at a time.
  const thumbObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) queueThumb(entry.target.thumb);
  }, { root: sidebar, rootMargin: '300px 0px' });
  let thumbQueue = [];
  let thumbBusy = false;

  async function loadThumbs(pdf) {
    thumbObserver.disconnect();
    thumbQueue = [];
    thumbs = [];
    pagesView.textContent = '';
    let first;
    try {
      first = (await pdf.getPage(1)).getViewport({ scale: 1 });
    } catch (e) {
      return;
    }
    if (pdf !== doc) return;
    for (let n = 1; n <= pdf.numPages; n++) {
      const item = pagesView.appendChild(el('div', 'thumb'));
      const box = item.appendChild(el('div', 'box'));
      box.style.aspectRatio = first.width + ' / ' + first.height;
      item.appendChild(el('div', 'num', String(n)));
      const thumb = { n, item, box, pdf, done: false, queued: false };
      item.thumb = thumb;
      item.addEventListener('click', () => {
        jump(() => { viewer.currentPageNumber = n; });
        picked();
      });
      thumbs.push(thumb);
      thumbObserver.observe(item);
    }
    markThumb();
  }

  function queueThumb(thumb) {
    if (!thumb || thumb.done || thumb.queued || thumb.pdf !== doc) return;
    thumb.queued = true;
    thumbQueue.push(thumb);
    drawThumbs();
  }

  async function drawThumbs() {
    if (thumbBusy) return;
    thumbBusy = true;
    while (thumbQueue.length) {
      const thumb = thumbQueue.shift();
      if (thumb.pdf !== doc) continue;
      try {
        const page = await thumb.pdf.getPage(thumb.n);
        const base = page.getViewport({ scale: 1 });
        const width = (thumb.box.clientWidth || 150) * (window.devicePixelRatio || 1);
        const viewport = page.getViewport({ scale: width / base.width });
        const canvas = document.createElement('canvas');
        canvas.width = Math.ceil(viewport.width);
        canvas.height = Math.ceil(viewport.height);
        await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
        if (thumb.pdf !== doc) continue;
        thumb.box.style.aspectRatio = base.width + ' / ' + base.height;
        thumb.box.appendChild(canvas);
        thumb.done = true;
      } catch (e) {
        thumb.queued = false;
      }
    }
    thumbBusy = false;
  }

  function markThumb() {
    if (!doc || !thumbs.length) return;
    const n = viewer.currentPageNumber;
    for (const thumb of thumbs) thumb.item.classList.toggle('current', thumb.n === n);
    if (state.sidebar && sidebarView() === 'pages' && thumbs[n - 1]) {
      thumbs[n - 1].item.scrollIntoView({ block: 'nearest' });
    }
  }

  // BADGES: the search's query and matches while it lasts (Esc in Emacs ends
  // it); without the toolbar, the page number for a moment while it changes.
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
    markThumb();
    publish();
  });

  // The zoom is part of the place (kept on close, a new pane's): said anew,
  // not only once a scroll happens to follow (at a page's top, none did).
  bus.on('scalechanging', (e) => {
    zoomInfo.textContent = Math.round(e.scale * 100) + '%';
    publishSoon();
  });

  // The place, while scrolling (not PDF.js's updateviewarea: see here()).
  container.addEventListener('scroll', publishSoon, { passive: true });

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

  // Opening: where it was before a reload, else where it was when last
  // closed, else at the top, as wide as the window.
  bus.on('pagesinit', () => {
    const reloaded = restore;
    const last = place;
    restore = null;
    place = null;
    if (reloaded) {
      viewer.currentScaleValue = reloaded.scale;
      container.scrollTop = reloaded.top;
      container.scrollLeft = reloaded.left;
    } else if (last) {
      if (typeof last.s === 'number') viewer.currentScale = clamp(last.s / 100, minScale, maxScale);
      else viewer.currentScaleValue = last.s || 'page-width';
      goTo(last);
    } else {
      viewer.currentScaleValue = 'page-width';
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
      back.length = 0;
      forward.length = 0;
      historyButtons();
      viewer.setDocument(doc);
      links.setDocument(doc);
      if (old) old.destroy();
      loadOutline(doc);
      loadThumbs(doc);
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

  // THE MOUSE POINTER: Emacs draws its own over the whole page (CSS cursors
  // never show), so the page says in its title which one it wants under the
  // mouse, for Emacs to show: hand (buttons, headings, thumbnails, links),
  // text (the PDF's text) or arrow.
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

  const scrollBy = (left, top, smooth) =>
    container.scrollBy({ left, top, behavior: smooth ? 'smooth' : 'auto' });

  historyButtons();
  apply();

  window.pdfx = {
    open: (src) => open(src, false),
    reload: (src) => open(src, true),
    scroll: (dx, dy) => scrollBy(dx, dy, false),
    screen: (fraction) => scrollBy(0, fraction * container.clientHeight, true),
    top: () => jump(() => container.scrollTo({ top: 0 })),
    bottom: () => jump(() => container.scrollTo({ top: container.scrollHeight })),
    goto: (n) => jump(() => { if (doc) viewer.currentPageNumber = clamp(n, 1, doc.numPages); }),
    page: turnPage,
    back: goBack,
    forward: goForward,
    zoom,
    fit,
    set,
    find: (q, backward) => {
      if (!q) return endFind();
      jump(() => {
        query = q;
        dispatchFind('', backward);
      });
    },
    again: (backward) => { if (query) dispatchFind('again', backward); },
    endFind,
    selection: () => String(window.getSelection()),
    outlineList: () => JSON.stringify(outline.map((h) => ({ t: h.titles, p: h.page }))),
    outlineGo: (i) => { if (outline[i]) go(outline[i]); },
    viewer,                      // for debugging, e.g. in WebKit's inspector
  };
})();
