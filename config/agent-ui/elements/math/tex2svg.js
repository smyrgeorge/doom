// Agent UI's math element (config/agent-ui/elements/math.el): TeX read from
// stdin, typeset by MathJax (mathjax-full, installed globally: npm install -g
// mathjax-full) as an SVG on stdout, its glyphs as paths (no fonts needed).
// Argument: "block" (display style) or "inline". Exits 1 with the TeX error.
const {mathjax} = require('mathjax-full/js/mathjax.js');
const {TeX} = require('mathjax-full/js/input/tex-full.js');
const {SVG} = require('mathjax-full/js/output/svg.js');
const {liteAdaptor} = require('mathjax-full/js/adaptors/liteAdaptor.js');
const {RegisterHTMLHandler} = require('mathjax-full/js/handlers/html.js');

let tex = '';
process.stdin.on('data', (chunk) => { tex += chunk; });
process.stdin.on('end', () => {
  const adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);
  const html = mathjax.document('', {
    InputJax: new TeX({packages: ['base', 'ams', 'newcommand'],
                       formatError: (jax, err) => { throw err; }}),
    OutputJax: new SVG({fontCache: 'none'}),
  });
  try {
    const node = html.convert(tex, {display: process.argv[2] !== 'inline'});
    process.stdout.write(adaptor.innerHTML(node));
  } catch (err) {
    process.stderr.write(String(err.message || err));
    process.exit(1);
  }
});
