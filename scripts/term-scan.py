#!/usr/bin/env python3
"""term-scan.py — find company / colleague / internal terms before a public push. 0 network, 0 model tokens.

Scans the working tree (every tracked file) and, with --history, every commit's full patch text (`git log -p --all`).
Patterns: the generic ones below (the same families bash-guard treats as private: credential files, internal hosts,
addresses, ticket keys, personal paths) plus the PRIVATE list in `.smartuse-terms.local` at the repo root, one term per
line (plain substrings, case-insensitive; a line starting with `re:` is a regex). That file is gitignored. Its terms are
NEVER printed: a hit shows as `private#<n>` with the matched text masked.

usage: python3 scripts/term-scan.py [--history] [--repo <path>] [--max-hits N] [--no-private]
--max-hits caps the printed generic hits only; private hits are never capped (the summary says `cap reached at N` when it bites).
exit 1 when any hit was found (so it can gate a push), 2 when the private list is missing or empty (those names were not
checked, so the run cannot call the tree clean; --no-private says a generic-only run is meant, as in CI), 0 when clean.
"""
import argparse, codecs, os, pathlib, re, subprocess, sys

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


def _u8_one_per_byte(e):  # an undecodable run becomes one U+FFFD per byte, so every character is one byte or one valid sequence
    return "\ufffd" * (e.end - e.start), e.end


_INVALID = []


def _u8_record(e):
    _INVALID.append((e.start, e.end))
    return _u8_one_per_byte(e)


codecs.register_error("termscan-u8", _u8_one_per_byte)
codecs.register_error("termscan-u8-record", _u8_record)


class Reading:
    """One way to read a line: its text, and (computed only when a private match needs it) the bytes each character came from."""
    __slots__ = ("text", "raw", "kind", "parent")

    def __init__(self, text, raw, kind, parent=None):
        self.text, self.raw, self.kind, self.parent = text, raw, kind, parent

    def bounds(self):
        """[(first byte, end byte)] per character of text, as offsets into the line's bytes."""
        if self.parent is not None:  # the NUL-stripped copy of another reading
            return [b for ch, b in zip(self.parent.text, self.parent.bounds()) if ch != "\0"]
        if self.kind == "id" or self.kind == "cp" or self.raw.isascii():
            return [(i, i + 1) for i in range(len(self.text))]
        if self.kind == "u8":  # valid UTF-8: a character is as long as its encoding
            out, b = [], 0
            for ch in self.text:
                n = len(ch.encode("utf-8"))
                out.append((b, b + n))
                b += n
            return out
        _INVALID.clear()  # "u8bad": UTF-8 with undecodable bytes replaced, one character per bad byte
        self.raw.decode("utf-8", "termscan-u8-record")
        inv, out, b, k = list(_INVALID), [], 0, 0
        for ch in self.text:
            if k < len(inv) and b == inv[k][0]:
                out.append((b, b + 1))
                b += 1
                if b == inv[k][1]:
                    k += 1
            else:
                n = len(ch.encode("utf-8"))
                out.append((b, b + n))
                b += n
        return out


def readings(raw):
    """One line's bytes as the Readings to scan, plus whether it was not valid UTF-8.
    Not UTF-8: read as UTF-8 and as cp1252 (a fixed second reading, not the console's code page), undecodable bytes replaced.
    NUL bytes: each reading is also read with them removed (the ASCII letters of UTF-16 text)."""
    try:
        base, bad = [Reading(raw.decode("utf-8"), raw, "u8")], False
    except UnicodeDecodeError:
        base, bad = [Reading(raw.decode("utf-8", "termscan-u8"), raw, "u8bad"), Reading(raw.decode("cp1252", errors="replace"), raw, "cp")], True
    rs = list(base)
    if b"\0" in raw:
        rs += [Reading(r.text.replace("\0", ""), raw, r.kind, parent=r) for r in base]
    seen, out = set(), []
    for r in rs:
        if r.text not in seen:
            seen.add(r.text)
            out.append(r)
    return out, bad


def star(text, private):
    """text with every character inside any private match starred; the same length, so offsets still line up."""
    chars = list(text)
    for _, rx in private:
        for m in rx.finditer(text):
            chars[m.start():m.end()] = "*" * (m.end() - m.start())
    return "".join(chars)


def private_bytes(rs, private):
    """The byte offsets of the line that lie inside a private match in ANY reading (UTF-8, cp1252, NUL-stripped)."""
    hit = set()
    for r in rs:
        bs = None
        for _, rx in private:
            for m in rx.finditer(r.text):
                bs = bs or r.bounds()
                for i in range(m.start(), m.end()):
                    hit.update(range(*bs[i]))
    return hit


def mask(r, m, hit):
    """The 30 characters each side of match m in reading r, NULs removed, every character that came from a private byte starred."""
    lo, hi = max(0, m.start() - 30), min(len(r.text), m.end() + 30)
    if not hit:
        return r.text[lo:hi].replace("\0", "")
    bs = r.bounds()
    return "".join("*" if any(x in hit for x in range(*bs[i])) else r.text[i] for i in range(lo, hi)).replace("\0", "")


class Hits:
    """The hits found. Private hits are never capped; --max-hits caps the generic ones, and `capped` says it was reached."""
    def __init__(self, max_hits):
        self.rows, self.max, self.ngen = [], max_hits, 0

    @property
    def capped(self):
        return self.ngen >= self.max


