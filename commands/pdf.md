---
description: Export a Markdown/HTML report to PDF (renders Markdown + Mermaid first); best-effort headless Chrome / wkhtmltopdf
argument-hint: <path to .md or .html (e.g. a cwk-sessions report)>
---

Use the **cwk-pdf** skill to export the file below to PDF: if it's Markdown, render to
self-contained HTML first (Mermaid drawn), then convert HTML→PDF via the bundled
`references/html-to-pdf.sh`, open it, and give the path. If no converter is found (NO_PDF_TOOL),
tell me to open the HTML and Print → Save as PDF. 100% local.

File:
$ARGUMENTS
