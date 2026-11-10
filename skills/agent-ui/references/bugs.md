# A bug in Agent UI itself

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first.

When Agent UI misbehaves (an element drawn wrong, an error where there should be a drawing, a property it lacks), don't
only work around it: tell the user, ask whether to file it, then file it and carry on with the workaround. It goes
into Agent UI's own issues (found from its code), never the project you're working in:

```sh
agent-ui bug <<'EOF'
{"title": "a stats tile's text overlaps the next tile",
 "description": "A long label runs past its tile into the next one at narrow widths.",
 "expected": "The label cut, or wrapped, inside its tile",
 "workaround": "Shorter labels",
 "element": "kpis",
 "repro": {"type": "stats", "figures": [{"label": "A long label for a figure", "value": 87}]}}
EOF
```

`title` and `description` are required; `element` is the id of the element on the canvas showing it (its JSON and
its drawing go with the report); `repro` an element showing the bug with neutral data (no secrets: it's drawn into
the report). The environment is added for you. The reply: `{"ok":true,"issue":"doom-abc","new":true}`; a similar
bug already open gets your report as a note (`"new":false`; `"new": true` in the JSON files it anyway). Not filed (no
issues set up there, no `bd`): `{"ok":false,"error":...,"report":...}`: show the user the report, to file by hand.
