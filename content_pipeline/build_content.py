#!/usr/bin/env python3
"""
Content pipeline for the "Monde de Demain" app.

Turns the official websites' brochures (and local Bible-course files) into
tiny static "packs" that the app downloads on demand:

    out/
      index.json                 languages list (~1 KB)
      <lang>/catalog.json        brochures + courses (~10-20 KB)
      <lang>/commentaires.json   commentaries list (fetched when the tab opens)
      <lang>/revues.json         magazine issues list (fetched when the tab opens)
      <lang>/m/<id>.json.gz      one commentary
      <lang>/r/<id>.json.gz      one magazine issue (all its articles)
      <lang>/b/<id>.json.gz      one brochure, plain structured text (~20-40 KB)
      <lang>/k/<course>/<n>.json.gz   one course lesson
      <lang>/c/<id>.jpg          tiny cover thumbnail (~5 KB, optional)

A brochure PDF is ~4 MB; the same brochure as a text pack is ~25 KB.
Upload the `out/` folder to any static host (GitHub Pages, Firebase Hosting,
Netlify, your own server...) and point the app at it with
--dart-define=CONTENT_BASE_URL=https://.../

Usage:
    python3 build_content.py                 # all configured languages
    python3 build_content.py --lang fr       # one language
    python3 build_content.py --lang fr --limit 3   # quick test

Only the Python standard library is used. Cover thumbnails use macOS `sips`
when present (otherwise covers are skipped).
"""
import argparse
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from html import unescape
from html.parser import HTMLParser
from urllib.parse import urljoin

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
COURSES_DIR = os.path.join(HERE, "courses")
UA = "Mozilla/5.0 (MondeDeDemainApp content builder)"

# Languages offered in the app. `sections` says which adapter scrapes each
# section (brochures, commentaires, revues) of that language's site;
# languages without adapters still appear in the app and can be filled with
# local course files only (see courses/README.md).
LANGUAGES = [
    {"code": "fr", "name": "French", "native": "Français", "rtl": False,
     "site": "https://www.mondedemain.org", "list": "/brochures",
     "sections": {"brochures": "drupal_booklets", "commentaires": "drupal_commentaires",
                  "revues": "drupal_revues"}},
    {"code": "en", "name": "English", "native": "English", "rtl": False,
     "site": "https://www.tomorrowsworld.org"},
    {"code": "es", "name": "Spanish", "native": "Español", "rtl": False,
     "site": "https://www.elmundodemanana.org"},
    {"code": "de", "name": "German", "native": "Deutsch", "rtl": False,
     "site": "https://www.weltvonmorgen.org"},
    {"code": "nl", "name": "Dutch", "native": "Nederlands", "rtl": False,
     "site": "https://www.wereldvanmorgen.nl"},
    {"code": "pt", "name": "Portuguese", "native": "Português", "rtl": False,
     "site": "https://www.omundodeamanha.org"},
    {"code": "ru", "name": "Russian", "native": "Русский", "rtl": False,
     "site": "https://russian.tomorrowsworld.org"},
    {"code": "ar", "name": "Arabic", "native": "العربية", "rtl": True,
     "site": "https://arabic.tomorrowsworld.org"},
    {"code": "sw", "name": "Swahili", "native": "Kiswahili", "rtl": False,
     "site": "https://swahili.tomorrowsworld.org"},
]


