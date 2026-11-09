;;; $DOOMDIR/config/projectile.el -*- lexical-binding: t; -*-
;; Projects: their files listed fresh, a project opening on its README, each
;; workspace keeping its project. Loaded from config.el; its code is in
;; config/projectile/. Where projects are found (SPC p D,
;; `projectile-project-search-path') is set in config.el.

;; ====== SETTINGS ======

;; List project files fresh on every SPC SPC (fd / git ls-files are fast) instead
;; of Doom's persistent cache, which misses files created outside Emacs (CLI,
;; Claude Code, git checkout) until `SPC p i'.
(setq projectile-enable-caching nil)

;; Picking a project (SPC p p) opens its README (config/projectile/readme.el):
;; several, Markdown first, then Org, reStructuredText, AsciiDoc, text, none
;; (README); any case (readme.md too).
(defvar +my/project-readme-extensions '("md" "markdown" "org" "rst" "adoc" "txt" "")
  "README file extensions, preferred first (\"\": a README without one).")

;; ====== CODE ======

(load! "projectile/readme")             ; SPC p p: the README
(load! "projectile/workspaces")         ; each workspace its project
