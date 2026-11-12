;;; $DOOMDIR/config/markdown/mermaid.el -*- lexical-binding: t; -*-
;; ```mermaid blocks drawn as diagrams in the preview (config/mermaid.el).
;; Loaded from config/markdown.el.

;; MERMAID DIAGRAMS (see config/markdown.el)
;; The page's script (`mdMermaid'): each <pre class="mermaid"> pandoc wrote
;; becomes its diagram. Kept by their source: an update (the page's content
;; swapped) draws only a block that changed; one being drawn shows its last
;; drawing meanwhile (no flash of its source). An error: Mermaid's message
;; under the block's last drawing. mermaid.js is loaded only once a page has
;; a block (a page without one doesn't parse it).
(defconst +md-preview--mermaid-js
  "window.mdMermaid = (function () {
  var config = null, url = null, loading = false, drawn = new Map(), last = [];
  function setup(newConfig, newUrl) {
    config = newConfig; url = newUrl || url; drawn.clear();
    if (window.mermaid) mmd.init(config);
  }
  function load() {
    if (loading) return;
    loading = true;
    var script = document.createElement('script');
    script.src = url;
    script.onload = function () { mmd.init(config); draw(); };
    script.onerror = function () { loading = false; };
    document.head.appendChild(script);
  }
  function show(box, svg, error) {
    box.innerHTML = svg || '';
    if (error) {
      var message = document.createElement('pre');
      message.className = 'mermaid-error';
      message.textContent = error;
      box.appendChild(message);
    }
  }
  function draw() {
    var blocks = document.querySelectorAll('pre.mermaid');
    if (!blocks.length) return;
    if (!window.mermaid) return load();
    blocks.forEach(function (pre, index) {
      var source = (pre.querySelector('code') || pre).textContent;
      var box = document.createElement('div');
      box.className = 'mermaid-diagram';
      box.dataset.source = source;
      if (pre.hasAttribute('data-pos')) box.setAttribute('data-pos', pre.getAttribute('data-pos'));
      var known = drawn.get(source);
      if (known) { show(box, known); last[index] = known; pre.replaceWith(box); return; }
      if (last[index]) show(box, last[index]); else box.appendChild(pre.cloneNode(true));
      pre.replaceWith(box);
      var target = document.createElement('div');
      mmd.draw(target, source).then(function (error) {
        if (!box.isConnected) return;
        if (error) { show(box, last[index], error); return; }
        drawn.set(source, target.innerHTML);
        last[index] = target.innerHTML;
        show(box, target.innerHTML);
      });
    });
  }
  // Each diagram drawn anew (the theme changed): back to its block first.
  function redraw() {
    document.querySelectorAll('div.mermaid-diagram').forEach(function (box) {
      var pre = document.createElement('pre'), code = document.createElement('code');
      pre.className = 'mermaid';
      if (box.hasAttribute('data-pos')) pre.setAttribute('data-pos', box.getAttribute('data-pos'));
      code.textContent = box.dataset.source;
      pre.appendChild(code);
      box.replaceWith(pre);
    });
    draw();
  }
  return {setup: setup, draw: draw, redraw: redraw};
})();"
  "JavaScript drawing a Markdown page's mermaid blocks (see above).")

(defun +md-preview--mermaid-p ()
  "Non-nil if diagrams can be drawn: config/mermaid.el loaded."
  (fboundp '+my/mermaid-config-json))

(defun +md-preview--mermaid-config ()
  "Mermaid's config for the page: the theme's, on the page's background."
  (+my/mermaid-page-json (+my/mermaid-config-json (+md-preview--page-color))))

(defun +md-preview--mermaid-head ()
  "The page's head for diagrams: their script, set up (mermaid.js loaded
when a block shows up), their look; empty without config/mermaid.el."
  (if (not (+md-preview--mermaid-p))
      ""
    (concat "<style>.mermaid-diagram{text-align:center;margin:0 0 16px}"
            ".mermaid-diagram svg{max-width:100%;height:auto}"
            (format ".mermaid-error{color:%s;background:none;text-align:left;font-size:12px;white-space:pre-wrap}"
                    (nth 2 (+my/mermaid-page-colours)))
            "</style>"
            "<script>" +my/mermaid-page-js "\n" +md-preview--mermaid-js "\n"
            (format "mdMermaid.setup(%s, %s);" (+md-preview--mermaid-config)
                    (json-encode (+my/mermaid-js-url)))
            "</script>")))

(defun +md-preview--mermaid-draw-script ()
  "JavaScript drawing the page's diagrams (after its content changed). A
Markdown with a block: mermaid.js downloaded first if it isn't there."
  (if (and (+md-preview--mermaid-p)
           (save-excursion
             (goto-char (point-min))
             (re-search-forward "^[ \t]*\\(```\\|~~~\\)[ \t]*mermaid\\b" nil t))
           (+my/mermaid-js-ensure))
      "if (window.mdMermaid) mdMermaid.draw();"
    ""))

(defun +md-preview--mermaid-theme-script ()
  "JavaScript drawing the page's diagrams in the theme's colours."
  (if (+md-preview--mermaid-p)
      (format "if (window.mdMermaid) { mdMermaid.setup(%s); mdMermaid.redraw(); }"
              (+md-preview--mermaid-config))
    ""))