def fetch(url, binary=False, retries=3):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
                return data if binary else data.decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            if attempt == retries - 1:
                raise
            print(f"  retry {url}: {e}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))


CACHE = os.path.join(HERE, ".cache")
REFRESH = False  # --refresh: ignore the page cache


def fetch_cached(url):
    """Item pages (one brochure, one article…) rarely change: keep a local
    copy so re-runs only download what is new. Listings are never cached."""
    key = hashlib.sha1(url.encode()).hexdigest()
    path = os.path.join(CACHE, key + ".html")
    if not REFRESH and os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    html = fetch(url)
    os.makedirs(CACHE, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    time.sleep(0.3)  # be gentle with the website
    return html


def write_gz(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    # mtime=0 so identical content gives identical bytes (stable hashes / ETags).
    data = gzip.compress(raw, compresslevel=9, mtime=0)
    with open(path, "wb") as f:
        f.write(data)
    return len(data), hashlib.sha1(raw).hexdigest()[:10]


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))


# --------------------------------------------------------------------------
# HTML -> compact blocks
#
# A pack body is a list of blocks: [type, text] where type is one of
#   h1 (article title, magazines), by (article author), h2, h3, p,
#   q (quote), li (bullet), ol (numbered item), img (url)
# Inline text keeps only <b> and <i>; everything else is stripped. This is all
# the reader needs and keeps packs very small.
# --------------------------------------------------------------------------
BLOCK_TAGS = {"h1": "h2", "h2": "h2", "h3": "h3", "h4": "h3", "h5": "h3",
              "p": "p", "blockquote": "q", "li": "li", "div": "p"}
INLINE_MAP = {"strong": "b", "b": "b", "em": "i", "i": "i"}


class BodyParser(HTMLParser):
    def __init__(self, base_url):
        super().__init__(convert_charrefs=True)
        self.base = base_url
        self.blocks = []
        self.buf = []
        self.kind = "p"
        self.stack = []      # open block-ish tags
        self.list_stack = []  # "ul" / "ol"
        self.skip = 0         # inside script/style/form

    def _flush(self):
        text = "".join(self.buf)
        text = re.sub(r"\s+", " ", text).strip()
        # drop empty inline tags and tidy spaces next to them
        text = re.sub(r"<([bi])>\s*</\1>", "", text)
        plain = re.sub(r"</?[bi]>", "", text).strip()
        if plain:
            kind = self.kind
            # headings are already bold - drop redundant <b>
            if kind in ("h2", "h3"):
                text = plain
            self.blocks.append([kind, text])
        self.buf = []

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "form", "iframe"):
            self.skip += 1
            return
        if self.skip:
            return
        a = dict(attrs)
        if tag in ("ul", "ol"):
            self._flush()
            self.list_stack.append(tag)
        elif tag in BLOCK_TAGS:
            self._flush()
            if tag == "li":
                self.kind = "ol" if self.list_stack and self.list_stack[-1] == "ol" else "li"
            elif tag == "div" and self.kind == "q":
                pass
            else:
                self.kind = BLOCK_TAGS[tag]
            self.stack.append(tag)
        elif tag in INLINE_MAP:
            self.buf.append(f"<{INLINE_MAP[tag]}>")
        elif tag == "br":
            self.buf.append(" ")
        elif tag == "img" and a.get("src"):
            self._flush()
            self.blocks.append(["img", urljoin(self.base, a["src"])])
        elif tag == "sup":
            self.buf.append("")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "form", "iframe"):
            self.skip = max(0, self.skip - 1)
            return
        if self.skip:
            return
        if tag in ("ul", "ol"):
            self._flush()
            if self.list_stack:
                self.list_stack.pop()
            self.kind = "p"
        elif tag in BLOCK_TAGS:
            self._flush()
            if self.stack:
                self.stack.pop()
            # back inside a blockquote? keep quoting
            self.kind = "q" if "blockquote" in self.stack else "p"
        elif tag in INLINE_MAP:
            self.buf.append(f"</{INLINE_MAP[tag]}>")

    def handle_data(self, data):
        if self.skip:
            return
        # escape stray angle brackets so only our <b>/<i> remain as markup
        self.buf.append(data.replace("<", "‹").replace(">", "›"))

    def close(self):
        super().close()
        self._flush()
        return self.blocks


def extract_div(html, class_marker):
    """Return the inner HTML of the first <div> whose class contains marker."""
    i = html.find(class_marker)
    if i < 0:
        return ""
    start = html.rfind("<div", 0, i)
    depth = 0
    for m in re.finditer(r"<(/?)div\b[^>]*>", html[start:]):
        depth += -1 if m.group(1) else 1
        if depth == 0:
            return html[start:start + m.end()]
    return html[start:]


def html_to_blocks(html, base):
    p = BodyParser(base)
    p.feed(html)
    return p.close()


