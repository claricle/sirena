// Runs a batch of Mermaid sequence-diagram sources through the REAL
// mermaid parser, inside one persistent headless-Chrome page, and prints
// one JSON verdict per input.
//
// Companion to scripts/sequence_fuzz.rb, which generates the inputs and
// runs Sirena's own parser on the Ruby side. This file only knows how to
// ask mermaid a question; it does not generate inputs and does not know
// what Sirena said. That split is deliberate: it lets both sides be
// checked independently against known-good behaviour.
//
// Usage: node scripts/sequence_fuzz_mermaid.js < cases.json > results.json
//   cases.json   [{ "id": 0, "source": "sequenceDiagram\n    A->>B: m\n" }, ...]
//   results.json [{ "id": 0, "accepted": true, "actors": ["A", "B"] }, ...]
//                or { "id": 0, "accepted": false, "error": "Parse error..." }
//
// Requires PUPPETEER_EXECUTABLE_PATH to point at a real Chrome/Chromium
// binary. Without it, every call fails with "Could not find Chrome",
// which looks exactly like mermaid rejecting the input -- this script
// refuses to proceed until a known-valid probe case is confirmed accepted,
// specifically to catch that trap before it produces a false divergence.

'use strict';

const path = require('path');
const { execFileSync } = require('child_process');

function findMermaidCliDir() {
  const npmRoot = execFileSync('npm', ['root', '-g']).toString().trim();
  return path.join(npmRoot, '@mermaid-js', 'mermaid-cli');
}

function loadPuppeteer(cliDir) {
  const resolved = require.resolve('puppeteer-core', {
    paths: [path.join(cliDir, 'node_modules')],
  });
  return require(resolved);
}

function mermaidDistPath(cliDir) {
  return path.join(cliDir, 'node_modules', 'mermaid', 'dist', 'mermaid.min.js');
}

function readStdin() {
  const chunks = [];
  process.stdin.on('data', (c) => chunks.push(c));
  return new Promise((resolve) => {
    process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  });
}

// Evaluated inside the page. Kept as a single function (rather than one
// page.evaluate per case) because the round-trip overhead of Puppeteer's
// CDP protocol, not mermaid's own parse time, is what dominates cost --
// measured at ~1ms/case batched versus ~1.7-2.2s per `mmdc` process spawn.
async function evaluateBatch(cases) {
  const out = [];
  for (const { id, source } of cases) {
    try {
      // eslint-disable-next-line no-undef
      const diagram = await mermaid.mermaidAPI.getDiagramFromText(source);
      let actors = null;
      const db = diagram.db;
      if (db && typeof db.getActors === 'function') {
        const raw = db.getActors();
        actors = raw instanceof Map ? Array.from(raw.keys()) : Object.keys(raw);
      }
      out.push({ id, accepted: true, actors });
    } catch (e) {
      out.push({ id, accepted: false, error: String(e.message || e).split('\n')[0] });
    }
  }
  return out;
}

async function main() {
  if (!process.env.PUPPETEER_EXECUTABLE_PATH) {
    process.stderr.write(
      'PUPPETEER_EXECUTABLE_PATH is not set. Every mermaid call will fail ' +
        'with "Could not find Chrome", which looks exactly like a rejection. ' +
        'Set it to a real Chrome binary, e.g.:\n' +
        '  export PUPPETEER_EXECUTABLE_PATH=' +
        '"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"\n',
    );
    process.exit(2);
  }

  const raw = await readStdin();
  const cases = JSON.parse(raw);

  const cliDir = findMermaidCliDir();
  const puppeteer = loadPuppeteer(cliDir);
  const mermaidJs = mermaidDistPath(cliDir);

  const browser = await puppeteer.launch({
    executablePath: process.env.PUPPETEER_EXECUTABLE_PATH,
    headless: true,
    args: ['--no-sandbox'],
  });

  try {
    const page = await browser.newPage();
    await page.goto('about:blank');
    await page.addScriptTag({ path: mermaidJs });
    await page.evaluate(() => {
      // eslint-disable-next-line no-undef
      mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' });
    });

    // Preflight: a known-valid single-actor case must be accepted before
    // any generated input is trusted. If Chrome cannot launch, or the
    // wrong binary is on PUPPETEER_EXECUTABLE_PATH, this fails loudly
    // instead of silently reporting every case as a mermaid rejection.
    const preflight = await page.evaluate(evaluateBatch, [
      { id: '__preflight__', source: 'sequenceDiagram\n    Alice->>Bob: Hello Bob\n' },
    ]);
    if (!preflight[0].accepted) {
      process.stderr.write(
        'PREFLIGHT FAILED: a known-valid sequence diagram was rejected by ' +
          'mermaid itself: ' + JSON.stringify(preflight[0]) + '\n' +
          'This means the harness cannot tell a real rejection from a ' +
          'broken Chrome/Puppeteer setup. Refusing to run the batch.\n',
      );
      process.exit(3);
    }

    const results = await page.evaluate(evaluateBatch, cases);
    process.stdout.write(JSON.stringify(results));
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  process.stderr.write('FATAL: ' + (e && e.stack ? e.stack : String(e)) + '\n');
  process.exit(1);
});
