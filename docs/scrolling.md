# Smooth scrolling

## Mouse-wheel glide

Doom's `smooth-scroll` module scrolls by pixels (ultra-scroll), which suits a trackpad's stream of small steps. A
mouse wheel reports a few lines per notch, so it still jumped; `config/smooth.el` spreads bigger steps over a glide
(about 0.15 s, fast at first then slowing down), and notches in quick succession add to what's left without
restarting it. A frame per refresh of the display (60 Hz), each covering a share of what's left that depends on the
time since the last frame, so a late frame catches up instead of slowing the glide down. Scrolling the other way, or in
another window, drops what's left of the glide.

- `+my/smooth-scroll-time-constant` (0.05 s): the glide covers ~63% of what's left in that time and ends after about
  three times it.
- `+my/smooth-scroll-min-step` (20 px): wheel steps bigger than this glide (a mouse notch here is 51 px); smaller ones,
  a trackpad's, scroll at once.
- `+my/smooth-scroll-frame` (1/60 s): the time between frames; 1/120 on a 120 Hz display.

## Keyboard scrolling

good-scroll (the `+interpolate` flag: it animates keyboard scrolling, `C-d`, `C-v`...) runs its 20 ms timer only while
a scroll animates: always on, it made Emacs redraw ~50 times a second, which on macOS took time from everything else
(opening a file too).

## While a scroll runs

Heavy jobs that run when Emacs is idle (gcmh's garbage collection, ~80 ms; treemacs' refresh after a git change,
~130 ms) wait until a glide ends: a glide runs from a timer, so Emacs counted as idle and they froze it for a few
frames. The module also pauses some modes while scrolling; hl-todo is kept on, otherwise TODO/NOTE/FIXME lose their
highlight during a scroll and flicker. Its mode-line freeze during scrolls is off: in popups like `*Messages*` it broke
the mode line, and with it Esc (which then couldn't close the popup).

## The minibuffer

The wheel doesn't scroll the minibuffer / echo area (it always fits what it shows, so it only jumped and came back);
with a completion list open, it moves through the candidates instead.

## Scrolling past the end

Every window (`*Messages*`, help, magit... not just files) stops scrolling with at most a quarter of it empty below the
last line (`+my/stripe-overscroll`: a fraction, a number of rows, `0` for none, `t` for no limit; see
[Error stripe](editor.md#error-stripe)), instead of going on until the last line reaches the top and bouncing back at
each further notch; images, PDFs and terminals are left alone. The limit is measured in pixels, not rows: a row
showing an image (e.g. a screenshot in a Claude reply) is as tall as many lines, and counted as one, scrolling down to
an image near the end went on past it, then snapped back up by screens.

## Very long lines

Files with lines over 5,000 characters (`+my/long-line-threshold`; Doom keeps Emacs's 10,000 in native-comp builds)
open in `so-long-mode`: plain, without highlighting, ligatures or LSP. Otherwise, e.g. an HTML report with
7,000-character SVG lines stayed in `web-mode`, where redisplay walks each such line character by character (~6 ms a
line a pass) and scrolling stalled for seconds. They don't wrap either: wrapped, such a line fills screens of rows and
every scroll step lays it out again (~60 ms, a visible stutter; ~13 ms unwrapped; `M-x toggle-truncate-lines` wraps
them). A notice at the top says so, with **Wrap lines** and **Open normally** (the file's own mode back) actions (see
[Notices](editor.md#notices)).