# --------------------------------------------------------------------------
# Adapter: Drupal "booklets" sites (mondedemain.org)
# --------------------------------------------------------------------------
def scrape_drupal_booklets(lang, limit, out_dir):
    site = lang["site"]
    listing = fetch(site + lang["list"])
    cards = re.findall(
        r'<a href="(/brochures/[^"?#/]+)"><img src="([^"]+)"[^>]*></a>\s*'
        r'<h2><a[^>]*>(.*?)</a></h2>(.*?)class="btn"',
        listing, re.S)
    items = []
    for n, (path, cover, title, rest) in enumerate(cards):
        if limit and n >= limit:
            break
        slug = path.rsplit("/", 1)[1]
        author = re.search(r'class="username">([^<]+)', rest)
        print(f"  [{n + 1}/{len(cards)}] {slug}")
        page = fetch_cached(f"{site}{path}/content")
        body = extract_div(page, 'field field-name-body')
        blocks = html_to_blocks(body, site)
        summary_html = extract_div(page, 'content-summary')
        summary = re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]+>", "", summary_html))).strip()
        pdf = re.search(r'href="([^"]+\.pdf)"', page)
        pack = {
            "id": slug,
            "t": unescape(title).strip(),
            "a": unescape(author.group(1)).strip() if author else "",
            "blocks": blocks,
        }
        size, h = write_gz(os.path.join(out_dir, "b", f"{slug}.json.gz"), pack)
        cover_ok = make_cover(cover, os.path.join(out_dir, "c", f"{slug}.jpg"))
        items.append({
            "id": slug,
            "t": pack["t"],
            "a": pack["a"],
            "s": summary[:220],
            "sz": size,          # pack size in bytes (shown before download)
            "v": h,              # content hash: changes when the text changes
            "c": cover_ok,       # cover thumbnail available?
            "pdf": urljoin(site, pdf.group(1)) if pdf else None,
        })
    return items


def make_cover(url, dest):
    """Download a cover and shrink it to a ~5 KB thumbnail (macOS sips)."""
    if not shutil.which("sips"):
        return False
    try:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + ".src"
        with open(tmp, "wb") as f:
            f.write(fetch(url, binary=True))
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "55",
                        "--resampleWidth", "160", tmp, "--out", dest],
                       check=True, capture_output=True)
        os.remove(tmp)
        return True
    except Exception as e:  # noqa: BLE001
        print(f"  cover failed: {e}", file=sys.stderr)
        return False


def plain(html):
    return re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]+>", "", html or ""))).strip()


def first_paragraph(blocks, n=160):
    for kind, text in blocks:
        if kind == "p":
            t = re.sub(r"</?[bi]>", "", text)
            return t if len(t) <= n else t[: n - 1].rsplit(" ", 1)[0] + "…"
    return ""


MONTHS_FR = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
             "septembre", "octobre", "novembre", "décembre"]


def date_key(display):
    """'5 juillet 2022' -> '2022-07-05' (sort key; '' when unknown)."""
    m = re.match(r"(\d{1,2})\s+(\S+)\s+(\d{4})", display.lower())
    if not m or m.group(2) not in MONTHS_FR:
        return ""
    return f"{m.group(3)}-{MONTHS_FR.index(m.group(2)) + 1:02d}-{int(m.group(1)):02d}"


# --------------------------------------------------------------------------
# Adapter: commentaries (/commentaire, paginated ?page=N, newest first)
# --------------------------------------------------------------------------
def scrape_drupal_commentaires(lang, limit, out_dir):
    site = lang["site"]
    items, page = [], 0
    while True:
        listing = fetch(f"{site}/commentaire?page={page}")
        parts = listing.split('class="blog-t"')[1:]
        if not parts:
            break
        for part in parts:
            # recent ones live under /commentaire/, older ones under /commentaires/
            m = re.search(r'<a href="(/commentaires?/[^"?#]+)">(.*?)</a>', part, re.S)
            if not m:
                continue
            if limit and len(items) >= limit:
                return items
            path, title = m.group(1), plain(m.group(2))
            slug = path.rsplit("/", 1)[1]
            date = re.search(r'date-display-single">([^<]+)<', part)
            author = re.search(r'class="username">([^<]+)<', part)
            print(f"  [commentaire {len(items) + 1}] {slug}")
            html = fetch_cached(site + path)
            blocks = html_to_blocks(extract_div(html, "field field-name-body"), site)
            pack = {"id": slug, "t": title, "a": plain(author.group(1)) if author else "",
                    "blocks": blocks}
            size, h = write_gz(os.path.join(out_dir, "m", f"{slug}.json.gz"), pack)
            display = plain(date.group(1)) if date else ""
            items.append({"id": slug, "t": title, "a": pack["a"],
                          "d": display, "k": date_key(display),
                          "s": first_paragraph(blocks), "sz": size, "v": h})
        page += 1
    # The site does not list commentaries by date: newest first.
    items.sort(key=lambda i: i["k"], reverse=True)
    return items


