#!/usr/bin/env python3
"""Convert a tracker markdown file to Notion-flavored Markdown.

Notion's markdown variant does not accept GitHub pipe tables — tables must be
emitted as <table> XML with header-row set. Everything else in progress.md and
backlog.md (headings, bullets, bold, inline code, links, dividers) passes
through unchanged.

Used by the `sync-notion` skill. Read-only mirror: git is the source of truth,
so this only ever converts repo -> Notion, never the reverse.

Usage:
    python3 scripts/md_to_notion.py docs/progress.md
    python3 scripts/md_to_notion.py docs/progress.md --header "Synced from ..."
"""

import argparse
import re
import sys
from pathlib import Path

# Parks source-escaped pipes mid-conversion; cannot occur in the trackers.
SENTINEL = "\x00"

# Characters Notion-flavored Markdown treats as markup and that must be escaped
# inside table cells. Deliberately excludes * ` [ ] which we want to keep live so
# that **bold**, `code` and [links](...) still render inside cells. Notion
# additionally auto-escapes ~ and [ ] on ingest, which is harmless.
CELL_ESCAPE = str.maketrans({"|": r"\|", "<": r"\<", ">": r"\>"})

# Notion reads " + " immediately after an inline-code span as list markup and
# renders it as a bullet, silently corrupting notes like "`model.safetensors` +
# config". Escaping the plus keeps it literal. Observed on ingest 2026-07-26.
PLUS_AFTER_CODE = re.compile(r"(`)(\s+)\+(\s+)")

# Repo-relative links are dead in Notion. Every mirrored doc points at its Notion
# page; anything unmirrored (notes/ files) degrades to plain text naming the file
# rather than a link that goes nowhere.
NOTION_PAGES = {
    "backlog.md": "https://app.notion.com/p/3a9c657667018119a2a5ee863bde5d45",
    "progress.md": "https://app.notion.com/p/3a9c657667018121a797dda10eec5ce9",
    "so101-embodied-ai-project-plan.md":
        "https://app.notion.com/p/3a9c65766701817e8f7ce4fe39822021",
    "physical-ai-learning-roadmap.md":
        "https://app.notion.com/p/3a9c65766701817283b2e9de9b6ffebf",
}

MD_LINK = re.compile(r"\[([^\]]+)\]\((?!https?:)([A-Za-z0-9._/-]+\.md)(#[^)]*)?\)")


def rewrite_links(text):
    """Point repo-relative .md links at Notion, or flatten them to plain text."""

    def repl(m):
        label, target, _anchor = m.group(1), m.group(2), m.group(3)
        base = target.rsplit("/", 1)[-1]
        url = NOTION_PAGES.get(base)
        if url:
            # Anchors are dropped: Notion heading anchors do not match the source
            # file's slugs, so a fragment would land in the wrong place or nowhere.
            return f"[{label}]({url})"
        # Unmirrored file (a notes/ entry): keep the path visible, since a bare
        # label like "notes" gives no way to find the file back in the repo.
        return f"{label} (`{target}`)" if label.lower() in {"notes", "note"} else label

    return MD_LINK.sub(repl, text)


def split_row(line):
    """Split a pipe-table row into cells, honouring \\| escapes."""
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|") and not body.endswith(r"\|"):
        body = body[:-1]
    # split on unescaped pipes only
    cells = re.split(r"(?<!\\)\|", body)
    return [c.strip() for c in cells]


def is_separator(line):
    """True for a |---|---| table separator row."""
    stripped = line.strip()
    if not stripped.startswith("|"):
        return False
    return bool(re.fullmatch(r"[|\s:-]+", stripped)) and "-" in stripped


def cell_to_notion(cell):
    """Escape a single cell's contents for Notion-flavored Markdown.

    Cells already carrying a source-escaped pipe keep that escape; bare < and >
    are escaped so Notion does not read them as tag delimiters.
    """
    # Park source-escaped pipes on a NUL sentinel that cannot occur in the
    # trackers, so the translate step below cannot double-escape them.
    cell = cell.replace(r"\|", SENTINEL)
    cell = cell.translate(CELL_ESCAPE)
    cell = cell.replace(SENTINEL, r"\|")
    return PLUS_AFTER_CODE.sub(r"\1\2\\+\3", cell)


def emit_table(rows, has_header):
    """Render collected pipe-table rows as a Notion <table> block."""
    out = [f'<table fit-page-width="true" header-row="{str(has_header).lower()}">']
    for row in rows:
        out.append("\t<tr>")
        for cell in row:
            out.append(f"\t\t<td>{cell_to_notion(cell)}</td>")
        out.append("\t</tr>")
    out.append("</table>")
    return out


def convert(text):
    """Convert markdown text to Notion-flavored Markdown."""
    lines = text.splitlines()
    out = []
    in_fence = False
    table = []          # collected rows of the table currently being parsed
    table_has_header = False

    def flush_table():
        nonlocal table, table_has_header
        if table:
            # Drop rows that are entirely empty (the tracker uses these as
            # placeholders in the empty-backlog table); keep the table itself so
            # the structure is still visible.
            rows = [r for r in table if any(c for c in r)]
            if rows:
                out.extend(emit_table(rows, table_has_header))
            table = []
            table_has_header = False

    for line in lines:
        stripped = line.strip()

        # Fenced code blocks pass through verbatim, tables inside them are not tables.
        if stripped.startswith("```"):
            flush_table()
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue

        if is_separator(line):
            # The row already collected before a separator is the header row.
            if table:
                table_has_header = True
            continue

        if stripped.startswith("|"):
            table.append(split_row(line))
            continue

        flush_table()
        out.append(line)

    flush_table()
    # Link rewriting runs last so it catches prose and table cells alike. Code
    # fences are exempt: a path inside a command is not a link.
    result = []
    in_fence = False
    for line in "\n".join(out).splitlines():
        if line.strip().startswith("```"):
            in_fence = not in_fence
            result.append(line)
            continue
        result.append(line if in_fence else rewrite_links(line))
    return "\n".join(result).strip() + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", type=Path, help="markdown file to convert")
    ap.add_argument("--header", default=None,
                    help="callout text prepended to the page (sync provenance)")
    args = ap.parse_args()

    if not args.path.is_file():
        sys.exit(f"not a file: {args.path}")

    body = convert(args.path.read_text(encoding="utf-8"))

    if args.header:
        banner = (
            '<callout icon="🔒" color="gray_bg">\n'
            f"\t{args.header}\n"
            "</callout>\n\n"
        )
        body = banner + body

    sys.stdout.write(body)


if __name__ == "__main__":
    main()
