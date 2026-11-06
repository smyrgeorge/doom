# Claude Code in Emacs

[`agent-shell`](https://github.com/xenodium/agent-shell) runs Claude Code (via the Agent Client Protocol) in a native
Emacs buffer — evil keys, search and copy work as usual. It uses the Claude CLI login. `C-u M-x agent-shell` starts a
second, parallel session.

Claude is told where it runs and what that allows (`+my/agent-shell-claude-context`, appended to Claude Code's own
system prompt in every session it starts or resumes):

- **Formatting:** the Markdown agent-shell renders (tables, code blocks highlighted by their language's mode), and what
  it doesn't (HTML, LaTeX, Mermaid).
- **File references** as `path:line`: agent-shell makes them links that open the file at that line.
- **Images** inline: a Markdown image link to a local file or an image's path alone on a line (PNG, JPEG, WebP, SVG),
  saved under the project's `.agent-shell/images/`, next to agent-shell's transcripts, so they keep showing there.
- **Reports** with diagrams or graphs come as Markdown in the reply, with only the diagrams rendered as images (not the
  whole report as one image or a web page), so they read inside the editor.
- **The editor:** Emacs runs a server, so Claude can ask it (`emacsclient --eval`) what you're looking at (buffers,
  file and line, region, diagnostics) or open a file for you: quickly, never waiting for input, changing nothing unless
  asked, and checking a file's buffer has no unsaved changes before editing it.
- **The theme's colours**, read when the session starts, so the images it draws suit them (dark here).

Images show as wide as the window (agent-shell shrinks them to 40% of it; `agent-shell-markdown-image-max-width` 1.0),
smaller ones at their own size; `{width=100%}` after an image link sizes one image,
`M-x agent-shell-markdown-image-scale-increase` / `-decrease` resize the ones on screen.
