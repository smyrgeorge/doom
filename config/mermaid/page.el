;;; $DOOMDIR/config/mermaid/page.el -*- lexical-binding: t; -*-
;; mermaid.js, and a page drawing a diagram with it. Loaded from
;; config/mermaid.el.

;; MERMAID.JS (see THE PREVIEW in config/mermaid.el)
(defun +my/mermaid--js-files ()
  "mermaid.js's files, as `+my/webkit-install' takes them."
  (list (list "mermaid.min.js"
              (format "https://cdn.jsdelivr.net/npm/mermaid@%s/dist/mermaid.min.js" +my/mermaid-js-version)
              +my/mermaid-js-sha256)))

(defun +my/mermaid-js-installed-p ()
  "Non-nil if mermaid.js is in `+my/mermaid-js-dir'."
  (+my/webkit-installed-p (+my/mermaid--js-files) +my/mermaid-js-dir))

(defun +my/mermaid-js-install ()
  "Download mermaid.js into `+my/mermaid-js-dir', checking its SHA-256."
  (interactive)
  (+my/webkit-install "mermaid.js" +my/mermaid-js-version (+my/mermaid--js-files) +my/mermaid-js-dir))

(defun +my/mermaid-js-ensure ()
  "Non-nil if mermaid.js is there, downloaded now if need be."
  (or (+my/mermaid-js-installed-p)
      (condition-case err
          (progn (+my/mermaid-js-install) t)
        (error (message "No mermaid.js: %s" (error-message-string err))
               nil))))

(defun +my/mermaid-js-url ()
  "mermaid.js's file:// URL."
  (+my/webkit-file-url (expand-file-name "mermaid.min.js" +my/mermaid-js-dir)))

;; DRAWING IN A PAGE
;; A page's script (`mmd'): mermaid.js set up with the theme's config, a
;; diagram drawn into an element. A drawing asked while another is under way:
;; the last asked wins (one finishing late doesn't replace it). Mermaid's
;; message for an error: the element keeps what it showed. Mermaid writes each
;; word of a label in a <tspan>, the space before it at its start, which
;; WebKitGTK dropped ("Write thecode"; its xml:space too, unlike librsvg,
;; mermaid/render.el): a no-break space there, which nothing collapses.
(defconst +my/mermaid-page-js
  "window.mmd = (function () {
  var count = 0, latest = new WeakMap();
  function init(config) {
    mermaid.initialize(Object.assign({startOnLoad: false, securityLevel: 'strict',
                                      suppressErrorRendering: true}, config));
  }
  function keepSpaces(element) {
    element.querySelectorAll('svg text tspan').forEach(function (tspan) {
      var text = tspan.firstChild;
      if (text && text.nodeType === 3 && text.data.charAt(0) === ' ')
        text.data = '\\u00a0' + text.data.slice(1);
    });
  }
  async function draw(element, source) {
    var id = 'mmd-' + (++count);
    latest.set(element, id);
    try {
      var result = await mermaid.render(id, source);
      if (latest.get(element) === id) {
        element.innerHTML = result.svg;
        keepSpaces(element);
      }
      return null;
    } catch (e) {
      return String((e && e.message) || e);
    } finally {
      ['d' + id, id].forEach(function (left) {
        var node = document.getElementById(left);
        if (node && !element.contains(node)) node.remove();
      });
    }
  }
  return {init: init, draw: draw};
})();"
  "JavaScript drawing Mermaid in a page (see above).")

