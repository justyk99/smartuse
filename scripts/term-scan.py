#!/usr/bin/env python3
"""term-scan.py — find company / colleague / internal terms before a public push. 0 network, 0 model tokens.

Scans the working tree (every tracked file) and, with --history, every commit's full patch text (`git log -p --all`).
Patterns: the generic ones below (the same families bash-guard treats as private: credential files, internal hosts,
addresses, ticket keys, personal paths) plus the PRIVATE list in `.smartuse-terms.local` at the repo root, one term per
line (plain substrings, case-insensitive; a line starting with `re:` is a regex). That file is gitignored. Its terms are
NEVER printed: a hit shows as `private#<n>` with the matched text masked.

usage: python3 scripts/term-scan.py [--history] [--repo <path>] [--max-hits N]
exit 1 when any hit was found (so it can gate a push), 0 when clean.
"""
import argparse, os, pathlib, re, subprocess, sys

GENERIC = [
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@(?!users\.noreply\.github\.com|anthropic\.com|example\.(com|org))[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("ipv4", re.compile(r"\b(?!(?:0|127|255)\.)(?:\d{1,3}\.){3}\d{1,3}\b(?![\d.])")),
    ("internal-host", re.compile(r"\b(?!smartuse-terms|settings|smartuse)[a-z0-9-]+\.(local|internal|corp|lan|intranet)\b(?!\.[a-z]{1,5}\b)", re.I)),
    ("private-url", re.compile(r"https?://(?!(?:www\.)?(github\.com|code\.claude\.com|claude\.ai|img\.shields\.io|arxiv\.org|docs\.anthropic\.com|anthropic\.com|x\.y|example\.com|x/|localhost))[A-Za-z0-9.-]+\.[A-Za-z]{2,}", re.I)),
    ("windows-user-path", re.compile(r"(?:/mnt/c/Users/|[A-Z]:\\Users\\)(?!user\b|Public\b)[A-Za-z0-9._-]+", re.I)),
    ("home-user-path", re.compile(r"/home/(?!user\b|u\b|alice\b)[a-z][a-z0-9._-]{1,}/")),
    ("jira-key", re.compile(r"(?<!['\"A-Z0-9-])(?!CVE-|ISO-|RFC-|UTF-|SHA-|MIT-|ID-|PR-|CI-)[A-Z]{3,10}-\d{2,6}\b")),
    ("credential-file", re.compile(r"(db-creds\.json|\.jira_env|/secrets/|recovery-codes|\.git-credentials|\.netrc|gh/hosts\.yml)")),
    ("db-object-prefix", re.compile(r"\b(usp_|t_|bo_|App_Code/|_KNOWLEDGE_BASE|_SESSIONS)[A-Za-z0-9_]*", re.I)),
    ("company-abbrev", re.compile(r"\b(GSG|CMM|Guru|GitLab)\b", re.I)),
    ("author-suffix", re.compile(r"(_YK\b|\byk_[a-z]+|\bbo_yk\b)")),
]
SKIP_DIRS = {".git", "node_modules", "__pycache__"}
SKIP_SELF = {"scripts/term-scan.py", ".smartuse-terms.local"}


def load_private(repo):
    terms = []
    f = repo / ".smartuse-terms.local"
    if not f.is_file():
        return terms
    for i, line in enumerate(f.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            rx = re.compile(line[3:].strip(), re.I) if line.startswith("re:") else re.compile(re.escape(line), re.I)
        except re.error:
            continue
        terms.append((f"private#{i}", rx))
    return terms


def mask(text, m, private):
    s, e = m.start(), m.end()
    hit = "*" * (e - s) if private else text[s:e]
    lo, hi = max(0, s - 30), min(len(text), e + 30)
    return (text[lo:s] + hit + text[e:hi]).replace("\n", " ")


def scan_text(label, text, patterns, hits, max_hits):
    for ln, line in enumerate(text.splitlines(), 1):
        for name, rx in patterns:
            for m in rx.finditer(line):
                if len(hits) >= max_hits:
                    return
                hits.append((label, ln, name, mask(line, m, name.startswith("private#"))))
                break  # one hit per pattern per line


def tracked_files(repo):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True, text=True).stdout
    return [p for p in out.split("\0") if p]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--history", action="store_true", help="also scan git log -p --all")
    ap.add_argument("--max-hits", type=int, default=400)
    a = ap.parse_args()
    repo = pathlib.Path(a.repo).resolve()
    private = load_private(repo)
    patterns = GENERIC + private
    hits = []
    for rel in tracked_files(repo):
        if rel in SKIP_SELF or any(part in SKIP_DIRS for part in rel.split("/")):
            continue
        p = repo / rel
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        scan_text(rel, text, patterns, hits, a.max_hits)
    if a.history:
        log = subprocess.run(["git", "log", "-p", "--all", "--format=commit %h %s"], cwd=repo, capture_output=True, text=True).stdout
        cur = "?"
        for ln, line in enumerate(log.splitlines(), 1):
            if line.startswith("commit "):
                cur = line.split()[1]
                continue
            if line.startswith(("+++ ", "--- ", "index ", "diff --git")):
                continue
            for name, rx in patterns:
                m = rx.search(line)
                if m and len(hits) < a.max_hits:
                    hits.append((f"history@{cur}", ln, name, mask(line, m, name.startswith("private#"))))
                    break
    print(f"term-scan: {len(patterns)} patterns ({len(private)} private) · {'tree + history' if a.history else 'tree'} · {len(hits)} hits")
    by = {}
    for label, ln, name, ex in hits:
        by.setdefault(name, []).append((label, ln, ex))
    for name, rows in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print(f"\n## {name} ({len(rows)})")
        for label, ln, ex in rows[:60]:
            print(f"- {label}:{ln}  …{ex}…")
        if len(rows) > 60:
            print(f"- … {len(rows) - 60} more")
    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
