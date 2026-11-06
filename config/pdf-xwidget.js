// $DOOMDIR/config/pdf-xwidget.js
// The page of a PDF in WebKit (config/pdf-xwidget.el): PDF.js's viewer
// (pdfjs-dist 3.11, its plain-script builds) over the PDF's bytes, which a
// data-N.js written by Emacs holds as base64 (a file:// page can't fetch other
// files). Keys go to Emacs, not to the page: Emacs drives it through
// window.pdfx, without waiting for answers, except pdfx.selection() (y, Cmd+C).
(function () {
  'use strict';

  const lib = window.pdfjsLib;
  const ui = window.pdfjsViewer;
  const container = document.getElementById('viewerContainer');
  const findBadge = document.getElementById('find');
  const pageBadge = document.getElementById('page');
  const minScale = 0.25;
  const maxScale = 10;

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

  const clamp = (n, lo, hi) => Math.min(Math.max(n, lo), hi);

  // BADGES: the page number for a moment while it changes; the search's
  // query and matches while it lasts (Esc in Emacs ends it).
  function badge(el, text) {
    el.textContent = text || '';
    el.classList.toggle('on', !!text);
  }

  bus.on('pagechanging', (e) => {
    if (!doc) return;
    badge(pageBadge, e.pageNumber + ' / ' + doc.numPages);
    clearTimeout(pageTimer);
    pageTimer = setTimeout(() => badge(pageBadge, ''), 1200);
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
  const zoom = (factor) => {
    viewer.currentScale = clamp(viewer.currentScale * factor, minScale, maxScale);
  };

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

  window.pdfx = {
    open: (src) => open(src, false),
    reload: (src) => open(src, true),
    scroll: (dx, dy) => scrollBy(dx, dy, false),
    screen: (fraction) => scrollBy(0, fraction * container.clientHeight, true),
    top: () => container.scrollTo({ top: 0 }),
    bottom: () => container.scrollTo({ top: container.scrollHeight }),
    goto: (n) => { if (doc) viewer.currentPageNumber = clamp(n, 1, doc.numPages); },
    page: (delta) => { if (doc) viewer.currentPageNumber = clamp(viewer.currentPageNumber + delta, 1, doc.numPages); },
    zoom,
    fit: (value) => { viewer.currentScaleValue = value; },
    find: (q, backward) => {
      if (!q) return endFind();
      query = q;
      dispatchFind('', backward);
    },
    again: (backward) => { if (query) dispatchFind('again', backward); },
    endFind,
    selection: () => String(window.getSelection()),
    viewer,                      // for debugging, e.g. in WebKit's inspector
  };
})();
