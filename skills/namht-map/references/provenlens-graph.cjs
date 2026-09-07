/**
 * provenlens-graph.cjs — build the viewer's graph from a RESOLVED call graph.
 *
 * The bundled analyzer (graph-builder.js) reads imports and `extends` with regular
 * expressions across nine languages. That is the only option for most of them, and it is
 * an honest one, but for the four provenlens covers it is strictly weaker: an import is not
 * a call, and a Spring controller reaching a repository through two interfaces produces no
 * import edge at all.
 *
 * So when the repository has a `.provenlens/` index and `provenlens` is on PATH, take the
 * edges from there instead. They are resolved calls, each carrying a confidence and the
 * rule that derived it — including hops through DI, mixins and framework string-bindings
 * (a Java publisher to a Ruby worker joined on a queue name) that no regex can see.
 *
 * Everything else — Python, Go, C#, PHP, Rust, Kotlin, or any repo without an index —
 * stays on the regex analyzer. This module simply reports that it cannot help, and the
 * caller falls back. It never throws for an ordinary "not available".
 *
 * Output shape is identical to buildGraphData(), so viewer-template.html is unchanged.
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const { LAYER_CONFIG } = require('./graph-builder.js');

/**
 * Extensions provenlens can put into a graph: the four it resolves, plus the two the binding
 * plugins read (MyBatis XML, Flyway SQL) which arrive as generated symbols.
 */
const COVERED_EXT = new Set([
  '.java', '.rb', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.xml', '.sql',
]);

/** Extensions worth naming when they are present and absent from the graph. */
const SOURCE_EXT = new Map([
  ['.py', 'Python'], ['.go', 'Go'], ['.cs', 'C#'], ['.php', 'PHP'],
  ['.rs', 'Rust'], ['.kt', 'Kotlin'], ['.kts', 'Kotlin'], ['.scala', 'Scala'],
  ['.swift', 'Swift'], ['.c', 'C'], ['.cpp', 'C++'], ['.h', 'C/C++'],
]);

const SKIP = new Set([
  'node_modules', '.git', '.provenlens', 'dist', 'build', 'out', 'target', 'vendor',
  'coverage', '__pycache__', '.next', '.nuxt', '.gradle', 'tmp', 'namht-sessions',
]);

/**
 * Source languages present on disk that provenlens cannot put in a graph.
 *
 * A map that silently drops a service is worse than one that admits the hole, and the
 * export alone cannot reveal it: a Python service in a mostly-Java monorepo simply has no
 * nodes. Walk shallowly and cheaply -- this only has to notice a language exists.
 */
function uncoveredLanguages(root, { maxDepth = 6, maxFiles = 20000 } = {}) {
  const found = new Set();
  let seen = 0;
  const walk = (dir, depth) => {
    if (depth > maxDepth || seen >= maxFiles) return;
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (seen >= maxFiles) return;
      if (e.isDirectory()) {
        if (!SKIP.has(e.name) && !e.name.startsWith('.')) walk(path.join(dir, e.name), depth + 1);
        continue;
      }
      seen++;
      const ext = path.extname(e.name).toLowerCase();
      if (!COVERED_EXT.has(ext) && SOURCE_EXT.has(ext)) found.add(SOURCE_EXT.get(ext));
    }
  };
  walk(root, 0);
  return [...found].sort();
}

/**
 * Languages the index holds, from `provenlens status`.
 *
 * `export` seeds from the busiest hubs and stops at a node cap, so on a large repository it draws
 * a neighbourhood, not the repository. If every hub is Ruby, an indexed TypeScript half can be
 * absent from the picture entirely -- and a map that omits half a codebase without saying so is
 * the failure this whole module is supposed to prevent. Comparing the two is the only way to
 * notice, because the export cannot report what it never reached.
 */
