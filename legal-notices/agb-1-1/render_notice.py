#!/usr/bin/env python3
"""Fill in and check the AGB 1.1 change notice (§ 15 Abs. 2 AGB).

    python3 render_notice.py --check                  # verify the quoted provisions
    python3 render_notice.py --send-date 2026-10-19   # check, then write rendered/*.txt

Standard library only. Run it from anywhere inside the repository.
"""
import argparse
import datetime as dt
import difflib
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
SITE = HERE.parents[1]  # repository root = website root
OUT = HERE / "rendered"

# Last commit that carries version 1.0 of agb.html / terms.html.
V1_0_COMMIT = "acab1b0"
NOTICE_WEEKS = 6  # § 15 Abs. 2 AGB
DELIVERY_LAG_DAYS = 1  # assume the e-mail is received the day after it is sent

NOTICES = {"de": ("notice.de.txt", "agb.html"), "en": ("notice.en.txt", "terms.html")}
TEMPLATES = ["notice.de.txt", "notice.en.txt", "in-app.de.txt", "in-app.en.txt"]
REQUIRED = {"EFFECTIVE_DATE", "OBJECTION_DEADLINE"}

MONTHS = {
    "de": ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
           "September", "Oktober", "November", "Dezember"],
    "en": ["January", "February", "March", "April", "May", "June", "July", "August",
           "September", "October", "November", "December"],
}

BLOCK_TAGS = {"p", "li", "ul", "ol", "dl", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6",
              "div", "section", "article", "header", "footer", "nav", "main", "body", "br",
              "table", "tr", "td", "th", "blockquote", "pre"}


def norm(text):
    return re.sub(r"\s+", " ", text.replace("­", "").replace("\xa0", " ")).strip()


