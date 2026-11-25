#!/usr/bin/env python3
"""term-scan.py — find company / colleague / internal terms before a public push. 0 network, 0 model tokens.

Scans the working tree (every tracked file) and, with --history, every commit's full patch text (`git log -p --all`).
Patterns: the generic ones below (the same families bash-guard treats as private: credential files, internal hosts,
addresses, ticket keys, personal paths) plus the PRIVATE list in `.smartuse-terms.local` at the repo root, one term per
line (plain substrings, case-insensitive; a line starting with `re:` is a regex). That file is gitignored. Its terms are
NEVER printed: a hit shows as `private#<n>` with the matched text masked.

usage: python3 scripts/term-scan.py [--history] [--repo <path>] [--max-hits N] [--no-private]
exit 1 when any hit was found (so it can gate a push), 2 when the private list is missing or empty (those names were not
checked, so the run cannot call the tree clean; --no-private says a generic-only run is meant, as in CI), 0 when clean.
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


def readings(raw):
    """One line's bytes as the strings to scan, plus whether it was not valid UTF-8.
    Not UTF-8: read as UTF-8 and as cp1252 (a fixed second reading, not the console's code page), undecodable bytes replaced.
    NUL bytes: each reading is also read with them removed (the ASCII letters of UTF-16 text)."""
    try:
        rs, bad = [raw.decode("utf-8")], False
    except UnicodeDecodeError:
        rs, bad = [raw.decode("utf-8", errors="replace"), raw.decode("cp1252", errors="replace")], True
    if b"\0" in raw:
        rs += [r.replace("\0", "") for r in rs]
    return list(dict.fromkeys(rs)), bad


def star(text, private):
    """text with every character inside any private match starred; the same length, so offsets still line up."""
    chars = list(text)
    for _, rx in private:
        for m in rx.finditer(text):
            chars[m.start():m.end()] = "*" * (m.end() - m.start())
    return "".join(chars)


def mask(text, m, private):
    lo, hi = max(0, m.start() - 30), min(len(text), m.end() + 30)
    return star(text, private)[lo:hi].replace("\0", "")  # a line holds no newline, but UTF-16 text may hold NULs


def scan_line(label, ln, rs, patterns, private, hits, max_hits):
    """One hit per pattern per line, private patterns first (so a cap keeps them); every excerpt stars every private match
    on its line, a generic hit's included. A pattern found in the first reading is not counted again in the second."""
    done = set()
    for text in rs:
        for name, rx in patterns:
            if name in done:
                continue
            m = rx.search(text)
            if m:
                if len(hits) >= max_hits:
                    return
                done.add(name)
                hits.append((label, ln, name, mask(text, m, private)))


def scan_bytes(label, raw, patterns, private, hits, max_hits, stats):
    for ln, line in enumerate(raw.splitlines(), 1):
        rs, bad = readings(line)
        stats["bad"] += bad
        scan_line(label, ln, rs, patterns, private, hits, max_hits)
        if len(hits) >= max_hits:
            return


def tracked_files(repo):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True).stdout.decode("utf-8", errors="replace")
    return [p for p in out.split("\0") if p]


def main():
    try:  # typed with no launcher: Windows would print through the ANSI code page and fail on · … or any non-ASCII text
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--history", action="store_true", help="also scan git log -p --all")
    ap.add_argument("--max-hits", type=int, default=400)
    ap.add_argument("--no-private", action="store_true", help="generic patterns only: no private list is expected (CI)")
    a = ap.parse_args()
    repo = pathlib.Path(a.repo).resolve()
    private = load_private(repo)
    patterns = private + GENERIC  # private first: a cap or a line's one-hit rule never hides a private term behind a generic one
    hits = []
    stats = {"bad": 0, "binary": 0}
    for rel in tracked_files(repo):
        if rel in SKIP_SELF or any(part in SKIP_DIRS for part in rel.split("/")):
            continue
        scan_line(rel, 0, [rel], patterns, private, hits, a.max_hits)  # the path itself, label `<path>:0`
        try:
            raw = (repo / rel).read_bytes()
        except Exception:
            continue
        scan_bytes(rel, raw, patterns, private, hits, a.max_hits, stats)
    if a.history:
        # the message is indented 4 spaces (%w), so no message line can pass for a `commit` / `diff` line below
        log = subprocess.run(["git", "-c", "core.quotepath=off", "log", "-p", "--all", "--format=commit %h%n%w(0,4,4)%B"], cwd=repo, capture_output=True).stdout
        cur = "?"
        for ln, line in enumerate(log.splitlines(), 1):
            if line.startswith(b"commit "):
                cur = line.split()[1].decode("ascii", errors="replace")
                continue
            if line.startswith((b"+++ ", b"--- ", b"index ")):
                continue
            if re.match(rb"Binary files .* differ$", line):
                stats["binary"] += 1  # git prints no content for it (a UTF-16 file included); its paths are on the diff --git line above
                continue
            rs, bad = readings(line)
            stats["bad"] += bad
            scan_line(f"history@{cur}", ln, rs, patterns, private, hits, a.max_hits)  # `diff --git` lines carry the paths
    npriv = sum(1 for h in hits if h[2].startswith("private#"))
    extra = (f" · {stats['bad']} lines not UTF-8" if stats["bad"] else "") + (f" · {stats['binary']} binary diffs not read" if stats["binary"] else "")
    print(f"term-scan: {len(patterns)} patterns ({len(private)} private) · {'tree + history' if a.history else 'tree'} · {len(hits)} hits ({npriv} private){extra}")
    by = {}
    for label, ln, name, ex in hits:
        by.setdefault(name, []).append((label, ln, ex))
    for name, rows in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print(f"\n## {name} ({len(rows)})")
        for label, ln, ex in rows[:60]:
            print(f"- {star(label, private)}:{ln}  …{ex}…")
        if len(rows) > 60:
            print(f"- … {len(rows) - 60} more")
    unchecked = not private and not a.no_private
    if unchecked:
        print("\nterm-scan: private names were NOT checked: .smartuse-terms.local is missing or empty. "
              "Put it at the repo root, or pass --no-private for a generic-only run.")
    sys.exit(1 if hits else 2 if unchecked else 0)


if __name__ == "__main__":
    main()
