---
description: Whole-repo security audit — sweep entry points for OWASP-style vulns (injection, authz/IDOR, secrets, exposure, AI) grounded in the KB. Read-only.
argument-hint: "[optional: scope/module to focus]"
---

Use the **cwk-security-audit** skill to audit this repository's security: enumerate the attack
surface (entry points via KB `03-entry-points`/`09-auth-security`/`11-api-docs`), then
check each category — input validation, injection, authn/authz & IDOR, secrets/crypto, sensitive-
data exposure, dependencies, AI/LLM — citing file·function·line with severity + concrete fixes.
Save a report + render HTML. Read-only (never edits/exploits; never prints real secret values).
Offer `/cwk-fix-bug` for each CRITICAL/MAJOR.

Scope (optional sub-path/module to focus): $ARGUMENTS
