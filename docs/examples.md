# Examples

`examples/` has an example of each feature that needs something set up to be seen, such as a Git repository in
conflict. `M-x +my/example` picks one in the minibuffer, and `M-x +my/example-NAME` runs one directly. An example
opens the feature as you'd come to it, on files of its own in the temp folder, and leaves nothing behind: its files are
deleted once you're done with it. Doom doesn't load `examples/` at startup: `config/examples.el` makes each
`+my/example-NAME` command, which loads `examples/NAME.el` when first run.

| Example | What it shows |
|---|---|
| `merge` | [Resolving conflicts](git.md#resolving-conflicts) in three panes. A temp repository merges `feature` into `main` and `orders.py` conflicts every way the panes handle: a conflict over one word (the tax rate: keep one, or both), two the ✨ wand merges (`discount()`, `tax()`), a change of each side alone, lines added (`refund()`), lines removed (`legacy_receipt()`), and the same change on both sides (a docstring). Try anything: the repository is deleted once the merge is closed (Done or Abort), along with whatever Done saved. |

To add one: `examples/NAME.el` defines the command `+my/example-NAME` (interactive), sets up what it needs in the temp
folder, opens the feature and deletes its files once it's closed. Add it to this table and to the list in
`config/examples.el`, and test it in `tests/unit/test-examples.el` (and `tests/e2e/test-examples.el` for what needs a
GUI).
