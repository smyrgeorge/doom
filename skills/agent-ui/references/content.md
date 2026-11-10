# Content and layout

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first. A type's every property: `agent-ui types TYPE`.

What stays in view as it is (notes, code, a change, a picture), and a `panel` to lay elements out together.

### `text`

Plain text, wrapped to the width, newlines kept. `face`: `plain` (default), `muted`, `success`, `warning`, `error`.

```sh
agent-ui show '{"id":"status","type":"text","text":"All 412 tests pass.","face":"success"}'
```

### `markdown`

Markdown drawn as your replies are: headings, emphasis, lists, task lists, tables, highlighted code, links. For a plan
or notes that should stay in view. Images show as their text.

```sh
agent-ui show '{"id":"notes","type":"markdown","title":"Plan","markdown":"1. **Parse** the config\n2. Check it against `schema.json`\n3. Write the report"}'
```

### `code`

A snippet, highlighted by its `language`'s mode (python, c, rust, emacs-lisp...; else its `file`'s), each line
numbered from `from` and linked to `file` (`RET` opens it there). Give `code`, or a `file` with `from` and `to` (read
as it is now). `marks`: `{"line", "kind", "note"}`, kind error, warning, change or info: a sign in the gutter, the note
after the line. For the line an error is on, the code a change is about.

```sh
agent-ui show '{"id":"where","type":"code","title":"Where it fails","language":"c","from":40,"code":"int parse_expr(Parser *p) {\n  return NULL;\n}","marks":[{"line":41,"kind":"error","note":"never NULL here"}]}'
```

The user can review it: `c` on a line (or a region's lines) writes a comment under it, and Send the review puts
them into your prompt as "Review of ID: file:line: comment; ...". The same on a `diff`.

### `diff`

Changes, from a unified diff (`git diff`'s): by file, its lines added and removed counted, and hunk; added lines
green, removed red, each line's number in the new file. `RET` on a line opens its file there. `dir` is where its files
are (default: your directory). To show what you changed, or follow the work tree as you go:

```sh
agent-ui show '{"id":"fix","type":"diff","title":"The fix","diff":"--- a/src/parser.c\n+++ b/src/parser.c\n@@ -40,2 +40,2 @@\n   int depth = 0;\n-  return NULL;\n+  return parse_term(p);\n"}'
agent-ui show <<'EOF'
{"id": "changes", "type": "diff", "title": "Uncommitted changes",
 "source": {"poll": "git diff", "every": 5, "into": "diff"}}
EOF
```

Changes to propose before making them, for the user to accept hunk by hunk (`accept`): see [asking.md](asking.md).

### `math`

Formulas, when an explanation needs them (an algorithm's cost, a statistic, a physics law): `tex` is LaTeX math
without `$` or `\[`; `display` `block` (the default: on its own) or `inline`. Typeset as an image in the GUI if the
user has MathJax or LaTeX; else drawn in Unicode where simple, or as its source. In JSON, a backslash is written
twice.

```sh
agent-ui show '{"id":"gauss","type":"math","title":"Gauss","tex":"\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}"}'
```

### `image`

An image file (PNG, JPEG, GIF, WebP, SVG; an Excalidraw drawing's `.excalidraw.svg` too) shown in a graphic Emacs, at
most `width` percent of the pane wide and `height` lines high (never above its own size), `alt` under it; in a
terminal, a line naming it. `RET` on it opens it. `file` is relative to your directory. For a screenshot, a plot you
rendered, a drawing. Or give a `url` (http or https) instead: in a graphic Emacs it's downloaded once, in the
background, and kept; its place says so meanwhile, or why it failed (showing it again tries again). As text (a
terminal, `agent-ui render`) its URL is named, nothing downloaded.

```sh
agent-ui show '{"id":"shot","type":"image","title":"The login page","file":"screenshots/login.png","alt":"After the fix","width":60}'
agent-ui show '{"id":"badge","type":"image","url":"https://img.shields.io/badge/build-passing-green.svg"}'
```

### `html`

A web page as a card: its title and the start of its text, from an HTML `file` (or a `url`: its address only).
`RET` on it opens it, in WebKit inside Emacs where it can, else in the browser. For a report or a page you made.

```sh
agent-ui show '{"id":"coverage","type":"html","title":"Coverage","file":"coverage/index.html","lines":3}'
```

### `files`

Files, each with its state: a path, or `{"path", "status", "added", "removed", "errors", "line", "note"}`; status
`changed`, `added`, `deleted`, `renamed`, `failing`, `passing` or `none`. `"tree": true` groups them by folder (the
user folds a folder with `RET`). `RET` on a file opens it, at its `line`. For what you touched, or where the errors are.
To have the user pick files (`select`): see [asking.md](asking.md).

```sh
agent-ui show '{"id":"touched","type":"files","title":"What I changed","tree":true,"files":[{"path":"src/parser.c","status":"changed","added":12,"removed":3},{"path":"src/lexer.h","status":"added","added":40},{"path":"tests/parser_test.c","status":"failing","errors":2,"line":88}]}'
```

### `panel`

Elements laid out together: `children` are ordinary elements (each its `type`, `title`, `id`), as a `"row"` (side by
side, each its share of the width: `weights`, equal by default) or a `"column"` (the default), in a border (`"border":
false` for none). Panels nest: rows of columns make a dashboard. A row too narrow (under `min-width` a child) stacks
its children. In the GUI, a row holding a chart, graph or image is drawn as one image, side by side (its children's
buttons not clickable there: put a `choice` in a row of its own); a `tags` element's chips (a line high) keep the row
text, clickable; in a terminal, as text. Keep a dashboard's related elements in one panel.

**Each child is an element of its own**: give it an `id`, and `update`, `append`, `remove`, `show` (replacing it),
`snapshot` and links work on it as on any element, its panel redrawn in place. Its `source` runs with it: a live
dashboard is a panel whose children follow commands and files ([sources.md](sources.md)). Ids are unique in the
canvas, children's too.

```sh
agent-ui show '{"id":"release","type":"panel","title":"Release","layout":"row","children":[{"id":"release-build","type":"progress","title":"Build","value":8,"max":12},{"id":"release-tests","type":"table","title":"Tests","columns":["Test","Result"],"rows":[["lexer","passed"],["parser","failed"]]}]}'
```