(defun +my/mermaid-page-colours ()
  "The page's colours, from the theme's faces: (BACKGROUND FOREGROUND ERROR)."
  (let ((frame (+my/mermaid--frame)))
    (list (or (+my/mermaid--face-colour 'default :background frame) "")
          (or (+my/mermaid--face-colour 'default :foreground frame) "")
          (or (+my/mermaid--face-colour 'error :foreground frame) ""))))

;; THE PREVIEW'S PAGE
;; The diagram as wide as its natural size, at most the pane's; zoomed (+, -,
;; 0) its natural size times the zoom, scrolled. An error under it, the last
;; drawing kept. The page's colours the theme's: re-themed in place.
(defconst +my/mermaid--preview-js
  "var shown = null, zoom = 1;
function fit() {
  var svg = document.querySelector('#diagram svg');
  if (!svg) return;
  if (zoom === 1) { svg.style.width = ''; svg.style.maxWidth = svg.dataset.maxWidth || svg.style.maxWidth; }
  else {
    if (!svg.dataset.maxWidth) svg.dataset.maxWidth = svg.style.maxWidth;
    svg.style.maxWidth = 'none';
    svg.style.width = (svg.viewBox.baseVal.width * zoom) + 'px';
  }
}
async function show(source) {
  shown = source;
  var error = await mmd.draw(document.getElementById('diagram'), source);
  if (shown !== source) return;
  var box = document.getElementById('error');
  box.textContent = error || '';
  box.hidden = !error;
  document.title = error ? 'mmd error' : 'mmd drawn';
  fit();
}
function zoomBy(factor) { zoom = factor ? Math.max(0.1, Math.min(10, zoom * factor)) : 1; fit(); }
function theme(config, background, foreground, error) {
  mmd.init(config);
  document.documentElement.style.background = background;
  document.documentElement.style.color = foreground;
  document.getElementById('error').style.color = error;
  if (shown !== null) show(shown);
}"
  "The preview page's own script (see above).")

(defconst +my/mermaid--preview-template
  "<!doctype html>
<html><head><meta charset=\"utf-8\">
<title>mmd</title>
<style>
html{background:%b;color:%f}
body{margin:0;padding:24px;font-family:%F}
#diagram{display:flex;justify-content:center}
#diagram svg{max-width:100%%;height:auto}
#error{color:%e;font:12px monospace;white-space:pre-wrap;margin:16px 0 0}
</style>
<script src=\"%m\"></script>
<script>%j
%p</script>
</head><body><div id=\"diagram\"></div><pre id=\"error\" hidden></pre>
<script>mmd.init(%c); show(%s);</script>
</body></html>
"
  "The preview's page, for `format-spec': %b %f %e the background, text and
error colours, %F the font, %m mermaid.js's URL, %j its drawing script, %p
the preview's, %c the theme's config (JSON), %s the diagram (JSON).")

(defun +my/mermaid-page-json (json)
  "JSON (a string of it) to put in a page's script: a </script> in it doesn't
end the script."
  (replace-regexp-in-string "</" "<\\/" json t t))

(defun +my/mermaid-preview-page (source)
  "The preview's page drawing SOURCE (see above)."
  (pcase-let ((`(,background ,foreground ,error) (+my/mermaid-page-colours)))
    (format-spec +my/mermaid--preview-template
                 `((?b . ,background) (?f . ,foreground) (?e . ,error)
                   (?F . ,(or (alist-get 'fontFamily (alist-get 'themeVariables (+my/mermaid-config)))
                              "monospace"))
                   (?m . ,(+my/mermaid-js-url))
                   (?j . ,+my/mermaid-page-js)
                   (?p . ,+my/mermaid--preview-js)
                   (?c . ,(+my/mermaid-page-json (+my/mermaid-theme-json)))
                   (?s . ,(+my/mermaid-page-json (json-encode source)))))))

(defun +my/mermaid-preview-show-script (source)
  "JavaScript drawing SOURCE in a preview's page."
  (format "show(%s);" (+my/mermaid-page-json (json-encode source))))

(defun +my/mermaid-preview-theme-script ()
  "JavaScript giving a preview's page the theme's colours."
  (pcase-let ((`(,background ,foreground ,error) (+my/mermaid-page-colours)))
    (format "theme(%s, %s, %s, %s);" (+my/mermaid-page-json (+my/mermaid-theme-json))
            (json-encode background) (json-encode foreground) (json-encode error))))