def scan_line(label, ln, rs, patterns, private, acc):
    """One hit per pattern per line, private patterns first. Every excerpt stars every private match of every reading of its
    line, a generic hit's included. A pattern found in the first reading is not counted again in the second.
    A generic pattern is not tried once the cap is reached; a private one always is."""
    done, hit = set(), None
    for r in rs:
        for name, rx in patterns:
            gen = not name.startswith("private#")
            if name in done or (gen and acc.capped):
                continue
            m = rx.search(r.text)
            if m:
                done.add(name)
                acc.ngen += gen
                if hit is None:
                    hit = private_bytes(rs, private)
                acc.rows.append((label, ln, name, mask(r, m, hit)))


def scan_bytes(label, raw, patterns, private, acc, stats):
    count_bad = b"\0" not in raw[:8192]  # a file with a NUL in its first 8 KB is binary: its lines are read, not counted as not-UTF-8
    for ln, line in enumerate(raw.splitlines(), 1):
        rs, bad = readings(line)
        stats["bad"] += bad and count_bad
        scan_line(label, ln, rs, patterns, private, acc)


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
    ap.add_argument("--history", action="store_true", help="also scan git log -p --text --all")
    ap.add_argument("--max-hits", type=int, default=400, help="cap on generic hits; private hits are never capped")
    ap.add_argument("--no-private", action="store_true", help="generic patterns only: no private list is expected (CI)")
    a = ap.parse_args()
    repo = pathlib.Path(a.repo).resolve()
    private = load_private(repo)
    patterns = private + GENERIC  # private first: a line's one-hit rule never hides a private term behind a generic one; the cap never touches private hits
    hits = Hits(a.max_hits)
    stats = {"bad": 0, "binary": 0}
    for rel in tracked_files(repo):
        if rel in SKIP_SELF or any(part in SKIP_DIRS for part in rel.split("/")):
            continue
        scan_line(rel, 0, [Reading(rel, None, "id")], patterns, private, hits)  # the path itself, label `<path>:0`
        try:
            raw = (repo / rel).read_bytes()
        except Exception:
            continue
        scan_bytes(rel, raw, patterns, private, hits, stats)
    if a.history:
        # --text: a blob git calls binary (a UTF-16 file) is read too; its lines carry the +/-/space prefix, so none can pass for a `commit` line.
        # The author / committer name and e-mail lines come first (`ident ` prefix, private patterns only: a generic pattern would flag every
        # commit's own address); the message is indented 4 spaces (%w), so no message line can pass for a `commit` / `diff` line either.
        fmt = "commit %h%nident %an%nident %ae%nident %cn%nident %ce%n%w(0,4,4)%B"
        log = subprocess.run(["git", "-c", "core.quotepath=off", "log", "-p", "--text", "--all", f"--format={fmt}"], cwd=repo, capture_output=True).stdout
        cur, sec, hdr = "?", None, False  # hdr: inside a diff header (after `diff --git`, before the first `@@`), where ---/+++/index are header lines; sec: [not-UTF-8 lines, a NUL seen, bytes seen] of the diff being read
        def flush():
            if sec and not sec[1]:  # a diff whose first 8 KB holds a NUL is binary: read, not counted as not-UTF-8
                stats["bad"] += sec[0]
        for ln, line in enumerate(log.splitlines(), 1):
            if line.startswith(b"commit "):
                flush()
                cur, sec, hdr = line.split()[1].decode("ascii", errors="replace"), None, False
                continue
            if line.startswith(b"ident "):
                rs, _ = readings(line[6:])
                scan_line(f"history@{cur}", ln, rs, private, private, hits)
                continue
            if line.startswith(b"diff --git "):
                flush()
                sec, hdr = [0, False, 0], True
            elif line.startswith(b"@@"):
                hdr = False
            elif sec and sec[2] < 8192:
                sec[1] = sec[1] or b"\0" in line
                sec[2] += len(line) + 1
            if hdr and line.startswith((b"+++ ", b"--- ", b"index ")):  # in a hunk a line is `+`/`-`/space + text, so `--- x` is a removed `-- x`
                continue
            if re.match(rb"Binary files .* differ$", line):
                stats["binary"] += 1  # git prints no content for it; its paths are on the diff --git line above
                continue
            rs, bad = readings(line)
            if sec:
                sec[0] += bad
            else:
                stats["bad"] += bad
            scan_line(f"history@{cur}", ln, rs, patterns, private, hits)  # `diff --git` lines carry the paths
        flush()
    rows = hits.rows
    npriv = sum(1 for h in rows if h[2].startswith("private#"))
    extra = (f" · {stats['bad']} lines not UTF-8" if stats["bad"] else "") + (f" · {stats['binary']} binary diffs not read" if stats["binary"] else "") + (f" · cap reached at {a.max_hits}" if hits.capped else "")
    print(f"term-scan: {len(patterns)} patterns ({len(private)} private) · {'tree + history' if a.history else 'tree'} · {len(rows)} hits ({npriv} private){extra}")
    by = {}
    for label, ln, name, ex in rows:
        by.setdefault(name, []).append((label, ln, ex))
    for name, rws in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print(f"\n## {name} ({len(rws)})")
        for label, ln, ex in rws[:60]:
            print(f"- {star(label, private)}:{ln}  …{ex}…")
        if len(rws) > 60:
            print(f"- … {len(rws) - 60} more")
    unchecked = not private and not a.no_private
    if unchecked:
        print("\nterm-scan: private names were NOT checked: .smartuse-terms.local is missing or empty. "
              "Put it at the repo root, or pass --no-private for a generic-only run.")
    sys.exit(1 if rows else 2 if unchecked else 0)


if __name__ == "__main__":
    main()
