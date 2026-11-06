# Smooth scrolling

Doom's `smooth-scroll` module scrolls by pixels (ultra-scroll), which suits a trackpad's stream of small steps. A
mouse wheel reports a few lines per notch, so it still jumped; `config/smooth.el` spreads bigger steps over a glide
(about 0.15 s, fast at first then slowing down), and notches in quick succession add to what's left without
restarting it. A frame per refresh of the display (60 Hz), each covering a share of what's left that depends on the
time since the last frame, so a late frame catches up instead of slowing the glide down
(`+my/smooth-scroll-min-step`, `-frame`, `-time-constant`). good-scroll (the `+interpolate` flag: it animates keyboard
scrolling, `C-d`, `C-v`...) runs its 20 ms timer only while a scroll animates: always on, it made Emacs redraw ~50 times
a second, which on macOS took time from everything else. Heavy jobs that run when Emacs is idle (gcmh's garbage
collection, ~80 ms; treemacs' refresh after a git change, ~130 ms) wait until a glide ends: a glide runs from a timer,
so Emacs counted as idle and they froze it for a few frames. The module also pauses some modes while scrolling; hl-todo is
kept on, otherwise TODO/NOTE/FIXME lose their highlight during a scroll and flicker. Its mode-line freeze during scrolls
is off: in popups like `*Messages*` it broke the mode line, and with it Esc (which then couldn't close the popup). The wheel doesn't scroll the
minibuffer / echo area (it always fits what it shows, so it only jumped and came back); with a completion list open,
it moves through the candidates instead. Every window (`*Messages*`, help, magit... not just files) stops scrolling
with at most a quarter of it empty below the last line (`+my/stripe-overscroll`), instead of going on until the last
line reaches the top and bouncing back at each further notch; images, PDFs and terminals are left alone. The limit is
measured in pixels, not rows: a row showing an image (e.g. a screenshot in a Claude reply) is as tall as many lines,
and counted as one, scrolling down to an image near the end went on past it, then snapped back up by screens.
Files with lines over 5,000 characters (`+my/long-line-threshold`; Doom keeps Emacs's 10,000 in native-comp builds)
open in `so-long-mode`: plain, without highlighting, ligatures or LSP. Otherwise, e.g. an HTML report with
7,000-character SVG lines stayed in `web-mode`, where redisplay walks each such line character by character (~6 ms a
line a pass) and scrolling stalled for seconds. They don't wrap either: wrapped, such a line fills screens of rows and
every scroll step lays it out again (~60 ms, a visible stutter; ~15-20 ms unwrapped). A notice at the top says so, with
**Wrap lines** and **Open normally** (the file's own mode back) actions (see [Notices](editor.md#notices)).
