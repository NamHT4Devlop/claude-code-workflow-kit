/**
 * provenlens-full.cjs — the WHOLE resolved call graph, packed for a single offline page.
 *
 * `provenlens export` answers "show me the shape of this codebase": it seeds from the busiest
 * hubs and stops near 400 nodes whatever cap it is handed. That is a picture, not a reference.
 * On mall it drew 403 of 18,683 symbols, and 379 of those were entity fields, so the page could
 * not find `paySuccess` at all while `provenlens node paySuccess` in a terminal could.
 *
 * This module reads the index itself, read-only, and ships every in-repo symbol, every edge
 * with its call-site line, every call that did not resolve (and why), and the source of every
 * indexed file. The viewer then draws a neighbourhood on demand, so the page stays light while
 * the search and the detail panel see everything the terminal sees.
 *
 * The index is provenlens's private format. It is guarded by schema version and by the columns
 * this reads; anything unexpected returns {ok:false, why} and the caller falls back to the
 * export, rather than drawing a half-read graph that looks authoritative.
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

/** Schema versions whose tables and columns match the queries below. */
const KNOWN_SCHEMAS = new Set(['9']);

/** Files above this are not embedded as source (generated bundles, minified vendor code). */
const MAX_SOURCE_BYTES = 512 * 1024;

const TEST_PATH = /(^|\/)(test|tests|spec|specs|__tests__|e2e|integration-tests?)(\/|$)|[._-](test|spec)\.[a-z]+$|_(test|spec)\.rb$|Tests?\.java$/i;

function openIndex(root) {
  const file = path.join(root, '.provenlens', 'index.db');
  if (!fs.existsSync(file)) return { why: 'no .provenlens/index.db' };
  let DatabaseSync;
  try {
    // Built into Node 22.5+. Loaded lazily so older Node still gets the export path.
    ({ DatabaseSync } = require('node:sqlite'));
  } catch {
    return { why: `node:sqlite is unavailable in Node ${process.version} (needs 22.5+)` };
  }
  let db;
  try {
    db = new DatabaseSync(file, { readOnly: true });
  } catch (err) {
    return { why: `cannot open the index read-only (${err.message})` };
  }
  const version = (db.prepare("SELECT value FROM meta WHERE key = 'schema_version'").get() || {}).value;
  if (!KNOWN_SCHEMAS.has(String(version))) {
    db.close();
    return { why: `index schema ${version} is not one this reader knows (${[...KNOWN_SCHEMAS].join(', ')})` };
  }
  return { db };
}

/**
 * Everything the explorer page needs, as compact positional arrays.
 * @returns {{ok: true, data: object, stats: object} | {ok: false, why: string}}
 */
