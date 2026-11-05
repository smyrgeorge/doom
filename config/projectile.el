;;; $DOOMDIR/config/projectile.el -*- lexical-binding: t; -*-
;; Project discovery and file listing. Loaded from config.el.

;; PROJECTILE
;; Discover projects using 'projectile-discover-projects-in-search-path'
(setq projectile-project-search-path '("~/dev"))
;; List project files fresh on every SPC SPC (fd / git ls-files are fast) instead
;; of Doom's persistent cache, which misses files created outside Emacs (CLI,
;; Claude Code, git checkout) until `SPC p i'.
(setq projectile-enable-caching nil)
