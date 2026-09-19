#!/usr/bin/env node
// Entry point kept in scripts/ beside the other KB tools. The canonical file lives in resources/
// so that scripts/sync-bundles.sh can bundle it into the skills that draw diagrams.
require('../resources/check-mermaid.cjs');
