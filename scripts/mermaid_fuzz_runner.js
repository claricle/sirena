// Runs a batch of Mermaid diagram sources -- of ANY registered diagram
// type -- through the REAL mermaid parser, inside one persistent
// headless-Chrome page, and prints one JSON verdict per input.
//
// Generalizes scripts/sequence_fuzz_mermaid.js so every per-type Ruby
// fuzz script (scripts/flowchart_fuzz.rb, scripts/class_diagram_fuzz.rb,
// scripts/state_diagram_fuzz.rb, scripts/er_diagram_fuzz.rb, ...) can
// share one driver instead of one copy each. It only knows how to ask
// mermaid a question; it does not generate inputs and does not know
// what Sirena said.
//
// Usage: node scripts/mermaid_fuzz_runner.js < payload.json > results.json
//   payload.json {
//     "getter": "getVertices",   zero-arg method on the parsed diagram's
//                                mermaid `db` returning an id-keyed Map,
//                                plain Object, or Array -- e.g.
//                                getVertices, getClasses, getStates,
//                                getEntities, getActors. null/"" skips
//                                structural extraction (accept/reject only).
//     "preflight": "flowchart TD\n    A\n",   a KNOWN-VALID source for
//                                this diagram type, asserted accepted
//                                before any case below is trusted -- see
//                                the preflight comment in main().
//     "cases": [{ "id": "x", "source": "flowchart TD\n    A-b\n" }, ...]
//   }
//   results.json [{ "id": "x", "accepted": true, "ids": ["A"] }, ...]
//                or { "id": "x", "accepted": false, "error": "Parse error..." }
//
// Requires PUPPETEER_EXECUTABLE_PATH to point at a real Chrome/Chromium
// binary. Two different failure modes both look exactly like mermaid
// rejecting the input, and are guarded two different ways:
//   - the env var missing entirely is checked explicitly, first, and
//     exits loudly (exit 2) before any Puppeteer call is attempted;
//   - the env var SET but pointing at a wrong/broken binary is caught by
//     the preflight probe below, which refuses to proceed until a
//     known-valid source is confirmed accepted.
// Neither check alone covers both cases.

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

// Evaluated inside the page via page.evaluate, which serializes ONLY the
// function passed to it -- it does not carry along other top-level
// functions or closures from this Node process. So extractIds is
// inlined here rather than called as a sibling function; a version that
// called out to a module-level helper failed with "extractIds is not
// defined" the first time this ran against a real page.
//
// Kept as a single function (rather than one page.evaluate per case)
// because the round-trip overhead of Puppeteer's CDP protocol, not
// mermaid's own parse time, is what dominates cost -- measured at
// ~1ms/case batched versus ~1.7-2.2s per `mmdc` process spawn (see
// scripts/sequence_fuzz_mermaid.js, which this generalizes).
async function evaluateBatch(cases, getter) {
  // Extracts an ordered id list from whatever shape a db getter returns.
  // mermaid's per-diagram db classes are not uniform: getActors/getStates
  // return a Map, getVertices too, some diagrams could plausibly expose
  // a plain object or array. Normalizing here is what lets one generic
  // runner serve every type without a type-specific case in this file.
  function extractIds(db, name) {
    if (!name) return null;
    const fn = db && db[name];
    if (typeof fn !== 'function') return null;
    const raw = fn.call(db);
    if (raw instanceof Map) return Array.from(raw.keys());
    // Not exercised by any getter this PR uses (getVertices/getClasses/
    // getStates/getEntities are all declared Map in mermaid's own .d.ts,
    // confirmed by running each against real Chrome) -- kept for a future
    // getter that returns an array of primitive-like ids. `String()`
    // assumes exactly that: a non-primitive element would silently
    // become "[object Object]" rather than raising, which a future
    // caller adding an Array-returning getter should know before relying
    // on this branch.
    if (Array.isArray(raw)) return raw.map(String);
    if (raw && typeof raw === 'object') return Object.keys(raw);
    return null;
  }

  const out = [];
  for (const { id, source } of cases) {
    try {
      // eslint-disable-next-line no-undef
      const diagram = await mermaid.mermaidAPI.getDiagramFromText(source);
      const ids = extractIds(diagram.db, getter);
      out.push({ id, accepted: true, ids });
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
  const payload = JSON.parse(raw);
  const getter = payload.getter || '';
  const preflightSource = payload.preflight;
  const cases = payload.cases;

  if (!preflightSource) {
    process.stderr.write('payload.preflight is required: a known-valid source for this diagram type.\n');
    process.exit(2);
  }

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

    // Preflight: a source the CALLER asserts is valid for this diagram
    // type must be accepted before any generated input is trusted. This
    // must be a fixed known-good case, never a generated one -- a
    // generated case is allowed to be a legitimate rejection, and using
    // one here would turn an expected "mermaid correctly rejected this"
    // into a false "the harness is broken". If Chrome cannot launch, or
    // the wrong binary is on PUPPETEER_EXECUTABLE_PATH, this fails
    // loudly instead of silently reporting every case as a rejection.
    const preflight = await page.evaluate(evaluateBatch, [{ id: '__preflight__', source: preflightSource }], getter);
    if (!preflight[0].accepted) {
      process.stderr.write(
        'PREFLIGHT FAILED: the caller\'s known-valid source was rejected ' +
          'by mermaid itself: ' + JSON.stringify(preflight[0]) + '\n' +
          'source used: ' + JSON.stringify(preflightSource) + '\n' +
          'This means the harness cannot tell a real rejection from a ' +
          'broken Chrome/Puppeteer setup. Refusing to run the batch.\n',
      );
      process.exit(3);
    }

    if (cases.length === 0) {
      process.stdout.write('[]');
      return;
    }

    const results = await page.evaluate(evaluateBatch, cases, getter);
    process.stdout.write(JSON.stringify(results));
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  process.stderr.write('FATAL: ' + (e && e.stack ? e.stack : String(e)) + '\n');
  process.exit(1);
});