# --------------------------------------------------------------------------
# Adapter: magazine issues (/revues/<year>/<issue>/<article>). One pack per
# issue holding all its articles; each article starts with an "h1" block.
# --------------------------------------------------------------------------
def scrape_drupal_revues(lang, limit, out_dir):
    site = lang["site"]
    root = fetch(site + "/revues")
    years = sorted({int(y) for y in re.findall(r'href="(?:%s)?/revues/(\d{4})"' % re.escape(site), root)},
                   reverse=True)
    issues = []
    for year in years:
        year_page = fetch(f"{site}/revues/{year}")
        paths = list(dict.fromkeys(re.findall(
            r'href="(?:%s)?(/revues/%d/[^"/?#]+)"' % (re.escape(site), year), year_page)))
        paths.reverse()  # the year page lists issues oldest first
        for path in paths:
            if limit and len(issues) >= limit:
                return issues
            slug = path.rsplit("/", 1)[1]
            iid = f"{year}-{slug}"
            print(f"  [revue {len(issues) + 1}] {iid}")
            html = fetch_cached(site + path)
            heading = re.search(r'class="magazines_year">\s*(.*?)\s*</h3>', html, re.S)
            title = plain(heading.group(1)) if heading else slug.replace("-", " ").title()
            title = re.sub(r"^%d\s+" % year, "", title)
            cover = re.search(r'magazine-view-container">\s*<img src="([^"]+)"', html)
            pdf = re.search(r'href="([^"]+\.pdf)"', html)
            blocks, arts = [], []
            for part in html.split("magazine-view-container text_align_left")[1:]:
                m = re.search(r'<h2>\s*<a href="([^"]+)">(.*?)</a>', part, re.S)
                if not m:
                    continue
                art_url, art_title = urljoin(site, m.group(1)), plain(m.group(2))
                author = re.search(r'class="username">([^<]+)<', part)
                page = fetch_cached(art_url)
                body = html_to_blocks(extract_div(page, "field field-name-body"), site)
                refs = html_to_blocks(extract_div(page, "field-name-field-mag-article-references"), site)
                blocks.append(["h1", art_title])
                if author:
                    blocks.append(["by", plain(author.group(1))])
                blocks += body + refs
                arts.append(art_title)
            if not arts:
                continue
            pack = {"id": iid, "t": f"{title} {year}", "a": "", "blocks": blocks}
            size, h = write_gz(os.path.join(out_dir, "r", f"{iid}.json.gz"), pack)
            cover_ok = bool(cover) and make_cover(cover.group(1), os.path.join(out_dir, "c", f"r-{iid}.jpg"))
            issues.append({"id": iid, "t": title, "y": year, "sz": size, "v": h, "c": cover_ok,
                           "arts": arts, "pdf": urljoin(site, pdf.group(1)) if pdf else None})
    return issues


ADAPTERS = {
    "drupal_booklets": scrape_drupal_booklets,
    "drupal_commentaires": scrape_drupal_commentaires,
    "drupal_revues": scrape_drupal_revues,
}


# --------------------------------------------------------------------------
# Courses from local files: courses/<lang>/<course-id>/
#     course.json   {"t": "Title", "s": "Short description"}
#     01.md, 02.md  one lesson per file; first line "# Lesson title"
# Markdown subset: "## " / "### " headings, "> " quotes, "- " bullets,
# "1. " numbered, **bold**, *italic*, blank line between paragraphs.
# --------------------------------------------------------------------------
def md_inline(s):
    s = s.replace("<", "‹").replace(">", "›")
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\*(.+?)\*", r"<i>\1</i>", s)
    return s