class Paragraphs(HTMLParser):
    """Text of a page, one entry per block element (inline tags such as <a>, <strong> are merged)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.items, self.buf, self.skip = [], [], 0

    def flush(self):
        text = norm("".join(self.buf))
        self.buf = []
        if text:
            self.items.append(text)

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1
        elif tag in BLOCK_TAGS:
            self.flush()

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.skip -= 1
        elif tag in BLOCK_TAGS:
            self.flush()

    def handle_data(self, data):
        if not self.skip:
            self.buf.append(data)


def paragraphs(html_text):
    parser = Paragraphs()
    parser.feed(html_text)
    parser.flush()
    return parser.items


def git_show(path):
    try:
        done = subprocess.run(["git", "show", f"{V1_0_COMMIT}:{path}"], cwd=SITE, check=True,
                              capture_output=True, text=True, encoding="utf-8")
        return done.stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def quotes(text):
    """Yield (kind, paragraph) for each '> ' line under a Bisher/Previously (1.0) or Neu/New (1.1) heading."""
    kind = None
    for line in text.splitlines():
        heading = re.match(r"(?:(Bisher|Previously) \(Version 1\.0\):|(Neu|New) \(Version 1\.1\):)", line)
        if heading:
            kind = "old" if heading.group(1) else "new"
        elif line.startswith("> ") and kind:
            yield kind, norm(line[2:])
        else:
            kind = None


META_LINE = re.compile(r"^(Stand|Letzte Aktualisierung|Effective Date|Last Updated|Version)\b|\bVersion:? ?\d+\.\d+\b")


def is_header_or_footer(paragraph):
    """Date and version lines at the top and bottom of the pages; the notice mentions them in prose."""
    return META_LINE.search(paragraph) is not None


def check_notice(lang):
    name, page = NOTICES[lang]
    problems, warnings = [], []
    text = (HERE / name).read_text(encoding="utf-8")
    new_paras = paragraphs((SITE / page).read_text(encoding="utf-8"))
    old_html = git_show(page)
    old_paras = paragraphs(old_html) if old_html else None
    if old_paras is None:
        warnings.append(f"{name}: {V1_0_COMMIT}:{page} not available (shallow clone?), old wording not verified")

    if not any(re.search(r"\bVersion:? ?1\.1\b", p) for p in new_paras):
        problems.append(f"{page} is no longer version 1.1: update the notice before sending")

    quoted = {"old": set(), "new": set()}
    for kind, paragraph in quotes(text):
        quoted[kind].add(paragraph)
        pool = new_paras if kind == "new" else old_paras
        if pool is not None and paragraph not in pool:
            problems.append(f"{name}: {kind} quote not found in {page}: {paragraph[:70]}...")

    if old_paras is not None:
        matcher = difflib.SequenceMatcher(None, old_paras, new_paras, autojunk=False)
        for tag, i1, i2, j1, j2 in matcher.get_opcodes():
            if tag == "equal":
                continue
            for paragraph in old_paras[i1:i2]:
                if not is_header_or_footer(paragraph) and paragraph not in quoted["old"]:
                    problems.append(f"{name}: changed provision missing (old wording): {paragraph[:70]}...")
            for paragraph in new_paras[j1:j2]:
                if not is_header_or_footer(paragraph) and paragraph not in quoted["new"]:
                    problems.append(f"{name}: changed provision missing (new wording): {paragraph[:70]}...")

    print(f"{name}: {len(quoted['old'])} old and {len(quoted['new'])} new provisions quoted")
    return problems, warnings


def schedule(send):
    receipt = send + dt.timedelta(days=DELIVERY_LAG_DAYS)
    deadline = receipt + dt.timedelta(weeks=NOTICE_WEEKS)
    while deadline.weekday() >= 5:  # § 193 BGB: a weekend deadline moves to Monday
        deadline += dt.timedelta(days=1)
    return receipt, deadline, deadline + dt.timedelta(days=1)


def check_schedule():
    problems = []
    for offset in range(14):
        send = dt.date(2026, 10, 19) + dt.timedelta(days=offset)
        receipt, deadline, effective = schedule(send)
        if (deadline - receipt).days < NOTICE_WEEKS * 7 or deadline.weekday() >= 5 or effective <= deadline:
            problems.append(f"schedule for {send}: receipt {receipt}, deadline {deadline}, effective {effective}")
    return problems


def fmt(day, lang):
    month = MONTHS[lang][day.month - 1]
    return f"{day.day}. {month} {day.year}" if lang == "de" else f"{month} {day.day}, {day.year}"


def render(name, values):
    lang = "de" if ".de." in name else "en"
    text = (HERE / name).read_text(encoding="utf-8")
    used = set(re.findall(r"\{\{([A-Z_]+)\}\}", text))
    unknown = used - set(values)
    if unknown or not REQUIRED <= used:
        sys.exit(f"{name}: unknown placeholders {sorted(unknown)}, missing {sorted(REQUIRED - used)}")
    return re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: fmt(values[m.group(1)], lang), text)


def check():
    problems, warnings = check_schedule(), []
    for lang in NOTICES:
        p, w = check_notice(lang)
        problems += p
        warnings += w
    for line in warnings:
        print("warning:", line)
    for line in problems:
        print("PROBLEM:", line)
    print("check failed" if problems else "check passed")
    return not problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="only verify the notice texts")
    parser.add_argument("--send-date", type=dt.date.fromisoformat, metavar="YYYY-MM-DD",
                        help="day the notice is sent; fills in the dates and writes rendered/")
    parser.add_argument("--allow-past", action="store_true", help="accept a send date before today")
    args = parser.parse_args()
    if not (args.check or args.send_date):
        parser.error("give --check or --send-date")
    if not check():
        sys.exit(1)
    if not args.send_date:
        return

    send = args.send_date
    if send < dt.date.today() and not args.allow_past:
        sys.exit(f"send date {send} is in the past (--allow-past to override)")
    receipt, deadline, effective = schedule(send)
    values = {"SEND_DATE": send, "OBJECTION_DEADLINE": deadline, "EFFECTIVE_DATE": effective}

    OUT.mkdir(exist_ok=True)
    rendered = {name: render(name, values) for name in TEMPLATES}
    for name, text in rendered.items():
        (OUT / name).write_text(text, encoding="utf-8", newline="\n")
    rule = "=" * 60
    combined = (rendered["notice.de.txt"].rstrip() + f"\n\n\n{rule}\nENGLISH VERSION (convenience translation)\n{rule}\n\n"
                + rendered["notice.en.txt"])
    (OUT / "notice.combined.txt").write_text(combined, encoding="utf-8", newline="\n")

    print(f"\nsent:                  {send:%a %Y-%m-%d}")
    print(f"assumed receipt:       {receipt:%a %Y-%m-%d}")
    print(f"objection until:       {deadline:%a %Y-%m-%d}")
    print(f"changes take effect:   {effective:%a %Y-%m-%d}")
    print(f"written to {OUT.relative_to(SITE)}/ ({len(rendered) + 1} files); check public holidays by hand")


if __name__ == "__main__":
    main()