function buildFullIndex(root) {
  const opened = openIndex(root);
  if (!opened.db) return { ok: false, why: opened.why };
  const db = opened.db;
  try {
    const files = db.prepare('SELECT id, path, lang FROM files WHERE external = 0 ORDER BY path').all();
    const fileIdx = new Map(files.map((f, i) => [f.id, i]));

    const symRows = db.prepare(
      `SELECT s.id, s.file_id, s.name, s.fqn, s.kind, s.signature, s.start_line, s.end_line
         FROM symbols s JOIN files f ON f.id = s.file_id
        WHERE f.external = 0
        ORDER BY f.path, s.start_line`,
    ).all();
    const symIdx = new Map(symRows.map((s, i) => [s.id, i]));

    const kinds = [];
    const kindCode = new Map();
    const code = (v) => {
      const k = v || '';
      if (!kindCode.has(k)) { kindCode.set(k, kinds.length); kinds.push(k); }
      return kindCode.get(k);
    };

    // [name, fqn, kindCode, fileIdx, startLine, endLine, signature]
    const syms = symRows.map((s) => [
      s.name, s.fqn || s.name, code(s.kind), fileIdx.get(s.file_id), s.start_line || 0, s.end_line || 0,
      s.signature && s.signature !== s.fqn ? s.signature : '',
    ]);

    // [from, to, edgeKindCode, confidence, viaCode, callLine]
    const edges = [];
    let droppedEdges = 0;
    for (const e of db.prepare('SELECT from_symbol_id, to_symbol_id, kind, confidence, via, line FROM edges').iterate()) {
      const a = symIdx.get(e.from_symbol_id);
      const b = symIdx.get(e.to_symbol_id);
      // Both ends are in-repo by construction; a miss means a dependency's declaration file,
      // which is not this project's code. Counted, so the page can say so.
      if (a === undefined || b === undefined) { droppedEdges++; continue; }
      edges.push([a, b, code(e.kind), e.confidence == null ? 1 : Math.round(e.confidence * 100) / 100, code(e.via), e.line || 0]);
    }

    // Calls that did not become edges. `external` ones went into a library, which is expected;
    // the rest are the misses the resolution figure counts, and hiding them would make the
    // callee list look complete when it is not.
    // [fromSym, name, receiver, line, external(0|1), reasonCode, owner]
    const unresolved = [];
    for (const r of db.prepare(
      `SELECT r.from_symbol_id, r.name, r.receiver, r.line, u.external, u.reason, u.owner
         FROM unresolved u JOIN refs r ON r.id = u.ref_id
        WHERE r.from_symbol_id IS NOT NULL`,
    ).iterate()) {
      const a = symIdx.get(r.from_symbol_id);
      if (a === undefined) continue;
      unresolved.push([a, r.name, r.receiver || '', r.line || 0, r.external ? 1 : 0, code(r.reason), r.owner || '']);
    }

    // Source, keyed by file index. Read from disk rather than the index, which does not keep it.
    const source = {};
    let skippedSource = 0;
    for (let i = 0; i < files.length; i++) {
      const abs = path.resolve(root, files[i].path);
      if (!abs.startsWith(path.resolve(root) + path.sep)) { skippedSource++; continue; }
      try {
        const st = fs.statSync(abs);
        if (st.size > MAX_SOURCE_BYTES) { skippedSource++; continue; }
        source[i] = fs.readFileSync(abs, 'utf8');
      } catch {
        skippedSource++;
      }
    }

    const linked = edges.filter((e) => kinds[e[2]] === 'calls' || kinds[e[2]] === 'instantiates').length;
    const missed = unresolved.filter((u) => !u[4]).length;
    const stats = {
      files: files.length,
      symbols: syms.length,
      edges: edges.length,
      linked,
      missed,
      library: unresolved.length - missed,
      // provenlens's own figure, so the page and `provenlens status` never disagree.
      resolution: statusResolution(root),
      droppedEdges,
      skippedSource,
    };

    return {
      ok: true,
      stats,
      data: {
        files: files.map((f) => [f.path, f.lang, TEST_PATH.test(f.path) ? 1 : 0]),
        kinds,
        syms,
        edges,
        unresolved,
        source,
        stats,
        generatedAt: new Date().toISOString(),
      },
    };
  } catch (err) {
    // A column renamed under a known schema number: refuse rather than guess.
    return { ok: false, why: `reading the index failed (${err.message})` };
  } finally {
    db.close();
  }
}

/** The resolution percentage `provenlens status` prints, or null when it cannot be read. */
function statusResolution(root) {
  const { spawnSync } = require('child_process');
  const run = spawnSync('provenlens', ['status'], { cwd: root, encoding: 'utf8' });
  const m = /resolution:\s*([\d.]+)%/.exec(run.stdout || '');
  return m ? Number(m[1]) : null;
}

/** gzip + base64, so a 15 MB graph travels as ~3 MB of inert text inside the page. */
function pack(data) {
  return zlib.gzipSync(Buffer.from(JSON.stringify(data), 'utf8'), { level: 9 }).toString('base64');
}

module.exports = { buildFullIndex, pack, KNOWN_SCHEMAS };
