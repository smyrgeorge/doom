;;; $DOOMDIR/config/emacs.el -*- lexical-binding: t; -*-
;; Emacs itself: what differs between macOS and Linux, the frame and its
;; windows, child frames, Emacs in a terminal, garbage collection, profiling,
;; Emacs's libraries loaded when first used, and this config's functions
;; compiled. Loaded from config.el, first: the other files use what differs
;; between macOS and Linux, the libraries' autoloads, child frames and the
;; focus of new windows. Its code is in config/emacs/.

;; ====== VARIABLES ======

;; MACOS AND LINUX
;; What differs between them (config/emacs/os.el: `+my/macos-p', the +my/os-
;; functions): the keys, and the other apps and programs files go to (another
;; app, the file manager, the printer, the clipboard's images, image editing),
;; desktop notifications.

;; KEYS
;; On macOS this config's keys use Cmd (Super, `s-'), as macOS's apps do.
;; Linux's desktops keep most Super keys for themselves (and a terminal can't
;; send Super at all), so on Linux each Cmd key also has a Ctrl key, as Linux's
;; apps have them (docs/keybindings.md lists both):
;; - Ctrl where Vim and Emacs leave it free: Ctrl+1..9 (tabs), Ctrl+= / Ctrl+-
;;   / Ctrl+0 (zoom), Ctrl+P (print), Ctrl+S (a drawing, a merge);
;; - Ctrl+Shift where Ctrl is Vim's (Ctrl+B, Ctrl+W, Ctrl+C, Ctrl+V...), as
;;   Linux's terminals copy with Ctrl+Shift+C;
;; - Alt+← / Alt+→ back / forward, as browsers.
;; The Cmd keys stay bound too (Super, where the desktop lets it through).
;; macOS gets none of the Linux keys: its keys are as they were.

;; OTHER APPS (see `+my/os-open', `+my/os-reveal', `+my/os-print')
;; macOS: Preview and Finder (open), Preview's print dialog (osascript).
;; Linux: the file's default app and the file manager (xdg-open, D-Bus), the
;; default printer (lp, after asking).
;; A file on another machine (TRAMP) none of them can open: said. One that
;; fails says why once it ends.

;; THE CLIPBOARD'S IMAGES (`+my/os-copy-image')
;; macOS: osascript. Linux: wl-copy (Wayland) or xclip (X11).

;; IMAGE EDITING (`+my/os-image-transform', `+my/os-image-to-png')
;; macOS: sips. Linux: ImageMagick (magick, or convert: ImageMagick 6).

;; DESKTOP NOTIFICATIONS (`+my/os-notify', config/notify.el's)
;; macOS: Notification Center, posted by Emacs itself (AppleScript's display
;; notification, `do-applescript'; osascript's without it, or without a GUI
;; display: Emacs in a terminal, posted as Script Editor's then); macOS asks
;; once whether Emacs may notify (System Settings > Notifications > Emacs). A
;; click brings Emacs forward.
;; Linux: the desktop's notifications, through D-Bus (`notifications-notify':
;; a click runs the caller's function), else notify-send.

;; FRAMES AND WINDOWS (config/emacs/window.el)
;; The frame is maximized at startup.

;; NEW WINDOWS GET FOCUS
;; Splits (SPC w s / SPC w v): Doom always splits below/right; these only decide
;; which window gets the cursor. SPC w S / SPC w V now split and stay.
(setq evil-split-window-below t
      evil-vsplit-window-right t)

;; Anything else a command shows in a newly created window (diffs, file
;; previews, other-window commands...) is selected too, once the command is
;; done: not while it runs, as a command may go on working in its own window
;; (M-x checkdoc, its status shown, recentred its file in the status's window
;; and failed); another window it selects itself stays so. Not affected: side
;; windows (Doom popups follow their own :select rules; treemacs, which-key and
;; transient menus live there), child frames, windows opened from timers or
;; process output (no command running), windows a command typed in the
;; minibuffer shows (TAB's *Completions*: the focus stays with what you're
;; typing), and code that binds `+my/focus-new-windows' to nil (e.g. the live
;; Markdown preview).
(defvar +my/focus-new-windows t
  "When non-nil, select windows that `display-buffer' creates for a command.")

;; CHILD FRAMES (config/emacs/childframe.el)
;; Frames laid over a window, without borders, never focused: the notices
;; (config/banner.el), the error stripe (config/stripe.el), WebKit's cover while
;; a page loads (config/webkit.el) make theirs with it.

;; EMACS IN A TERMINAL (config/emacs/terminal.el)
;; emacs -nw, emacsclient -t: the terminal's background is the theme's while
;; Emacs runs, its own while Emacs is suspended (C-x C-z) or gone; no menu bar;
;; hover help in the echo area, never in a tooltip.

;; GARBAGE COLLECTION
;; gcmh (Doom) lets garbage pile up to 64 MB while you work, collects once
;; you've been idle a moment, then drops the limit to 800 KB until the next
;; command. But work keeps happening "idle" (a language server's replies,
;; highlighting, redraws after opening a file), and at 800 KB it collected
;; every few redraws, ~70 ms each (the heap is big): opening a file stuttered
;; for a second after it showed. 32 MB while idle: rarely a collection then.
(setq gcmh-low-cons-threshold (* 32 1024 1024))

;; PROFILING (config/emacs/profiling/)
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

;; LIBRARIES (config/emacs/libraries.el)
;; Emacs's own libraries this config uses (svg, url, map, json...) load when
;; first used, not as Emacs starts: each costs ~8 ms to load here, however
;; small (a native-compiled .eln opened), and config.el loaded 33 of them,
;; a quarter of a second. Their functions are autoloaded.

;; COMPILE (config/emacs/compile.el)
;; Doom loads config.el and config/*.el as source, so their functions ran
;; interpreted, several times slower than compiled: e.g. the stripe's redraw on
;; each frame of a scroll took 1.5 ms instead of 0.2. Once Emacs has been idle
;; for a moment they're byte-compiled in place, a few milliseconds each,
;; stopping at the first key press (no files written, so nothing gets stale).
;; Again after anything loads: functions in `after!' blocks are defined when
;; their package loads. The first pass waits for Emacs to be idle, so it sees
;; every file config.el loads, though this one loads first. Compiled before a
;; package loaded, some code would go wrong: config/emacs/compile.el says how
;; it's caught.
(defvar +my/compile-idle-delay 2
  "Seconds of idleness before this config's functions get compiled.")

;; ====== KEY BINDINGS ======

;; SPC h T: Doom's `doom/toggle-profiler' opened the report instead.
(map! [remap doom/toggle-profiler] #'+my/profiling-toggle)

;; ====== CODE ======

;; Emacs's libraries autoloaded, and what differs between macOS and Linux,
;; first: the other files use them.
(load! "emacs/libraries")
(load! "emacs/os")
(load! "emacs/window")
(load! "emacs/childframe")
(load! "emacs/terminal")
(load! "emacs/profiling")
(load! "emacs/compile")
