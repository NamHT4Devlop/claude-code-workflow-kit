"use strict";
/**
 * html-builder.ts
 * Renders a structured EpicOutput object into a self-contained, professional HTML file.
 * No external CDN required — all CSS/JS is inlined.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildUserStoriesHtml = buildUserStoriesHtml;
exports.markdownToHtml = markdownToHtml;
exports.buildDocumentHtml = buildDocumentHtml;
// Exposed for scripts/kb-site.cjs, which renders many documents into one page and therefore
// needs the body renderer without the surrounding document shell.
exports.markdownToHtml = (md) => markdownToHtml(md);
exports.buildKnowledgeGraphHtml = buildKnowledgeGraphHtml;
// ─── Helpers ─────────────────────────────────────────────────────────────────
function esc(s) {
    return (s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function priorityClass(p) {
    return p === 'P1' ? 'p1' : p === 'P2' ? 'p2' : 'p3';
}
function priorityLabel(p) {
    return p === 'P1' ? '🔴 P1 Critical' : p === 'P2' ? '🟡 P2 High' : '🔵 P3 Normal';
}
function sprintColor(n) {
    const colors = ['#6366f1', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#3b82f6'];
    return colors[(n - 1) % colors.length];
}
// ─── Sub-renderers ────────────────────────────────────────────────────────────
function renderStoryCard(s) {
    const acList = s.acceptanceCriteria.map((ac, i) => `
    <div class="ac-item" id="ac-${esc(s.id)}-${i}">
      <div class="ac-badge">AC${i + 1}</div>
      <div class="ac-body">
        <span class="ac-label given">Given</span> ${esc(ac.given)}<br>
        <span class="ac-label when">When</span> ${esc(ac.when)}<br>
        <span class="ac-label then">Then</span> ${esc(ac.then)}
      </div>
    </div>`).join('');
    const dodList = s.definitionOfDone.map(d => `<li><label><input type="checkbox"> ${esc(d)}</label></li>`).join('');
    const depBadges = s.dependencies.map(d => `<span class="dep-badge" onclick="focusStory('${esc(d)}')">${esc(d)}</span>`).join('');
    const apiList = s.apiEndpoints.map(a => `<code>${esc(a)}</code>`).join(' ');
    const modList = s.affectedModules.map(m => `<span class="module-badge">${esc(m)}</span>`).join('');
    return `
<div class="story-card ${priorityClass(s.priority)}" id="story-${esc(s.id)}"
     data-priority="${esc(s.priority)}" data-sprint="${s.sprint}"
     data-feature="${esc(s.featureId)}" data-role="${esc(s.role)}">
  <div class="story-header" onclick="toggleStory('${esc(s.id)}')">
    <div class="story-meta">
      <span class="story-id">${esc(s.id)}</span>
      <span class="priority-badge ${priorityClass(s.priority)}">${priorityLabel(s.priority)}</span>
      <span class="sprint-badge" style="background:${sprintColor(s.sprint)}">Sprint ${s.sprint}</span>
      <span class="points-badge">⭐ ${s.storyPoints} pts</span>
    </div>
    <h3 class="story-title">${esc(s.title)}</h3>
    <div class="story-sentence">
      <em>As <strong>${esc(s.role)}</strong>, I want to <strong>${esc(s.action)}</strong>
      so that <strong>${esc(s.benefit)}</strong>.</em>
    </div>
    <div class="story-quick">
      <span class="quick-stat">📋 ${s.acceptanceCriteria.length} ACs</span>
      <span class="quick-stat">✅ ${s.definitionOfDone.length} DoD</span>
      ${s.dependencies.length ? `<span class="quick-stat">🔗 ${s.dependencies.length} deps</span>` : ''}
      <span class="expand-icon">▼</span>
    </div>
  </div>
  <div class="story-detail" id="detail-${esc(s.id)}" style="display:none">
    ${acList ? `<div class="detail-section">
      <h4>📋 Acceptance Criteria</h4>
      <div class="ac-list">${acList}</div>
    </div>` : ''}
    ${dodList ? `<div class="detail-section">
      <h4>✅ Definition of Done</h4>
      <ul class="dod-list">${dodList}</ul>
    </div>` : ''}
    ${s.dependencies.length ? `<div class="detail-section">
      <h4>🔗 Dependencies</h4>
      <div class="dep-list">${depBadges}</div>
    </div>` : ''}
    ${s.technicalNotes ? `<div class="detail-section">
      <h4>🔧 Technical Notes</h4>
      <p class="tech-notes">${esc(s.technicalNotes)}</p>
    </div>` : ''}
    ${s.apiEndpoints.length ? `<div class="detail-section">
      <h4>🌐 API Endpoints</h4>
      <div class="api-list">${apiList}</div>
    </div>` : ''}
    ${s.affectedModules.length ? `<div class="detail-section">
      <h4>📦 Affected Modules</h4>
      <div class="module-list">${modList}</div>
    </div>` : ''}
  </div>
</div>`;
}
function renderFeatureSection(f) {
    const cards = f.stories.map(renderStoryCard).join('');
    const totalPts = f.stories.reduce((acc, s) => acc + s.storyPoints, 0);
    return `
<div class="feature-section" id="feature-${esc(f.id)}" data-feature="${esc(f.id)}">
  <div class="feature-header">
    <div class="feature-id">${esc(f.id)}</div>
    <div class="feature-info">
      <h2 class="feature-title">${esc(f.title)}</h2>
      <p class="feature-desc">${esc(f.description)}</p>
    </div>
    <div class="feature-stats">
      <span class="fstat">📖 ${f.stories.length} stories</span>
      <span class="fstat">⭐ ${totalPts} pts</span>
    </div>
  </div>
  <div class="stories-grid">${cards}</div>
</div>`;
}
function renderSprintView(data) {
    const allStories = data.features.flatMap(f => f.stories);
    const maxSprint = Math.max(...allStories.map(s => s.sprint), 1);
    const columns = Array.from({ length: maxSprint }, (_, i) => {
        const sprintNum = i + 1;
        const stories = allStories.filter(s => s.sprint === sprintNum);
        const pts = stories.reduce((a, s) => a + s.storyPoints, 0);
        const cards = stories.map(s => `
      <div class="sprint-card ${priorityClass(s.priority)}" onclick="focusStory('${esc(s.id)}')">
        <div class="sprint-card-id">${esc(s.id)}</div>
        <div class="sprint-card-title">${esc(s.title)}</div>
        <div class="sprint-card-meta">
          <span class="priority-dot ${priorityClass(s.priority)}"></span>
          ${esc(s.role)} · ${s.storyPoints}pts
        </div>
      </div>`).join('');
        return `
    <div class="sprint-column">
      <div class="sprint-col-header" style="border-top:3px solid ${sprintColor(sprintNum)}">
        <strong>Sprint ${sprintNum}</strong>
        <span class="sprint-meta">${stories.length} stories · ${pts} pts</span>
      </div>
      <div class="sprint-cards">${cards || '<p class="empty-sprint">No stories</p>'}</div>
    </div>`;
    }).join('');
    return `<div class="sprint-board">${columns}</div>`;
}
// ─── Main builder ─────────────────────────────────────────────────────────────
function buildUserStoriesHtml(data) {
    const allStories = data.features.flatMap(f => f.stories);
    const allRoles = [...new Set(allStories.map(s => s.role))];
    const maxSprint = Math.max(...allStories.map(s => s.sprint), 1);
    const featureSections = data.features.map(renderFeatureSection).join('');
    const sprintView = renderSprintView(data);
    const assumptionsList = data.assumptions.map(a => `<li>${esc(a)}</li>`).join('');
    const outOfScopeList = data.outOfScope.map(o => `<li>${esc(o)}</li>`).join('');
    const roleFilterOptions = allRoles.map(r => `<option value="${esc(r)}">${esc(r)}</option>`).join('');
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(data.epic.title)} — User Stories</title>
<style>
/* ── Reset & base ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
       background: #f1f5f9; color: #1e293b; line-height: 1.6; }
a { color: #6366f1; }
code { background: #e2e8f0; padding: 1px 5px; border-radius: 4px;
       font-family: 'Fira Code', monospace; font-size: 0.85em; }

/* ── Layout ── */
.app { max-width: 1400px; margin: 0 auto; padding: 0 16px 60px; }