def md_to_blocks(text):
    blocks, para = [], []

    def flush():
        if para:
            blocks.append(["p", md_inline(" ".join(para))])
            para.clear()

    for line in text.splitlines():
        l = line.strip()
        if not l:
            flush()
        elif l.startswith("### "):
            flush(); blocks.append(["h3", l[4:]])
        elif l.startswith("## ") or l.startswith("# "):
            flush(); blocks.append(["h2", l.lstrip("#").strip()])
        elif l.startswith("> "):
            flush(); blocks.append(["q", md_inline(l[2:])])
        elif l.startswith("- ") or l.startswith("* "):
            flush(); blocks.append(["li", md_inline(l[2:])])
        elif re.match(r"^\d+\.\s", l):
            flush(); blocks.append(["ol", md_inline(re.sub(r"^\d+\.\s", "", l))])
        else:
            para.append(l)
    flush()
    return blocks


def build_courses(code, out_dir):
    root = os.path.join(COURSES_DIR, code)
    courses = []
    if not os.path.isdir(root):
        return courses
    for cid in sorted(os.listdir(root)):
        cdir = os.path.join(root, cid)
        meta_path = os.path.join(cdir, "course.json")
        if not os.path.isfile(meta_path):
            continue
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
        lessons = []
        for fn in sorted(x for x in os.listdir(cdir) if x.endswith(".md")):
            with open(os.path.join(cdir, fn), encoding="utf-8") as f:
                text = f.read()
            first = text.strip().splitlines()[0] if text.strip() else fn
            title = first.lstrip("#").strip()
            body = text.strip().split("\n", 1)[1] if "\n" in text.strip() else ""
            lid = os.path.splitext(fn)[0]
            pack = {"id": f"{cid}/{lid}", "t": title, "a": meta.get("a", ""),
                    "blocks": md_to_blocks(body)}
            size, h = write_gz(os.path.join(out_dir, "k", cid, f"{lid}.json.gz"), pack)
            lessons.append({"id": lid, "t": title, "sz": size, "v": h})
        courses.append({"id": cid, "t": meta["t"], "s": meta.get("s", ""), "lessons": lessons})
        print(f"  course {cid}: {len(lessons)} lessons")
    return courses


def main():
    global REFRESH
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", help="only build this language code")
    ap.add_argument("--limit", type=int, default=0, help="max items per section (testing)")
    ap.add_argument("--only", default="brochures,commentaires,revues",
                    help="sections to rebuild (courses are always rebuilt)")
    ap.add_argument("--refresh", action="store_true", help="re-download cached pages")
    args = ap.parse_args()
    REFRESH = args.refresh
    only = set(args.only.split(","))

    index = []
    for lang in LANGUAGES:
        code = lang["code"]
        out_dir = os.path.join(OUT, code)
        catalog_path = os.path.join(out_dir, "catalog.json")
        if not args.lang or args.lang == code:
            print(f"== {code} ({lang['native']})")
            sections = lang.get("sections", {})
            previous = {}
            if os.path.isfile(catalog_path):
                with open(catalog_path, encoding="utf-8") as f:
                    previous = json.load(f)

            brochures = previous.get("brochures", [])
            if "brochures" in only:
                adapter = ADAPTERS.get(sections.get("brochures"))
                brochures = adapter(lang, args.limit, out_dir) if adapter else []
            courses = build_courses(code, out_dir)

            # Big sections live in their own file, fetched by the app only
            # when the reader opens that tab.
            counts = dict(previous.get("sections", {}))
            for name in ("commentaires", "revues"):
                adapter = ADAPTERS.get(sections.get(name))
                if name in only:
                    items = adapter(lang, args.limit, out_dir) if adapter else []
                    write_json(os.path.join(out_dir, f"{name}.json"), {"lang": code, "items": items})
                    counts[name] = len(items)
                    print(f"  {len(items)} {name}, "
                          f"{sum(i['sz'] for i in items) / 1024:.0f} KB of packs")
                counts.setdefault(name, 0)

            write_json(catalog_path, {
                "lang": code,
                "updated": time.strftime("%Y-%m-%d"),
                "brochures": brochures,
                "courses": courses,
                "sections": counts,
            })
            print(f"  {len(brochures)} brochures, {len(courses)} courses, "
                  f"{sum(b['sz'] for b in brochures) / 1024:.0f} KB of brochure packs")
        # a language is listed when its catalog exists (even if empty)
        if os.path.isfile(catalog_path):
            index.append({k: lang[k] for k in ("code", "name", "native", "rtl")})

    write_json(os.path.join(OUT, "index.json"), {"languages": index})
    print(f"Done -> {OUT}")


if __name__ == "__main__":
    main()
