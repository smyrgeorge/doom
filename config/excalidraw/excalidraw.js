// $DOOMDIR/config/excalidraw/excalidraw.js
// The page of a drawing in WebKit (config/excalidraw.el): Excalidraw (0.17,
// its plain-script build, on React 18) over the drawing whose file's text
// Emacs gives as base64. Emacs drives it through window.exd and reads what it
// says in its title ("exd {json}"): whether it's ready, the version of the
// drawing (one more at each change), the version its latest export (the
// file's text as it would be saved) is of, the mouse pointer it wants, the
// theme, an error, its library's version (one more at each change of the
// shapes kept to reuse, which Emacs keeps in a file for all drawings), and
// the number of its latest PNG (see png()).
(function () {
  'use strict';

  const L = window.ExcalidrawLib;
  const options = window.EXD_OPTIONS || {};
  // .excalidraw: Excalidraw's JSON; .excalidraw.svg: an SVG image with the
  // drawing in it, editable again.
  const kind = options.kind === 'json' ? 'json' : 'svg';
  const exportDelay = options.exportDelay == null ? 300 : options.exportDelay;

  // Excalidraw has taken its files' folder (fonts, the code it loads later)
  // from this as it loaded. An exported SVG names its fonts from it too: at
  // the CDN, not at this computer's file:// copy (GitHub, a browser, someone
  // else's computer can load those). Not left out: Excalidraw 0.17.6's own
  // default names a version "undefined".
  window.EXCALIDRAW_ASSET_PATH = options.fonts;

  const state = { ready: false, version: 0, exported: 0, cursor: 'arrow', dark: !!options.dark, error: null,
                  library: 0, png: 0 };
  let api = null;
  let content = null;        // the latest export (its version: state.exported)
  let lastSignature = null;  // the drawing's, as last seen
  let settling = true;       // just loaded: changes are Excalidraw's own,
  let acted = false;         // unless there was input since
  let exportTimer = null;
  let exporting = null;      // the export running (a promise)
  let shown = 0;             // one more each time another drawing is shown
  let libraryItems = [];     // the library as it is
  let knownLibrary = null;   // ... as Emacs has it (JSON)

  function publish() {
    document.title = 'exd ' + JSON.stringify(state);
  }

  // What saving the drawing would write differs (elements, background, images).
  // BACKGROUND: the one set, before React has rendered it.
  function signature(background) {
    return [L.getSceneVersion(api.getSceneElements()),
            background || api.getAppState().viewBackgroundColor,
            Object.keys(api.getFiles() || {}).length].join(':');
  }

  function decode(base64) {
    const binary = atob(base64 || '');
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new TextDecoder('utf-8').decode(bytes);
  }

  const blank = (text) => !text || !text.trim();

  // A library from an .excalidrawlib's text (version 1 or 2): its items.
  async function libraryOf(base64) {
    const text = decode(base64);
    if (blank(text)) return [];
    return L.loadLibraryFromBlob(new Blob([text], { type: 'application/json' }), 'published');
  }

  // The library changed here (shapes added to it, removed): one more version,
  // for Emacs to keep. Not when it's the library Emacs gave.
  function onLibraryChange(items) {
    libraryItems = items;
    const json = L.serializeLibraryAsJSON(items);
    if (json === knownLibrary) return;
    knownLibrary = json;
    if (!state.ready || (settling && !acted)) return;
    state.library += 1;
    publish();
  }

  // The library from Emacs (another drawing's change): not a change here.
  async function setLibrary(base64) {
    if (!api) return;
    const items = await libraryOf(base64);
    knownLibrary = L.serializeLibraryAsJSON(items);
    await api.updateLibrary({ libraryItems: items, merge: false });
  }

  // A library to add (from libraries.excalidraw.com, a file): merged into
  // this one, the library panel opened on it; a change, for Emacs to keep.
  async function addLibrary(base64) {
    if (!api) return;
    acted = true;
    try {
      const items = await libraryOf(base64);
      await api.updateLibrary({ libraryItems: items, merge: true, openLibraryMenu: true });
    } catch (e) {
      state.error = 'Library: ' + (e && e.message ? e.message : e);
      publish();
    }
  }
  const empty = () => ({ elements: [], appState: {}, files: {} });

  // A drawing from its file's text: empty if blank (a new file).
  async function sceneOf(text) {
    if (blank(text)) return empty();
    const blob = new Blob([text], { type: kind === 'json' ? 'application/json' : 'image/svg+xml' });
    return L.loadFromBlob(blob, null, null);
  }

  // The file's text: ending with a line break, no spaces at lines' ends (a
  // project's .editorconfig would have Emacs change them as it saves).
  async function serialize() {
    const text = await exported();
    return text.replace(/[ \t]+$/gm, '').replace(/\n*$/, '\n');
  }

  async function exported() {
    const elements = api.getSceneElements();
    const appState = api.getAppState();
    const files = api.getFiles();
    if (kind === 'json') return L.serializeAsJSON(elements, appState, files, 'local');
    const svg = await L.exportToSvg({
      elements,
      // The drawing in the SVG (editable again), on its background, light
      // whatever the theme here.
      appState: Object.assign({}, appState, {
        exportEmbedScene: true, exportBackground: true, exportWithDarkMode: false,
      }),
      files,
    });
    return svg.outerHTML;
  }

  // Export the drawing as it is (the version it's of), one at a time.
  async function exportNow() {
    clearTimeout(exportTimer);
    exportTimer = null;
    while (exporting) await exporting;
    if (!api) return;
    const version = state.version;
    const drawing = shown;
    if (state.exported === version && content !== null) return;
    exporting = (async () => {
      try {
        const text = await serialize();
        // Another drawing shown meanwhile (see replace): this one's gone.
        if (drawing !== shown) return;
        content = text;
        state.exported = version;
        state.error = null;
      } catch (e) {
        state.error = 'Export: ' + e;
      }
    })();
    await exporting;
    exporting = null;
    publish();
    // Changed meanwhile: again.
    if (state.version !== state.exported) scheduleExport();
  }

  function scheduleExport() {
    clearTimeout(exportTimer);
    exportTimer = setTimeout(exportNow, exportDelay);
  }

  // Excalidraw's own changes as it starts (fonts loaded, texts measured anew)
  // aren't yours: counted from a moment after, or from your first input (a
  // click, a key, a paste...).
  ['pointerdown', 'keydown', 'paste', 'drop', 'input'].forEach((type) => {
    document.addEventListener(type, () => { acted = true; }, true);
  });

  function settle(then) {
    settling = true;
    acted = false;
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => setTimeout(() => {
      lastSignature = signature();
      settling = false;
      if (then) then();
    }, 300));
  }

  // A change to the drawing: one more version. Excalidraw says so (onChange)
  // a moment after the drawing has changed (React renders later): a save
  // looks itself first (see flush).
  function noticeChange() {
    if (!api || !state.ready) return;
    const now = signature();
    if (now === lastSignature) return;   // the view moved, a selection...
    lastSignature = now;
    if (settling && !acted) return;
    state.version += 1;
    publish();
    scheduleExport();
  }

  function onChange() {
    noticeChange();
  }

  // The mouse pointer the page wants: Emacs draws its own over the page (see
  // POINTER in config/webkit.el).
  function onPointerMove(event) {
    const target = event.target;
    const css = target instanceof Element ? getComputedStyle(target).cursor : 'default';
    const cursor = /^(pointer|grab|grabbing|move)$/.test(css) ? 'hand' : css === 'text' ? 'text' : 'arrow';
    if (cursor !== state.cursor) {
      state.cursor = cursor;
      publish();
    }
  }

  async function open(base64, libraryBase64) {
    const text = decode(base64);
    try {
      libraryItems = await libraryOf(libraryBase64);
    } catch (e) {
      libraryItems = [];
    }
    knownLibrary = L.serializeLibraryAsJSON(libraryItems);
    let scene;
    try {
      scene = await sceneOf(text);
    } catch (e) {
      state.error = 'Not a drawing Excalidraw opens (' + (e && e.message ? e.message : e) + ')';
      scene = empty();
    }
    // A new file: the empty drawing is a change (to save).
    if (blank(text)) state.version = 1;
    const appState = Object.assign({}, scene.appState || {}, { theme: state.dark ? 'dark' : 'light' });
    ReactDOM.createRoot(document.getElementById('app')).render(React.createElement(L.Excalidraw, {
      excalidrawAPI: (excalidraw) => {
        if (api) return;
        api = excalidraw;
        setTimeout(() => {
          lastSignature = signature();
          state.ready = true;
          publish();
          settle(() => { if (state.version !== state.exported) scheduleExport(); });
        }, 0);
      },
      initialData: { elements: scene.elements, appState, files: scene.files, scrollToContent: true,
                     libraryItems },
      // Browse libraries: libraries.excalidraw.com sends the one chosen to this
      // address (Emacs opens the site and takes it from there, see
      // config/excalidraw.el).
      libraryReturnUrl: options.libraryReturn,
      onLibraryChange,
      langCode: 'en',
      autoFocus: true,
      // Keys come from Emacs (see config/excalidraw.el), sent to the
      // document: listened for there, not only in the drawing's element.
      handleKeyboardGlobally: true,
      UIOptions: {
        // Emacs opens and saves the file.
        canvasActions: { loadScene: false, saveToActiveFile: false, saveAsImage: false, export: false },
      },
      onChange,
    }));
    document.addEventListener('pointermove', onPointerMove, { passive: true });
    publish();
  }

  // Another view's drawing, or the file read again: shown, not a change of
  // this one; its undo history starts there. Changes count from then on (its
  // fonts are loaded: nothing to settle; a drag going on goes on).
  async function replace(base64) {
    if (!api) return;
    let scene;
    try {
      scene = await sceneOf(decode(base64));
    } catch (e) {
      state.error = 'Not a drawing Excalidraw opens (' + (e && e.message ? e.message : e) + ')';
      publish();
      return;
    }
    shown += 1;
    clearTimeout(exportTimer);
    const background = (scene.appState || {}).viewBackgroundColor || '#ffffff';
    if (scene.files && Object.keys(scene.files).length) api.addFiles(Object.values(scene.files));
    api.updateScene({
      elements: scene.elements,
      appState: { viewBackgroundColor: background },
      commitToHistory: false,
    });
    if (api.history && api.history.clear) api.history.clear();
    content = null;
    state.exported = state.version;      // what it shows is what Emacs has
    state.error = null;
    lastSignature = signature(background);
    publish();
  }

  // A key typed in Emacs: to Excalidraw, as the browser would give it.
  function key(init) {
    const event = Object.assign({ bubbles: true, cancelable: true }, init);
    const target = document.activeElement || document.body;
    target.dispatchEvent(new KeyboardEvent('keydown', event));
    target.dispatchEvent(new KeyboardEvent('keyup', event));
  }

  function selectedElements() {
    const ids = api.getAppState().selectedElementIds || {};
    return api.getSceneElements().filter((element) => ids[element.id]);
  }

  // Copy: the selection in Excalidraw's clipboard format (it pastes it back,
  // here or at excalidraw.com).
  function copy() {
    if (!api) return '';
    const elements = selectedElements();
    if (!elements.length) return '';
    const files = {};
    const all = api.getFiles() || {};
    elements.forEach((element) => {
      if (element.fileId && all[element.fileId]) files[element.fileId] = all[element.fileId];
    });
    return JSON.stringify({ type: 'excalidraw/clipboard', elements, files });
  }

  function cut() {
    const text = copy();
    if (text) key({ key: 'Delete', code: 'Delete' });
    return text;
  }

  // Paste: Excalidraw's own paste, of TEXT (shapes copied from a drawing, or
  // plain text: a text element), where the mouse last was.
  function paste(text) {
    const data = new DataTransfer();
    data.setData('text/plain', text);
    document.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
  }

  // A PNG of the drawing (what an agent reads: not SVG), light as the file
  // is, SCALE times its size, made in the background: png() returns its
  // number, state.png says the latest one made, pngData() its number, a
  // line break and its base64 ('' when nothing is drawn) or 'error: ' and
  // why (WebKit doesn't answer with nothing).
  let pngCount = 0;
  let pngBase64 = '';
  async function pngOf(scale) {
    const elements = api.getSceneElements();
    if (!elements.length) return '';
    const blob = await L.exportToBlob({
      elements,
      appState: Object.assign({}, api.getAppState(), { exportBackground: true, exportWithDarkMode: false }),
      files: api.getFiles(),
      mimeType: 'image/png',
      getDimensions: (width, height) => ({ width: width * scale, height: height * scale, scale }),
    });
    const url = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
    return url.slice(url.indexOf(',') + 1);
  }
  function png(scale) {
    if (!api) return '0';
    const n = ++pngCount;
    pngOf(scale > 0 ? scale : 1)
      .catch((error) => 'error: ' + (error && error.message || error))
      .then((data) => {
        if (n !== pngCount) return;
        pngBase64 = data;
        state.png = n;
        publish();
      });
    return String(n);
  }

  function set(settings) {
    if ('dark' in settings && api) {
      state.dark = !!settings.dark;
      api.updateScene({ appState: { theme: state.dark ? 'dark' : 'light' } });
      publish();
    }
  }

  window.exd = {
    open, replace, key, copy, cut, paste, set, setLibrary, addLibrary, png,
    // The latest PNG (see png()).
    pngData: () => state.png + '\n' + pngBase64,
    // Export now: a save waits for the version the drawing is at.
    flush: () => { noticeChange(); exportNow(); return String(state.version); },
    // The latest export, the file's text as it would be saved, after the
    // version it's of and a line break (Emacs asks for it: WebKit doesn't
    // answer with nothing).
    answer: () => state.exported + '\n' + (content || ''),
    // The library, after its version and a line break.
    library: () => state.library + '\n' + L.serializeLibraryAsJSON(libraryItems),
    state: () => JSON.stringify(state),
    // Changes are counted (see settle).
    settled: () => !settling,
    api: () => api,
  };
})();