/* ── Epic header ── */
.epic-hero { background: linear-gradient(135deg, #1e1b4b 0%, #312e81 50%, #4c1d95 100%);
             color: white; padding: 40px 48px; border-radius: 0 0 24px 24px; margin-bottom: 32px;
             box-shadow: 0 8px 32px rgba(99,102,241,0.3); }
.epic-hero h1 { font-size: 2rem; font-weight: 700; margin-bottom: 8px; }
.epic-hero .epic-desc { font-size: 1.05rem; opacity: 0.85; margin-bottom: 20px; max-width: 800px; }
.epic-hero .business-value { background: rgba(255,255,255,0.12); border-left: 3px solid #a78bfa;
  padding: 12px 16px; border-radius: 8px; font-size: 0.9rem; margin-bottom: 24px; max-width: 800px; }
.epic-stats { display: flex; gap: 20px; flex-wrap: wrap; }
.epic-stat { background: rgba(255,255,255,0.15); border-radius: 10px; padding: 10px 20px;
             text-align: center; min-width: 100px; }
.epic-stat .val { font-size: 1.8rem; font-weight: 700; }
.epic-stat .lbl { font-size: 0.75rem; opacity: 0.75; text-transform: uppercase; letter-spacing: 0.05em; }
.epic-meta { margin-top: 20px; font-size: 0.8rem; opacity: 0.6; }

/* ── Toolbar ── */
.toolbar { background: white; border-radius: 12px; padding: 14px 20px; margin-bottom: 24px;
           box-shadow: 0 1px 4px rgba(0,0,0,0.08); display: flex; gap: 12px;
           align-items: center; flex-wrap: wrap; }
.tab-group { display: flex; gap: 4px; background: #f1f5f9; border-radius: 8px; padding: 3px; }
.tab { padding: 7px 16px; border-radius: 6px; cursor: pointer; font-size: 0.875rem;
       font-weight: 500; color: #64748b; border: none; background: transparent; transition: all 0.15s; }
.tab.active { background: white; color: #6366f1; box-shadow: 0 1px 4px rgba(0,0,0,0.12); }
.tab:hover:not(.active) { background: rgba(255,255,255,0.6); color: #475569; }
.filters { display: flex; gap: 8px; flex-wrap: wrap; margin-left: auto; }
select, .search-box { padding: 7px 12px; border: 1px solid #e2e8f0; border-radius: 8px;
                      font-size: 0.875rem; outline: none; background: white; color: #1e293b;
                      cursor: pointer; }
select:focus, .search-box:focus { border-color: #6366f1; box-shadow: 0 0 0 3px rgba(99,102,241,0.15); }
.search-box { width: 200px; }
.btn-print { padding: 7px 16px; background: #6366f1; color: white; border: none;
             border-radius: 8px; cursor: pointer; font-size: 0.875rem; font-weight: 500; }
.btn-print:hover { background: #4f46e5; }

/* ── Feature sections ── */
.feature-section { background: white; border-radius: 16px; padding: 24px 28px;
                   margin-bottom: 24px; box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
.feature-header { display: flex; align-items: flex-start; gap: 16px; margin-bottom: 20px;
                  padding-bottom: 16px; border-bottom: 2px solid #f1f5f9; }
.feature-id { background: #6366f1; color: white; font-weight: 700; padding: 6px 12px;
              border-radius: 8px; font-size: 0.875rem; flex-shrink: 0; height: fit-content; }
.feature-info { flex: 1; }
.feature-title { font-size: 1.2rem; font-weight: 600; color: #1e293b; margin-bottom: 4px; }
.feature-desc { color: #64748b; font-size: 0.9rem; }
.feature-stats { display: flex; gap: 8px; flex-direction: column; text-align: right; flex-shrink: 0; }
.fstat { color: #64748b; font-size: 0.85rem; font-weight: 500; }

/* ── Story grid ── */
.stories-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 16px; }

/* ── Story card ── */
.story-card { border: 2px solid #e2e8f0; border-radius: 12px; overflow: hidden;
              transition: box-shadow 0.2s, transform 0.1s; }
.story-card:hover { box-shadow: 0 4px 16px rgba(0,0,0,0.1); transform: translateY(-1px); }
.story-card.p1 { border-left: 4px solid #ef4444; }
.story-card.p2 { border-left: 4px solid #f59e0b; }
.story-card.p3 { border-left: 4px solid #3b82f6; }
.story-card.hidden { display: none; }
.story-card.highlighted { box-shadow: 0 0 0 3px #6366f1, 0 4px 16px rgba(99,102,241,0.3); }

.story-header { padding: 16px; cursor: pointer; background: #fafafa; }
.story-header:hover { background: #f8fafc; }
.story-meta { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px; align-items: center; }
.story-id { font-family: monospace; font-weight: 700; color: #475569; font-size: 0.9rem; }
.priority-badge { font-size: 0.72rem; padding: 2px 8px; border-radius: 100px; font-weight: 600; }
.priority-badge.p1 { background: #fee2e2; color: #b91c1c; }
.priority-badge.p2 { background: #fef3c7; color: #92400e; }
.priority-badge.p3 { background: #dbeafe; color: #1d4ed8; }
.sprint-badge { font-size: 0.72rem; padding: 2px 8px; border-radius: 100px; color: white;
                font-weight: 600; }
.points-badge { font-size: 0.72rem; padding: 2px 8px; border-radius: 100px;
                background: #f0fdf4; color: #166534; font-weight: 600; }
.story-title { font-size: 0.95rem; font-weight: 600; color: #1e293b; margin-bottom: 8px; }
.story-sentence { font-size: 0.85rem; color: #475569; font-style: italic; margin-bottom: 10px;
                  padding: 8px; background: #f8fafc; border-radius: 6px; }
.story-sentence strong { color: #1e293b; font-style: normal; }
.story-quick { display: flex; gap: 8px; align-items: center; }
.quick-stat { font-size: 0.78rem; color: #64748b; }
.expand-icon { margin-left: auto; color: #94a3b8; font-size: 0.75rem; transition: transform 0.2s; }
.expanded .expand-icon { transform: rotate(180deg); }

/* ── Story detail ── */
.story-detail { padding: 0 16px 16px; border-top: 1px solid #f1f5f9; background: white; }
.detail-section { margin-top: 14px; }
.detail-section h4 { font-size: 0.82rem; text-transform: uppercase; letter-spacing: 0.05em;
                     color: #64748b; margin-bottom: 8px; font-weight: 600; }
.ac-list { display: flex; flex-direction: column; gap: 8px; }
.ac-item { display: flex; gap: 10px; background: #f8fafc; border-radius: 8px;
           padding: 10px 12px; font-size: 0.83rem; }
.ac-badge { background: #6366f1; color: white; border-radius: 4px; padding: 1px 6px;
            font-size: 0.7rem; font-weight: 700; height: fit-content; flex-shrink: 0; }
.ac-body { color: #334155; line-height: 1.7; }
.ac-label { font-weight: 700; font-size: 0.72rem; text-transform: uppercase;
            letter-spacing: 0.04em; padding: 1px 5px; border-radius: 3px; }
.ac-label.given { background: #dbeafe; color: #1d4ed8; }
.ac-label.when  { background: #fef3c7; color: #92400e; }
.ac-label.then  { background: #dcfce7; color: #166534; }
.dod-list { list-style: none; display: flex; flex-direction: column; gap: 6px; }
.dod-list li { display: flex; align-items: flex-start; gap: 8px; font-size: 0.85rem;
               color: #334155; }
.dod-list input[type="checkbox"] { margin-top: 3px; cursor: pointer; flex-shrink: 0; }
.dep-list, .module-list, .api-list { display: flex; gap: 6px; flex-wrap: wrap; }
.dep-badge { background: #ede9fe; color: #6d28d9; padding: 3px 10px; border-radius: 100px;
             font-size: 0.78rem; font-weight: 600; cursor: pointer; }
.dep-badge:hover { background: #c4b5fd; }
.module-badge { background: #f1f5f9; color: #475569; padding: 3px 10px; border-radius: 100px;
                font-size: 0.78rem; font-weight: 500; }
.tech-notes { font-size: 0.85rem; color: #475569; background: #fffbeb; border-left: 3px solid #f59e0b;
              padding: 10px 14px; border-radius: 6px; }

/* ── Sprint board ── */
.sprint-board { display: flex; gap: 16px; overflow-x: auto; padding: 4px 0 16px;
                min-height: 200px; }
.sprint-column { background: white; border-radius: 12px; min-width: 260px; flex: 1;
                 box-shadow: 0 1px 4px rgba(0,0,0,0.08); overflow: hidden; }
.sprint-col-header { padding: 14px 18px; border-bottom: 1px solid #f1f5f9; }
.sprint-col-header strong { font-size: 0.95rem; color: #1e293b; display: block; }
.sprint-meta { font-size: 0.78rem; color: #64748b; }
.sprint-cards { padding: 12px; display: flex; flex-direction: column; gap: 8px; }
.sprint-card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 10px 12px;
               cursor: pointer; transition: box-shadow 0.15s; }
.sprint-card:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
.sprint-card.p1 { border-left: 3px solid #ef4444; }
.sprint-card.p2 { border-left: 3px solid #f59e0b; }
.sprint-card.p3 { border-left: 3px solid #3b82f6; }
.sprint-card-id { font-family: monospace; font-size: 0.75rem; font-weight: 700; color: #94a3b8; }
.sprint-card-title { font-size: 0.85rem; font-weight: 600; color: #1e293b; margin: 2px 0 4px; }
.sprint-card-meta { font-size: 0.75rem; color: #64748b; display: flex; align-items: center; gap: 4px; }
.priority-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.priority-dot.p1 { background: #ef4444; }
.priority-dot.p2 { background: #f59e0b; }
.priority-dot.p3 { background: #3b82f6; }
.empty-sprint { color: #94a3b8; font-size: 0.85rem; font-style: italic; text-align: center; padding: 20px; }

/* ── Info panel (assumptions / out-of-scope) ── */
.info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 24px; }
.info-card { background: white; border-radius: 12px; padding: 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
.info-card h3 { font-size: 0.9rem; font-weight: 600; margin-bottom: 12px; color: #475569; text-transform: uppercase; letter-spacing: 0.04em; }
.info-card ul { list-style: none; display: flex; flex-direction: column; gap: 6px; }
.info-card li { font-size: 0.85rem; color: #334155; padding-left: 16px; position: relative; }
.info-card li::before { content: '•'; position: absolute; left: 0; color: #6366f1; font-weight: 700; }
.system-findings { background: white; border-radius: 12px; padding: 20px; margin-bottom: 24px;
                   box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
.system-findings h3 { font-size: 0.9rem; font-weight: 600; margin-bottom: 10px; color: #475569;
                      text-transform: uppercase; letter-spacing: 0.04em; }
.system-findings p { font-size: 0.88rem; color: #334155; white-space: pre-wrap; line-height: 1.8; }

/* ── View containers ── */
.view { display: none; }
.view.active { display: block; }

/* ── Empty state ── */
.empty-state { text-align: center; padding: 60px 20px; color: #94a3b8; font-size: 0.9rem; }

/* ── Print ── */
@media print {
  .toolbar, .btn-print { display: none !important; }
  .story-detail { display: block !important; }
  .story-card { break-inside: avoid; }
  body { background: white; }
  .epic-hero { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
}
</style>
</head>
<body>
<div class="app">

  <!-- Epic Hero -->
  <div class="epic-hero">
    <h1>📦 ${esc(data.epic.title)}</h1>
    <p class="epic-desc">${esc(data.epic.description)}</p>
    ${data.epic.businessValue ? `<div class="business-value">🎯 <strong>Business Value:</strong> ${esc(data.epic.businessValue)}</div>` : ''}
    <div class="epic-stats">
      <div class="epic-stat"><div class="val">${data.features.length}</div><div class="lbl">Features</div></div>
      <div class="epic-stat"><div class="val">${data.epic.totalStories}</div><div class="lbl">User Stories</div></div>
      <div class="epic-stat"><div class="val">${data.epic.totalPoints}</div><div class="lbl">Story Points</div></div>
      <div class="epic-stat"><div class="val">${data.epic.estimatedSprints}</div><div class="lbl">Sprints</div></div>
    </div>
    <div class="epic-meta">📅 Generated: ${esc(data.generatedAt)} · Project: ${esc(data.projectName)} · Auto Spec extension</div>
  </div>

  <!-- Toolbar -->
  <div class="toolbar">
    <div class="tab-group">
      <button class="tab active" onclick="switchTab('stories')">📖 All Stories</button>
      <button class="tab" onclick="switchTab('sprint')">🗓 Sprint View</button>
      <button class="tab" onclick="switchTab('info')">ℹ️ Context</button>
    </div>
    <div class="filters">
      <input class="search-box" type="search" placeholder="🔍 Search stories..."
             oninput="filterStories()" id="search-box">
      <select onchange="filterStories()" id="filter-priority">
        <option value="">All Priorities</option>
        <option value="P1">🔴 P1 Critical</option>
        <option value="P2">🟡 P2 High</option>
        <option value="P3">🔵 P3 Normal</option>
      </select>
      <select onchange="filterStories()" id="filter-sprint">
        <option value="">All Sprints</option>
        ${Array.from({ length: maxSprint }, (_, i) => `<option value="${i + 1}">Sprint ${i + 1}</option>`).join('')}
      </select>
      <select onchange="filterStories()" id="filter-role">
        <option value="">All Roles</option>
        ${roleFilterOptions}
      </select>
    </div>
    <button class="btn-print" onclick="window.print()">🖨 Print</button>
  </div>

  <!-- Stories View -->
  <div id="view-stories" class="view active">${featureSections}</div>

  <!-- Sprint View -->
  <div id="view-sprint" class="view">${sprintView}</div>

  <!-- Context View -->
  <div id="view-info" class="view">
    ${data.systemFindings ? `<div class="system-findings">
      <h3>🔍 System Investigation Findings</h3>
      <p>${esc(data.systemFindings)}</p>
    </div>` : ''}
    <div class="info-grid">
      ${data.assumptions.length ? `<div class="info-card">
        <h3>💡 Assumptions</h3>
        <ul>${data.assumptions.map(a => `<li>${esc(a)}</li>`).join('')}</ul>
      </div>` : ''}
      ${data.outOfScope.length ? `<div class="info-card">
        <h3>🚫 Out of Scope</h3>
        <ul>${data.outOfScope.map(o => `<li>${esc(o)}</li>`).join('')}</ul>
      </div>` : ''}
    </div>
  </div>

</div><!-- end .app -->

<script>
// ── Tab switching ──
function switchTab(tab) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.getElementById('view-' + tab).classList.add('active');
  event.target.classList.add('active');
}

// ── Story expand/collapse ──
function toggleStory(id) {
  const detail = document.getElementById('detail-' + id);
  const card   = document.getElementById('story-' + id);
  const isOpen = detail.style.display !== 'none';
  detail.style.display = isOpen ? 'none' : 'block';
  card.classList.toggle('expanded', !isOpen);
}

// ── Focus a story (e.g. from sprint board click or dep badge click) ──
function focusStory(id) {
  switchTab('stories');
  setTimeout(() => {
    document.querySelectorAll('.tab')[0].classList.add('active');
    const card = document.getElementById('story-' + id);
    if (!card) { return; }
    card.scrollIntoView({ behavior: 'smooth', block: 'center' });
    card.classList.add('highlighted');
    const detail = document.getElementById('detail-' + id);
    if (detail) { detail.style.display = 'block'; card.classList.add('expanded'); }
    setTimeout(() => card.classList.remove('highlighted'), 2500);
  }, 50);
}

// ── Filter stories ──
function filterStories() {
  const q  = document.getElementById('search-box').value.toLowerCase();
  const pr = document.getElementById('filter-priority').value;
  const sp = document.getElementById('filter-sprint').value;
  const ro = document.getElementById('filter-role').value;
  let visible = 0;
  document.querySelectorAll('.story-card').forEach(card => {
    const titleEl = card.querySelector('.story-title');
    const titleText = (titleEl ? titleEl.textContent : '').toLowerCase();
    const sentEl = card.querySelector('.story-sentence');
    const sentText = (sentEl ? sentEl.textContent : '').toLowerCase();
    const matchQ  = !q  || titleText.includes(q) || sentText.includes(q);
    const matchPr = !pr || card.dataset.priority === pr;
    const matchSp = !sp || card.dataset.sprint    === sp;
    const matchRo = !ro || card.dataset.role      === ro;
    const show    = matchQ && matchPr && matchSp && matchRo;
    card.classList.toggle('hidden', !show);
    if (show) { visible++; }
  });
  // Show/hide feature sections if all their stories are hidden
  document.querySelectorAll('.feature-section').forEach(sec => {
    const anyVisible = sec.querySelectorAll('.story-card:not(.hidden)').length > 0;
    sec.style.display = anyVisible ? '' : 'none';
  });
}

// ── Keyboard shortcut: Ctrl+P = print ──
document.addEventListener('keydown', e => {
  if ((e.ctrlKey || e.metaKey) && e.key === 'p') { e.preventDefault(); window.print(); }
});
</script>
</body>
</html>`;
}
const crypto = __importStar(require("crypto"));
// ═══════════════════════════════════════════════════════════════════════════
// Markdown → safe HTML (small, dependency-free subset) + document page builder
// Used by the /document command. All text is HTML-escaped before formatting.
// ═══════════════════════════════════════════════════════════════════════════
function mdInline(s) {
    let t = esc(s);
    t = t.replace(/`([^`]+)`/g, (_m, c) => `<code>${c}</code>`);
    // Images ![alt](src) — before links, since the syntaxes differ only by the leading '!'.
    // Only http(s), a relative path or a data: URI; anything else stays literal text.
    t = t.replace(/!\[([^\]]*)\]\((https?:\/\/[^\s)]+|data:image\/[^\s)]+|[^\s):]+)\)/g,
        (_m, alt, src) => `<img src="${src}" alt="${alt}">`);
    t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    // Single-asterisk italics — run AFTER ** so bold is already consumed and cannot be re-matched.
    t = t.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<em>$2</em>');
    t = t.replace(/(^|[^_])_([^_]+)_(?!_)/g, '$1<em>$2</em>');
    t = t.replace(/~~([^~]+)~~/g, '<del>$1</del>');
    // Only allow http(s) links; everything else stays literal text.
    t = t.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (_m, txt, url) => `<a href="${url}" rel="noopener noreferrer" target="_blank">${txt}</a>`);
    return t;
}
function renderMdTable(rows) {
    const parse = (line) => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
    const header = parse(rows[0]);
    const body = rows.slice(2).map(parse); // rows[1] is the |---|---| separator
    let h = '<table><thead><tr>' + header.map(c => `<th>${mdInline(c)}</th>`).join('') + '</tr></thead><tbody>';
    for (const r of body) {
        h += '<tr>' + r.map(c => `<td>${mdInline(c)}</td>`).join('') + '</tr>';
    }
    return h + '</tbody></table>';
}
function markdownToHtml(md) {
    const lines = (md ?? '').replace(/\r\n/g, '\n').split('\n');
    const out = [];
    let i = 0;
    let listType = null;
    const closeList = () => { if (listType) {
        out.push(`</${listType}>`);
        listType = null;
    } };
    while (i < lines.length) {
        const line = lines[i];
        // Code fence
        const fence = line.match(/^\s*```(\w*)\s*$/);
        if (fence) {
            closeList();
            const buf = [];
            i++;
            while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) {
                buf.push(lines[i]);
                i++;
            }
            i++; // skip closing fence
            const lang = (fence[1] || '').toLowerCase();
            if (lang === 'mermaid') {
                // Mermaid renders the div's text as a diagram. Strip any tags defensively.
                // HTML-escape rather than regex-strip: /<[^>]*>/g only removes COMPLETE tags, so an
                // unterminated `<img src=x onerror=…` survived and the parser reassembled it from the
                // following markup. Mermaid reads textContent, so escaping the source is lossless.
                out.push(`<div class="mermaid">${esc(buf.join('\n'))}</div>`);
            }
            else {
                out.push(`<pre><code>${esc(buf.join('\n'))}</code></pre>`);
            }
            continue;
        }
        // Table (current line + next look like a table with a separator row)
        if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|?[\s:|-]+\|?\s*$/.test(lines[i + 1]) && lines[i + 1].includes('-')) {
            closeList();
            const rows = [];
            while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
                rows.push(lines[i]);
                i++;
            }
            out.push(renderMdTable(rows));
            continue;
        }
        // Heading
        const h = line.match(/^(#{1,6})\s+(.*)$/);
        if (h) {
            closeList();
            out.push(`<h${h[1].length}>${mdInline(h[2])}</h${h[1].length}>`);
            i++;
            continue;
        }
        // Horizontal rule
        if (/^\s*([-*_])\1\1+\s*$/.test(line)) {
            closeList();
            out.push('<hr>');
            i++;
            continue;
        }
        // Blockquote — consume the whole run of `> ` lines so it renders as one quote
        if (/^\s*>\s?/.test(line)) {
            closeList();
            const buf = [];
            while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
                buf.push(lines[i].replace(/^\s*>\s?/, ''));
                i++;
            }
            out.push(`<blockquote>${markdownToHtml(buf.join('\n'))}</blockquote>`);
            continue;
        }
        // Unordered list
        const ul = line.match(/^\s*[-*]\s+(.*)$/);
        if (ul) {
            if (listType !== 'ul') {
                closeList();
                out.push('<ul>');
                listType = 'ul';
            }
            out.push(`<li>${mdInline(ul[1])}</li>`);
            i++;
            continue;
        }
        // Ordered list
        const ol = line.match(/^\s*\d+\.\s+(.*)$/);
        if (ol) {
            if (listType !== 'ol') {
                closeList();
                out.push('<ol>');
                listType = 'ol';
            }
            out.push(`<li>${mdInline(ol[1])}</li>`);
            i++;
            continue;
        }
        // Blank line
        if (/^\s*$/.test(line)) {
            closeList();
            i++;
            continue;
        }
        // Paragraph
        closeList();
        out.push(`<p>${mdInline(line)}</p>`);
        i++;
    }
    closeList();
    return out.join('\n');
}
function buildDocumentHtml(topic, markdown) {
    const body = markdownToHtml(markdown);
    const safeTopic = esc(topic);
    const hasMermaid = /class="mermaid"/.test(body);
    const nonce = randomNonce();
    const csp = hasMermaid
        ? `default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data: file: https:; font-src data: https:; script-src 'nonce-${nonce}' https://cdnjs.cloudflare.com;`
        : `default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data: file: https:;`;
    const mermaidTags = hasMermaid
        ? `<script nonce="${nonce}" src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.8/mermaid.min.js"></script>
<script nonce="${nonce}">try{
// startOnLoad:true — mermaid waits for DOMContentLoaded itself. This script sits in <head>, so a
// manual run() here would find no .mermaid nodes yet (and double-render once they appear).
// useMaxWidth keeps each diagram inside the page/container width so print never clips it.
mermaid.initialize({startOnLoad:true,theme:'dark',securityLevel:'strict',
  flowchart:{useMaxWidth:true},sequence:{useMaxWidth:true},er:{useMaxWidth:true},gantt:{useMaxWidth:true},
  // The stock dark theme still paints sequence message labels and some edge text almost black —
  // pin every text/line colour so nothing disappears into the page.
  themeVariables:{background:'#141a28',mainBkg:'#1f2937',textColor:'#e6e9ef',lineColor:'#94a3b8',
    primaryColor:'#1f2937',primaryTextColor:'#e6e9ef',primaryBorderColor:'#6366f1',
    secondaryColor:'#312e81',tertiaryColor:'#111726',nodeBorder:'#6366f1',nodeTextColor:'#e6e9ef',
    clusterBkg:'#141a28',clusterBorder:'#2a3040',edgeLabelBackground:'#141a28',
    actorBkg:'#1f2937',actorBorder:'#6366f1',actorTextColor:'#e6e9ef',actorLineColor:'#94a3b8',
    signalColor:'#cbd5e1',signalTextColor:'#e6e9ef',labelBoxBkgColor:'#1f2937',
    labelBoxBorderColor:'#6366f1',labelTextColor:'#e6e9ef',loopTextColor:'#e6e9ef',
    noteBkgColor:'#374151',noteTextColor:'#f9fafb',noteBorderColor:'#6b7280',
    altBackground:'#111726',classText:'#e6e9ef',titleColor:'#f2f4f8'}});
}catch(e){}</script>`
        : '';
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${safeTopic} — Document</title>
${mermaidTags}
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
/* Dark theme end to end. It has to be dark on screen too: Mermaid bakes its colours into the SVG
   when it renders, so a diagram cannot be re-themed at print time — the page and the diagram must
   agree from the start, which is also why the PDF matches what you see in the browser. */
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#e6e9ef;line-height:1.65;background:#0f1420}
.doc{max-width:980px;margin:0 auto;padding:40px 32px 80px}
h1{font-size:1.9rem;font-weight:750;margin:0 0 8px;color:#f2f4f8;border-bottom:3px solid #6366f1;padding-bottom:12px}
h2{font-size:1.3rem;font-weight:700;margin:30px 0 10px;color:#f2f4f8}
h3{font-size:1.05rem;font-weight:650;margin:20px 0 8px;color:#dfe4ee}
h4{font-size:.95rem;font-weight:650;margin:16px 0 6px;color:#c3cad8}
p{margin:8px 0}
em{color:#a8b0c0}
a{color:#9bb0ff}
code{background:#1b2130;color:#c9d2ff;padding:1px 6px;border-radius:5px;font-family:'Fira Code',ui-monospace,monospace;font-size:.86em}
pre{background:#0b1020;color:#e2e8f0;border:1px solid #2a3040;padding:14px 16px;border-radius:10px;overflow-x:auto;margin:12px 0}
pre code{background:none;color:inherit;padding:0}
ul,ol{margin:8px 0 8px 26px}
li{margin:4px 0}
hr{border:none;border-top:1px solid #2a3040;margin:24px 0}
blockquote{margin:12px 0;padding:10px 16px;border-left:3px solid #6366f1;background:#141a28;border-radius:0 8px 8px 0;color:#c3cad8}
blockquote p{margin:.25em 0}
del{opacity:.7}
table{border-collapse:collapse;width:100%;margin:14px 0;font-size:.9rem;border:1px solid #2a3040;border-radius:8px;overflow:hidden}
th{background:#4f46e5;color:#fff;text-align:left;padding:9px 12px;font-weight:600;font-size:.82rem}
td{padding:9px 12px;border-top:1px solid #2a3040;vertical-align:top;background:#151b29}
tr:nth-child(even) td{background:#111726}
.meta{color:#8b94a7;font-size:.8rem;margin-top:6px}
/* A raster diagram is usually black line-art on white or on transparency — it needs a light backing
   or it vanishes on a dark page. Photos just gain a thin light frame, which is harmless. */
img{max-width:100%;height:auto;background:#fff;padding:6px;border-radius:8px}
.mermaid{background:#141a28;border:1px solid #2a3040;border-radius:10px;padding:16px;margin:14px 0;text-align:center;overflow-x:auto}
/* Mermaid scopes its styles by the SVG id, so its own (often dark) text colours beat any theme
   variable we pass. Pin them here with !important — this is what keeps sequence message labels,
   actor names and edge labels readable on the dark card. */
.mermaid svg text,.mermaid svg .messageText,.mermaid svg .labelText,.mermaid svg .loopText,
.mermaid svg .noteText,.mermaid svg .titleText,.mermaid svg .sectionTitle,
.mermaid svg .taskText,.mermaid svg tspan{fill:#e6e9ef!important}
.mermaid svg .nodeLabel,.mermaid svg .edgeLabel,.mermaid svg .label{color:#e6e9ef!important;fill:#e6e9ef!important}
.mermaid svg .edgeLabel rect,.mermaid svg .labelBkg{fill:#141a28!important;background:#141a28!important;opacity:.9}
.mermaid svg .actor,.mermaid svg .node rect,.mermaid svg .node polygon,.mermaid svg .node circle,
.mermaid svg .node ellipse,.mermaid svg .node path{fill:#1f2937!important;stroke:#6366f1!important}
.mermaid svg .actor tspan,.mermaid svg .actor text{fill:#e6e9ef!important}
.mermaid svg line,.mermaid svg .messageLine0,.mermaid svg .messageLine1,
.mermaid svg .edgePath path,.mermaid svg .flowchart-link,.mermaid svg .actor-line{stroke:#94a3b8!important}
.mermaid svg marker path,.mermaid svg .arrowheadPath{fill:#94a3b8!important;stroke:#94a3b8!important}
.mermaid svg .sequenceNumber{fill:#0f1420!important}
.mermaid svg{max-width:100%;height:auto}
/* Print / PDF: keep blocks whole, never rely on scrolling (paper has none), keep colours. */
@page{size:A4;margin:14mm 12mm;background:#0f1420}
@media print{
  /* Dark page. print-color-adjust:exact is what stops the browser dropping backgrounds when printing. */
  /* The document is dark already — print-color-adjust is what stops the browser discarding those
     backgrounds when it prints. */
  html,body{-webkit-print-color-adjust:exact;print-color-adjust:exact}
  .doc{max-width:100%;padding:0}
  /* Diagrams are already dark-themed (Mermaid theme:'dark'), so nothing needs recolouring here.
     Raster images keep their light backing from the base stylesheet — black line-art on transparency
     would otherwise disappear into the page. */
  /* a diagram, table, code block or quote must not be split across pages */
  .mermaid,table,pre,blockquote,figure{break-inside:avoid;page-break-inside:avoid}
  tr,li{break-inside:avoid;page-break-inside:avoid}
  thead{display:table-header-group}            /* repeat headers on long tables */
  h1,h2,h3,h4{break-after:avoid;page-break-after:avoid}   /* no orphan heading at a page foot */
  /* overflow is CUT on paper — let wide content shrink or wrap instead */
  .mermaid{overflow:visible;padding:8px;break-inside:avoid}
  /* Scale an oversized diagram down so it fits ONE page instead of spilling across pages.
     A4 usable height ≈ 269mm; cap below that to leave room for the box padding/border. */
  .mermaid svg{width:auto!important;height:auto!important;max-width:100%!important;max-height:170mm!important}
  pre{overflow:visible;white-space:pre-wrap;word-break:break-word}
  table{box-shadow:none}
  a{text-decoration:none}
}
</style>
</head>
<body>
<div class="doc">
${body}
<hr>
<p class="meta">Generated by Auto Spec extension · ${esc(new Date().toLocaleString('en-US'))}</p>
</div>
</body>
</html>`;
}
/** Cryptographically-random nonce for the webview Content-Security-Policy. */
function randomNonce() {
    return crypto.randomBytes(16).toString('base64').replace(/[^A-Za-z0-9]/g, '');
}
function buildKnowledgeGraphHtml(graph) {
    // Neutralise "</script>" / "<!--" breakout from any string embedded in the JSON
    // (node labels, descriptions and AI-enriched text are untrusted content).
    const graphJson = JSON.stringify(graph)
        .replace(/</g, '\\u003c')
        .replace(/>/g, '\\u003e')
        .replace(/\u2028/g, '\\u2028')
        .replace(/\u2029/g, '\\u2029');
    const { projectName, generatedAt, nodeCount, edgeCount } = graph.metadata;
    const safeProjectName = esc(projectName);
    // Per-render nonce so the Content-Security-Policy can whitelist only our own
    // inline scripts and block any injected <script> from graph content.
    const nonce = randomNonce();
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' data: file: https: https:; style-src 'unsafe-inline'; font-src data:; connect-src 'none'; script-src 'nonce-${nonce}' https://cdnjs.cloudflare.com;">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🔭 Knowledge Graph — ${safeProjectName}</title>
<script nonce="${nonce}" src="https://cdnjs.cloudflare.com/ajax/libs/d3/7.9.0/d3.min.js"></script>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg: #0d1117; --surface: #161b22; --surface2: #21262d;
    --border: #30363d; --text: #e6edf3; --text-muted: #8b949e;
    --accent: #58a6ff; --accent2: #3fb950; --danger: #f85149;
    --radius: 8px;
  }

  body { background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; height: 100vh; overflow: hidden; display: flex; flex-direction: column; }

  /* ── Header ── */
  .header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 10px 16px; display: flex; align-items: center; gap: 12px; flex-shrink: 0; }
  .header h1 { font-size: 15px; font-weight: 600; color: var(--text); }
  .header .meta { color: var(--text-muted); font-size: 12px; margin-left: auto; }
  .search-box { background: var(--surface2); border: 1px solid var(--border); border-radius: var(--radius); padding: 5px 10px; color: var(--text); font-size: 13px; width: 200px; outline: none; }
  .search-box:focus { border-color: var(--accent); }

  /* ── Tabs ── */
  .tabs { display: flex; gap: 0; background: var(--surface); border-bottom: 1px solid var(--border); flex-shrink: 0; padding: 0 16px; }
  .tab { padding: 8px 16px; font-size: 13px; cursor: pointer; border-bottom: 2px solid transparent; color: var(--text-muted); transition: all .2s; user-select: none; }
  .tab:hover { color: var(--text); }
  .tab.active { color: var(--accent); border-bottom-color: var(--accent); }

  /* ── Main area ── */
  .main { display: flex; flex: 1; overflow: hidden; }

  /* ── Graph canvas ── */
  .graph-area { flex: 1; position: relative; overflow: hidden; }
  svg.graph { width: 100%; height: 100%; }

  /* ── Nodes ── */
  .node circle { cursor: pointer; stroke: var(--bg); stroke-width: 2px; transition: r .2s; }
  .node circle:hover { stroke: #fff; stroke-width: 2.5px; filter: brightness(1.3); }
  .node.selected circle { stroke: #fff; stroke-width: 3px; filter: brightness(1.4) drop-shadow(0 0 8px currentColor); }
  .node text { font-size: 11px; fill: var(--text); pointer-events: none; text-shadow: 0 1px 3px #000a; }

  /* ── Edges ── */
  .link { stroke: var(--border); stroke-opacity: 0.6; stroke-width: 1.5; }
  .link.imports  { stroke: #58a6ff55; }
  .link.calls    { stroke: #3fb95055; }
  .link.depends  { stroke: #f7a34f55; }
  .link.flows-to { stroke: #9b59b655; stroke-dasharray: 4 3; }
  .link.defines  { stroke: #e74c3c44; stroke-dasharray: 2 4; }
  .link-label { font-size: 9px; fill: var(--text-muted); pointer-events: none; }

  /* ── Detail panel ── */
  .detail-panel { width: 280px; background: var(--surface); border-left: 1px solid var(--border); overflow-y: auto; flex-shrink: 0; transition: width .2s; }
  .detail-panel.hidden { width: 0; overflow: hidden; }
  .detail-content { padding: 16px; }
  .detail-content h2 { font-size: 15px; margin-bottom: 4px; color: var(--text); }
  .detail-content .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; color: #fff; margin-bottom: 10px; }
  .detail-content .desc { font-size: 13px; color: var(--text-muted); line-height: 1.6; margin-bottom: 12px; }
  .detail-content .details-raw { font-size: 11px; color: var(--text-muted); background: var(--surface2); border-radius: 6px; padding: 10px; font-family: monospace; white-space: pre-wrap; word-break: break-word; max-height: 220px; overflow-y: auto; border: 1px solid var(--border); }
  .detail-content .node-meta { font-size: 11px; color: var(--text-muted); margin: 0 0 10px; font-family: monospace; word-break: break-word; }
  .detail-content .chip-list { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 8px; }
  .detail-content .chip { background: var(--surface2); border: 1px solid var(--border); border-radius: 5px; padding: 2px 7px; font-size: 11px; font-family: monospace; color: var(--accent2); }
  .detail-content .chip-field { color: #d8b4fe; }
  .detail-content .open-file { margin-top: 10px; display: inline-block; padding: 5px 12px; background: var(--accent); color: #fff; border-radius: var(--radius); font-size: 12px; cursor: pointer; border: none; text-decoration: none; }
  .detail-content .open-file:hover { background: #79b8ff; }
  .detail-content h3 { font-size: 12px; color: var(--text-muted); margin: 12px 0 6px; text-transform: uppercase; letter-spacing: .5px; }
  .conn-list { list-style: none; }
  .conn-list li { font-size: 12px; padding: 3px 0; color: var(--text-muted); border-bottom: 1px solid var(--border); }
  .conn-list li span { color: var(--text); }

  /* ── Legend ── */
  .legend { position: absolute; bottom: 16px; left: 16px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 10px 14px; font-size: 12px; }
  .legend-item { display: flex; align-items: center; gap: 8px; padding: 2px 0; color: var(--text-muted); }
  .legend-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }

  /* ── Stats bar ── */
  .stats { position: absolute; top: 12px; right: 12px; display: flex; gap: 8px; }
  .stat-chip { background: var(--surface); border: 1px solid var(--border); border-radius: 20px; padding: 3px 10px; font-size: 11px; color: var(--text-muted); }

  /* ── Zoom controls ── */
  .zoom-controls { position: absolute; bottom: 16px; right: 16px; display: flex; flex-direction: column; gap: 4px; }
  .zoom-btn { background: var(--surface2); border: 1px solid var(--border); border-radius: 6px; width: 30px; height: 30px; color: var(--text); font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; }
  .zoom-btn:hover { background: var(--surface); }

  /* ── Empty state ── */
  .empty-state { display: flex; align-items: center; justify-content: center; height: 100%; flex-direction: column; gap: 12px; color: var(--text-muted); font-size: 14px; }
</style>
</head>
<body>

<div class="header">
  <span>🔭</span>
  <h1>${safeProjectName} — Knowledge Graph</h1>
  <input class="search-box" id="searchBox" placeholder="🔍  Search nodes…" />
  <span class="meta">Generated ${new Date(generatedAt).toLocaleDateString()} · ${nodeCount} nodes · ${edgeCount} edges</span>
</div>

<div class="tabs" id="tabBar">
  <div class="tab active" data-view="all">All</div>
  <div class="tab" data-view="architecture">Architecture</div>
  <div class="tab" data-view="workflow">Workflow</div>
  <div class="tab" data-view="domain">Domain / KB</div>
  <div class="tab" data-view="files">Source Files</div>
</div>

<div class="main">
  <div class="graph-area" id="graphArea">
    <svg class="graph" id="graphSvg"></svg>
    <div class="legend" id="legend"></div>
    <div class="stats">
      <span class="stat-chip" id="statNodes"></span>
      <span class="stat-chip" id="statEdges"></span>
    </div>
    <div class="zoom-controls">
      <button class="zoom-btn" id="zoomIn">+</button>
      <button class="zoom-btn" id="zoomFit">⊡</button>
      <button class="zoom-btn" id="zoomOut">−</button>
    </div>
  </div>
  <div class="detail-panel hidden" id="detailPanel">
    <div class="detail-content" id="detailContent"></div>
  </div>
</div>

<script nonce="${nonce}">
const RAW_GRAPH = ${graphJson};

// ── Colour map ───────────────────────────────────────────────────────────────
const LAYER_COLORS = {};
RAW_GRAPH.layers.forEach(l => { LAYER_COLORS[l.id] = l.color; });

// ── VS Code webview communication ────────────────────────────────────────────
const vscode = (typeof acquireVsCodeApi !== 'undefined') ? acquireVsCodeApi() : null;
function openFile(filePath) {
  if (vscode) { vscode.postMessage({ command: 'openFile', filePath }); }
}
// Delegated handler (CSP-safe — no inline onclick) for dynamically-rendered "Open File" buttons.
document.getElementById('detailContent').addEventListener('click', e => {
  const btn = e.target.closest('.open-file');
  if (btn && btn.dataset.file) { openFile(btn.dataset.file); }
});

// ── View filter ──────────────────────────────────────────────────────────────
let currentView = 'all';
let searchQuery = '';
let simulation, svg, zoomBehavior, linkSel, nodeSel, labelSel;
let selectedNodeId = null;

function filterGraph(view, query) {
  const q = query.toLowerCase();
  let nodes = RAW_GRAPH.nodes;
  if (view === 'architecture') nodes = nodes.filter(n => n.id.startsWith('arch:'));
  else if (view === 'workflow')     nodes = nodes.filter(n => ['workflow','command'].includes(n.type));
  else if (view === 'domain')       nodes = nodes.filter(n => n.id.startsWith('kb:') || n.layer === 'domain');
  else if (view === 'files')        nodes = nodes.filter(n => n.id.startsWith('file:'));

  if (q) {
    nodes = nodes.filter(n =>
      n.label.toLowerCase().includes(q) ||
      (n.description || '').toLowerCase().includes(q)
    );
  }

  const nodeIds = new Set(nodes.map(n => n.id));
  const edges = RAW_GRAPH.edges.filter(e => nodeIds.has(e.source) && nodeIds.has(e.target));
  return { nodes, edges };
}

// ── D3 graph ─────────────────────────────────────────────────────────────────
function renderGraph(view, query) {
  const { nodes, edges } = filterGraph(view, query);
  const area = document.getElementById('graphArea');
  const svgEl = document.getElementById('graphSvg');
  const W = area.clientWidth, H = area.clientHeight;

  // Update stats
  document.getElementById('statNodes').textContent = nodes.length + ' nodes';
  document.getElementById('statEdges').textContent = edges.length + ' edges';

  // Clear previous
  d3.select(svgEl).selectAll('*').remove();
  if (nodes.length === 0) {
    d3.select(svgEl).append('text')
      .attr('x', W / 2).attr('y', H / 2)
      .attr('text-anchor', 'middle').attr('fill', '#8b949e')
      .text('No nodes match this filter.');
    return;
  }

  svg = d3.select(svgEl);
  const g = svg.append('g').attr('class', 'canvas');

  // Zoom
  zoomBehavior = d3.zoom().scaleExtent([0.05, 4]).on('zoom', e => {
    g.attr('transform', e.transform);
  });
  svg.call(zoomBehavior);

  // Copy nodes/edges for simulation (D3 mutates source/target)
  const simNodes = nodes.map(n => ({ ...n }));
  const simEdgesRaw = edges.map(e => ({ ...e }));

  // Build id→index map
  const idxMap = {};
  simNodes.forEach((n, i) => { idxMap[n.id] = i; });

  const simEdges = simEdgesRaw
    .filter(e => idxMap[e.source] !== undefined && idxMap[e.target] !== undefined)
    .map(e => ({ ...e, source: idxMap[e.source], target: idxMap[e.target] }));

  // Simulation
  simulation = d3.forceSimulation(simNodes)
    .force('link',   d3.forceLink(simEdges).distance(d => d.type === 'defines' ? 60 : 120).strength(0.5))
    .force('charge', d3.forceManyBody().strength(-300))
    .force('center', d3.forceCenter(W / 2, H / 2))
    .force('collide', d3.forceCollide(d => nodeRadius(d) + 8));

  // Arrowhead markers
  const defs = svg.append('defs');
  ['imports','calls','depends','flows-to','defines'].forEach(t => {
    defs.append('marker')
      .attr('id', 'arrow-' + t)
      .attr('viewBox', '0 -4 8 8')
      .attr('refX', 16).attr('refY', 0)
      .attr('markerWidth', 6).attr('markerHeight', 6)
      .attr('orient', 'auto')
      .append('path').attr('d', 'M0,-4L8,0L0,4').attr('fill', '#30363d');
  });

  // Edges
  linkSel = g.append('g').selectAll('line')
    .data(simEdges).enter().append('line')
    .attr('class', d => 'link ' + d.type)
    .attr('marker-end', d => 'url(#arrow-' + d.type + ')');

  // Nodes
  nodeSel = g.append('g').selectAll('.node')
    .data(simNodes).enter().append('g')
    .attr('class', 'node')
    .attr('data-id', d => d.id)
    .call(d3.drag()
      .on('start', (event, d) => {
        if (!event.active) { simulation.alphaTarget(0.3).restart(); }
        d.fx = d.x; d.fy = d.y;
      })
      .on('drag', (event, d) => { d.fx = event.x; d.fy = event.y; })
      .on('end',  (event, d) => {
        if (!event.active) { simulation.alphaTarget(0); }
        d.fx = null; d.fy = null;
      })
    )
    .on('click', (event, d) => {
      event.stopPropagation();
      selectNode(d.id, simNodes, simEdges);
    });

  nodeSel.append('circle')
    .attr('r', d => nodeRadius(d))
    .attr('fill', d => LAYER_COLORS[d.layer] || '#555');

  nodeSel.append('text')
    .attr('dy', d => nodeRadius(d) + 12)
    .attr('text-anchor', 'middle')
    .text(d => d.label.length > 18 ? d.label.slice(0, 16) + '…' : d.label);

  // Click on background → deselect
  svg.on('click', () => {
    selectedNodeId = null;
    nodeSel.classed('selected', false);
    document.getElementById('detailPanel').classList.add('hidden');
  });

  // Tick
  simulation.on('tick', () => {
    linkSel
      .attr('x1', d => d.source.x).attr('y1', d => d.source.y)
      .attr('x2', d => d.target.x).attr('y2', d => d.target.y);
    nodeSel.attr('transform', d => 'translate(' + d.x + ',' + d.y + ')');
  });

  // Legend
  buildLegend(nodes);
}

function nodeRadius(d) {
  const s = d.size || 2;
  return 6 + s * 2.5;
}

function selectNode(id, simNodes, simEdges) {
  selectedNodeId = id;
  const node = RAW_GRAPH.nodes.find(n => n.id === id);
  if (!node) { return; }

  // Highlight
  d3.selectAll('.node').classed('selected', d => d.id === id);

  // Connections
  const incoming = simEdges.filter(e => (e.target.id || simNodes[e.target]?.id) === id)
    .map(e => ({ label: e.type, name: (e.source.label || simNodes[e.source]?.label || '') }));
  const outgoing = simEdges.filter(e => (e.source.id || simNodes[e.source]?.id) === id)
    .map(e => ({ label: e.type, name: (e.target.label || simNodes[e.target]?.label || '') }));

  // Panel
  const panel = document.getElementById('detailPanel');
  const content = document.getElementById('detailContent');
  panel.classList.remove('hidden');

  const color = LAYER_COLORS[node.layer] || '#555';
  const fileHtml = node.file
    ? '<button class="open-file" data-file="' + esc(node.file) + '">📂 Open File</button>'
    : '';

  const inHtml = incoming.slice(0, 12).map(c =>
    '<li>← <span>' + esc(c.name) + '</span> <small>(' + c.label + ')</small></li>'
  ).join('');
  const outHtml = outgoing.slice(0, 12).map(c =>
    '<li>→ <span>' + esc(c.name) + '</span> <small>(' + c.label + ')</small></li>'
  ).join('');

  // Meta line: type · language · file:line
  const metaBits = [];
  if (node.type) { metaBits.push(esc(node.type)); }
  if (node.language && node.language !== 'unknown') { metaBits.push(esc(node.language)); }
  if (node.file) { metaBits.push(esc(node.file) + (node.line ? ':' + node.line : '')); }
  const metaHtml = metaBits.length ? '<div class="node-meta">' + metaBits.join(' · ') + '</div>' : '';

  // Methods / fields (these are captured by the static scan but were not shown before)
  const methods = Array.isArray(node.methods) ? node.methods.filter(Boolean) : [];
  const fields = Array.isArray(node.fields) ? node.fields.filter(Boolean) : [];
  const methodsHtml = methods.length
    ? '<h3>Methods (' + methods.length + ')</h3><div class="chip-list">' +
      methods.slice(0, 40).map(m => '<span class="chip">' + esc(m) + '()</span>').join('') + '</div>'
    : '';
  const fieldsHtml = fields.length
    ? '<h3>Fields (' + fields.length + ')</h3><div class="chip-list">' +
      fields.slice(0, 40).map(f => '<span class="chip chip-field">' + esc(f) + '</span>').join('') + '</div>'
    : '';

  content.innerHTML = [
    '<h2>' + esc(node.label) + '</h2>',
    '<span class="badge" style="background:' + esc(color) + '">' + esc(node.layer) + '</span>',
    metaHtml,
    '<p class="desc">' + esc(node.description || '') + '</p>',
    fileHtml,
    methodsHtml,
    fieldsHtml,
    node.details ? '<h3>Details</h3><pre class="details-raw">' + esc(node.details.slice(0, 600)) + '</pre>' : '',
    incoming.length ? '<h3>Used by / Incoming (' + incoming.length + ')</h3><ul class="conn-list">' + inHtml + '</ul>' : '',
    outgoing.length ? '<h3>Uses / Outgoing (' + outgoing.length + ')</h3><ul class="conn-list">' + outHtml + '</ul>' : '',
    (!incoming.length && !outgoing.length) ? '<p class="desc" style="color:var(--text-muted)">No links detected for this node. Tip: run AI enrichment (re-open Map → "Enrich with AI") for cross-file business flows.</p>' : '',
  ].join('');
}

function esc(s) {
  // Must escape " as well: this value also lands inside double-quoted attributes (data-file="…"),
  // where an unescaped quote would break out of the attribute.
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

function buildLegend(nodes) {
  const layers = [...new Set(nodes.map(n => n.layer))];
  const legend = document.getElementById('legend');
  legend.innerHTML = layers.map(l => {
    const cfg = RAW_GRAPH.layers.find(x => x.id === l) || { label: l, color: '#555' };
    return '<div class="legend-item"><div class="legend-dot" style="background:' + esc(cfg.color) + '"></div>' + esc(cfg.label) + '</div>';
  }).join('');
}

// ── Zoom controls ────────────────────────────────────────────────────────────
document.getElementById('zoomIn').addEventListener('click', () => {
  d3.select('#graphSvg').transition().call(zoomBehavior.scaleBy, 1.4);
});
document.getElementById('zoomOut').addEventListener('click', () => {
  d3.select('#graphSvg').transition().call(zoomBehavior.scaleBy, 0.7);
});
document.getElementById('zoomFit').addEventListener('click', () => {
  d3.select('#graphSvg').transition().call(zoomBehavior.transform, d3.zoomIdentity);
});

// ── Tabs ─────────────────────────────────────────────────────────────────────
document.getElementById('tabBar').addEventListener('click', e => {
  const tab = e.target.closest('.tab');
  if (!tab) { return; }
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  tab.classList.add('active');
  currentView = tab.dataset.view;
  renderGraph(currentView, searchQuery);
});

// ── Search ───────────────────────────────────────────────────────────────────
let searchTimer;
document.getElementById('searchBox').addEventListener('input', e => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    searchQuery = e.target.value;
    renderGraph(currentView, searchQuery);
  }, 250);
});

// ── Initial render ───────────────────────────────────────────────────────────
renderGraph('all', '');

window.addEventListener('resize', () => renderGraph(currentView, searchQuery));
</script>
</body>
</html>`;
}
