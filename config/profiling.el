;;; $DOOMDIR/config/profiling.el -*- lexical-binding: t; -*-
;; Profiling Emacs, for an agent to read. Loaded from config.el; its code is in
;; config/profiling/.

;; ====== VARIABLES ======

;; PROFILING
;; SPC h T (Doom's profiler toggle, taken over) starts Emacs's CPU and memory
;; profilers; do what's slow, then SPC h T again stops them and writes what
;; they recorded, as text, into a new folder under `+my/profiling-directory':
;; a summary (the functions that took the most time and memory), the call
;; trees, and the raw profiles (M-x profiler-find-profile). The message says
;; where, and that an agent should read the skill first
;; (skills/emacs-profiling/SKILL.md, which explains the files); the
;; same text is copied, to paste to one.
(defvar +my/profiling-directory (expand-file-name "profiles/" doom-cache-dir)
  "Where profiles are written, a folder each.")

(defvar +my/profiling-mode 'cpu+mem
  "What `+my/profiling-start' profiles: `cpu', `mem' or `cpu+mem'.")

;; Calls kept per sample (Emacs keeps 16): deeper stacks reach the command or
;; timer the work started from. Set here, before the profiler first runs: its
;; next log is made, at the depth of the moment, as it hands over the last one.
(setq profiler-max-stack-depth 32)

(defvar +my/profiling-min-percent 0.5
  "The call trees leave out branches under this share of the total.")

(defvar +my/profiling-top 30
  "Functions the summary lists, by time and by memory.")

;; ====== KEY BINDINGS ======

;; SPC h T: Doom's `doom/toggle-profiler' opened the report instead.
(map! [remap doom/toggle-profiler] #'+my/profiling-toggle)

;; ====== CODE ======

(load! "profiling/report")
(load! "profiling/session")