function indexedLanguages(root) {
  const run = spawnSync('provenlens', ['status'], { cwd: root, encoding: 'utf8' });
  if (run.error || run.status !== 0) return [];
  const out = run.stdout || '';
  const start = out.indexOf('by language:');
  if (start === -1) return [];
  const langs = [];
  for (const line of out.slice(start).split('\n').slice(1)) {
    const m = /^\s+([a-z+#]+)\s+(\d+)\s*$/.exec(line);
    if (!m) break;
    langs.push(m[1]);
  }
  return langs;
}

/**
 * Is the resolved graph available for this repository?
 * @returns {{ok: true} | {ok: false, why: string}}
 */
function probe(root) {
  if (!fs.existsSync(path.join(root, '.provenlens'))) {
    return { ok: false, why: 'no .provenlens/ index (run `provenlens init .` in the repo)' };
  }
  const v = spawnSync('provenlens', ['--version'], { encoding: 'utf8' });
  if (v.error || v.status !== 0) {
    return { ok: false, why: 'the `provenlens` command is not on PATH' };
  }
  return { ok: true };
}

/**
 * A layer for a symbol, from its path and kind.
 *
 * Deliberately the same vocabulary the regex analyzer uses, so the legend, the colours and
 * the layer filter mean the same thing whichever source drew the picture. Tests are checked
 * first: a controller spec is a test, not presentation.
 */
function layerFor(node) {
  const p = (node.file || '').toLowerCase();
  if (node.isTest) return 'test';
  if (/(^|\/)(config|settings)(\/|\.)|\.(yml|yaml|toml|ini)$/.test(p)) return 'config';
  if (/(controller|resolver|route|handler|view|component|page|api)/.test(p)) return 'presentation';
  if (/(repository|repositories|mapper|dao|entity|entities|model|models|migration|schema)/.test(p)) return 'data';
  if (/(service|usecase|use-case|interactor|domain|worker|job|listener|consumer|publisher)/.test(p)) return 'business';
  if (/(util|helper|lib|infra|infrastructure|client|adapter|middleware)/.test(p)) return 'infrastructure';
  return 'business';
}

/** provenlens `kind` → the viewer's node `type`, which drives the shape it is drawn with. */
function typeFor(kind) {
  switch (kind) {
    case 'class': case 'interface': case 'module': case 'enum': case 'record': return 'class';
    case 'method': case 'constructor': case 'class_method': case 'function': return 'function';
    case 'field': return 'field';
    default: return kind || 'symbol';
  }
}

/**
 * Read the graph around the busiest hubs.
 *
 * `provenlens export` with no symbol seeds from the top hubs, which is exactly the "show me
 * this codebase" picture this skill wants. Its own node cap is honoured rather than
 * re-implemented, so the viewer can never be handed more than it draws smoothly.
 */
function buildFromProvenlens(root, { depth = 3, max = 400 } = {}) {
  const ready = probe(root);
  if (!ready.ok) return { ok: false, why: ready.why };

  const run = spawnSync(
    'provenlens',
    ['export', '--format', 'json', '-d', String(depth), '-m', String(max)],
    { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 },
  );
  if (run.error || run.status !== 0) {
    return { ok: false, why: `provenlens export failed: ${(run.stderr || run.error?.message || '').trim().split('\n')[0]}` };
  }

  let graph;
  try {
    graph = JSON.parse(run.stdout);
  } catch (err) {
    return { ok: false, why: `provenlens export returned unparsable JSON (${err.message})` };
  }
  if (!graph || !Array.isArray(graph.nodes) || !graph.nodes.length) {
    return { ok: false, why: 'the index is empty — nothing to draw' };
  }

  const langs = new Set();
  const nodes = graph.nodes.map((n) => {
    if (n.lang) langs.add(n.lang);
    return {
      id: String(n.id),
      label: n.name,
      type: typeFor(n.kind),
      layer: layerFor(n),
      // `derived` marks a symbol a binding plugin produced — a SQL statement, a route, a
      // migration. It is real, but it is not written in that file, and a reader looking for
      // it there must be told so rather than left to wonder.
      description: `${n.fqn || n.name}${n.derived ? '  (derived, not written in this file)' : ''}`,
      file: n.file,
      line: n.line,
      language: n.lang,
      size: n.seed ? 5 : 3,
      details: n.derived ? 'derived by a framework binding' : undefined,
    };
  });

  const known = new Set(nodes.map((n) => n.id));
  const edges = [];
  for (const e of graph.edges || []) {
    const source = String(e.from);
    const target = String(e.to);
    // The node cap can land mid-edge. An edge to a node the viewer never received would
    // render as a dangling arrow, so drop it here rather than draw a lie.
    if (!known.has(source) || !known.has(target)) continue;
    edges.push({
      source,
      target,
      type: e.kind === 'declares' ? 'defines' : 'calls',
      // The confidence is the whole reason to prefer this graph: keep it visible so a
      // 0.4 unique-name guess never looks like a 1.0 direct call.
      label: e.via && e.via !== 'direct' ? `${e.label || e.kind} · ${e.via} ${e.confidence}` : e.label || e.kind,
      weight: typeof e.confidence === 'number' ? Math.max(1, Math.round(e.confidence * 3)) : 1,
    });
  }

  const unsupported = uncoveredLanguages(root);
  // Indexed, therefore drawable -- and still not drawn. Different from `unsupported`,
  // which is about languages provenlens cannot read at all.
  const indexedButAbsent = indexedLanguages(root).filter((l) => !langs.has(l));

  return {
    ok: true,
    data: {
      nodes,
      edges,
      legend: Object.entries(LAYER_CONFIG).map(([id, cfg]) => ({
        id,
        label: cfg.label,
        color: cfg.color,
      })),
      metadata: {
        projectName: path.basename(root),
        generatedAt: new Date().toISOString(),
        nodeCount: nodes.length,
        edgeCount: edges.length,
        languages: [...langs],
        // Read by build-map.cjs to label the picture. A reader must be able to tell a
        // resolved call from an import line, because they are not worth the same.
        source: 'provenlens (resolved call graph)',
        truncated: Boolean(graph.truncated),
        unsupportedLanguages: unsupported,
        indexedButAbsent,
      },
    },
  };
}

module.exports = { buildFromProvenlens, probe, uncoveredLanguages, indexedLanguages };
