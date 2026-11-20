#!/usr/bin/env python3
"""Builds a made-up home folder for Scout's screenshots: /Users/Shared/marta.

Run Scout with SCOUT_DEMO_HOME=/Users/Shared/marta and it treats this folder as your home and
keeps its own files in <home>/Library/Application Support/Scout, so nothing of yours shows:
not your sidebar, downloads, projects, coding-agent logs or Clean Up results.

What's inside:
- Northwind Studio (marketing/demo-folder) with fields, folder links and a workspace
- Downloads to triage, with "where from" sites, and a File History that taught Scout where they go
- Clean Up and Disk Map material: caches, installers, an old node_modules, a big video, a screen
  recording. Big files are APFS clones of one ~600 MB file, so the whole home uses under 1 GB.
- Coding-agent projects with Claude Code and Codex session logs and MCP servers
- Settings for the demo app (com.jackpawlik.scout.demo): Developer tools on, two saved layouts

Usage: python3 -I marketing/screenshots/setup-home.py   (an existing demo home goes to the Trash)
"""
import json, os, plistlib, random, shutil, subprocess, sys, time, uuid
from datetime import datetime, timedelta, timezone

HOME = "/Users/Shared/marta"
BUNDLE = "com.jackpawlik.scout.demo"
HERE = os.path.dirname(os.path.abspath(__file__))
MARKETING = os.path.dirname(HERE)
NOW = time.time()
random.seed(11)


def run(*args, **kw):
    subprocess.run(args, check=True, **kw)


def p(*parts):
    return os.path.join(HOME, *parts)


def write(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def age(path, days):
    t = NOW - days * 86400
    os.utime(path, (t, t))


def added(path, days):
    """Sets the date a file was added to its folder (what Downloads, Triage and Clean Up go by)."""
    import ctypes, struct
    libc = ctypes.CDLL(None, use_errno=True)
    # struct attrlist: bitmapcount=5, reserved, common, vol, dir, file, fork; ATTR_CMN_ADDEDTIME
    attrs = struct.pack("HHIIIII", 5, 0, 0x10000000, 0, 0, 0, 0)
    t = NOW - days * 86400
    buf = struct.pack("qq", int(t), int((t % 1) * 1e9))
    if libc.setattrlist(path.encode(), attrs, buf, len(buf), 0) != 0:
        raise OSError(ctypes.get_errno(), "setattrlist", path)


def where_from(path, *urls):
    data = plistlib.dumps(list(urls), fmt=plistlib.FMT_BINARY).hex()
    run("xattr", "-wx", "com.apple.metadata:kMDItemWhereFroms", data, path)


BLOB = None


def big(path, extra_mb=0, days=None):
    """A large file that costs no disk: an APFS clone of the blob, plus a little unique data."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    run("cp", "-c", BLOB, path)
    with open(path, "ab") as f:
        f.write(os.urandom(4096 + extra_mb * 1024 * 1024))
    if days is not None:
        age(path, days)


def iso(days_ago, hour=None):
    d = datetime.now(timezone.utc) - timedelta(days=days_ago)
    if hour is not None:
        d = d.replace(hour=hour, minute=random.randint(0, 59))
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------- fresh home
if os.path.exists(HOME):
    os.rename(HOME, os.path.expanduser(f"~/.Trash/marta (old demo home) {int(NOW)}"))
for d in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Code", "Library"]:
    os.makedirs(p(d))

NW = p("Northwind Studio")
run("zsh", os.path.join(MARKETING, "demo-folder/build.sh"), env={**os.environ, "NORTHWIND_DEST": NW})

# The blob behind every big file (random, so APFS can't make it smaller).
BLOB = p("Library/Caches/.blob")
os.makedirs(os.path.dirname(BLOB), exist_ok=True)
with open(BLOB, "wb") as f:
    for _ in range(24):
        f.write(os.urandom(25 * 1024 * 1024))   # 600 MB

# ---------------------------------------------------------------- Downloads to triage
dl = p("Downloads")
downloads = [
    # name, copied from, minutes ago, where from
    ("Invoice 1044 - Acme Coffee.pdf", "Finance/Invoices/Invoice 1043 - Lumen Health.pdf", 12, "https://billing.acmecoffee.com/invoices/1044"),
    ("harbor-pine-moodboard.pdf", "Clients/Harbor & Pine/Proposal - Harbor & Pine.pdf", 48, "https://www.figma.com/file/harbor-moodboard"),
    ("Product Shoot - selects.zip", None, 95, "https://www.dropbox.com/s/selects"),
    ("Screenshot 2026-11-19 at 9.41.12 AM.png", None, 140, None),
    ("Lisbon offsite - itinerary.pdf", "Research/Packaging Trends 2026.pdf", 26 * 60, "https://mail.google.com/mail/u/0"),
    ("Survey export.csv", "Research/Competitors.csv", 30 * 60, "https://forms.studio-research.com/export"),
]
photos = sorted(os.listdir(os.path.join(NW, "Photos/Product Shoot")))
for name, src, minutes, url in downloads:
    dest = os.path.join(dl, name)
    if name.endswith(".zip"):
        run("zip", "-qj", dest, *[os.path.join(NW, "Photos/Product Shoot", n) for n in photos[:3]])
    elif name.endswith(".png"):
        shutil.copy(os.path.join(NW, "Photos/Product Shoot", photos[0]), dest)
    else:
        shutil.copy(os.path.join(NW, src), dest)
    if url:
        where_from(dest, url)
    t = NOW - minutes * 60
    os.utime(dest, (t, t))
    added(dest, minutes / 1440)

# Installers (Clean Up offers these once the app is installed).
big(os.path.join(dl, "Figma-126.2.dmg"), days=20)
big(os.path.join(dl, "Blender-4.3-arm64.dmg"), extra_mb=20, days=34)
big(os.path.join(dl, "FontInstaller.pkg"), days=50)
for name, days in [("Figma-126.2.dmg", 19.62), ("Blender-4.3-arm64.dmg", 33.31), ("FontInstaller.pkg", 49.78)]:
    added(os.path.join(dl, name), days)
# An old download nobody opened again (Clean Up: "Old downloads").
shutil.copy(os.path.join(NW, "Research/Packaging Trends 2026.pdf"), os.path.join(dl, "conference-badge-2026.pdf"))
age(os.path.join(dl, "conference-badge-2026.pdf"), 140)
added(os.path.join(dl, "conference-badge-2026.pdf"), 139.55)

# ---------------------------------------------------------------- Clean Up and Disk Map material
big(p("Library/Developer/Xcode/DerivedData/northwind-app-abcd/Build/Intermediates.noindex/data.bin"), days=4)
big(p("Library/Developer/Xcode/DerivedData/BrandKit-efgh/Build/Products/data.bin"), days=9)
big(p("Library/Caches/Homebrew/downloads/ffmpeg--7.1.bottle.tar.gz"), days=12)
big(p("Library/Caches/Yarn/v6/npm-cache.bin"), days=15)
big(p("Library/Caches/pip/http/cache.bin"), days=40)
big(p("Library/Containers/com.example.OldNotes/Data/Library/notes.db"), days=200)
big(p("Movies/Spring Collection - raw footage.mov"), extra_mb=120, days=25)
big(p("Desktop/Screen Recording 2026-09-02 at 10.14.33.mov"), days=78)
big(p("Code/brand-tokens/node_modules/.cache/build.bin"), days=230)
write(p("Code/brand-tokens/package.json"), '{ "name": "brand-tokens", "version": "0.3.0" }\n')
for path in ["Code/brand-tokens/package.json", "Code/brand-tokens/node_modules", "Code/brand-tokens"]:
    age(p(path), 230)
# Real duplicates (over 1 MB; Scout ignores clones, which share their data).
for name, mb, copy in [("Documents/Contract scan.pdf", 3, "Desktop/Contract scan copy.pdf"),
                       ("Pictures/Lisbon offsite.heic", 2, "Desktop/IMG_4821.heic")]:
    with open(p(name), "wb") as f:
        f.write(os.urandom(mb * 1024 * 1024 + random.randint(1, 90000)))
    age(p(name), 60)
    shutil.copyfile(p(name), p(copy))
    age(p(copy), 21)

# ---------------------------------------------------------------- Coding-agent projects
code = {
    "northwind-site": os.path.join(NW, "Projects/northwind-site"),
    "harbor-app": p("Code/harbor-app"),
    "lumen-dashboard": p("Code/lumen-dashboard"),
    "brand-tokens": p("Code/brand-tokens"),
}
write(os.path.join(code["northwind-site"], "CLAUDE.md"), "# northwind-site\n\nThe studio website. Run `npm run dev`.\n")
write(os.path.join(code["northwind-site"], ".mcp.json"), json.dumps({"mcpServers": {"figma": {}, "linear": {}}}))
write(os.path.join(code["harbor-app"], "AGENTS.md"), "# harbor-app\n\nHarbor & Pine's ordering app.\n")
write(os.path.join(code["harbor-app"], "README.md"), "# harbor-app\n")
write(os.path.join(code["lumen-dashboard"], "CLAUDE.md"), "# lumen-dashboard\n")
os.makedirs(os.path.join(code["lumen-dashboard"], ".cursor"))
write(os.path.join(code["brand-tokens"], "GEMINI.md"), "# brand-tokens\n")


def claude_session(cwd, days_ago, replies):
    folder = p(".claude/projects", cwd.replace("/", "-").replace(" ", "-").replace("&", "-"))
    path = os.path.join(folder, f"{uuid.uuid4()}.jsonl")
    lines = [json.dumps({"type": "user", "cwd": cwd, "message": {"role": "user", "content": "…"}})]
    for _ in range(replies):
        lines.append(json.dumps({"type": "assistant", "cwd": cwd, "message": {
            "id": f"msg_{uuid.uuid4().hex[:20]}", "role": "assistant", "usage": {
                "input_tokens": random.randint(800, 4000), "output_tokens": random.randint(400, 2500),
                "cache_read_input_tokens": random.randint(15000, 60000),
                "cache_creation_input_tokens": random.randint(1000, 8000)}}}))
    write(path, "\n".join(lines) + "\n")
    age(path, days_ago)


def codex_session(cwd, days_ago, total):
    d = datetime.now() - timedelta(days=days_ago)
    path = p(".codex/sessions", d.strftime("%Y/%m/%d"), f"rollout-{uuid.uuid4()}.jsonl")
    lines = [json.dumps({"type": "session_meta", "payload": {"cwd": cwd}}),
             json.dumps({"type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {
                 "input_tokens": total, "cached_input_tokens": int(total * 0.7), "output_tokens": total // 9}}}})]
    write(path, "\n".join(lines) + "\n")
    age(path, days_ago)


for days in (0.02, 1, 3, 6):
    claude_session(code["northwind-site"], days, 18)
for days in (0.3, 2):
    codex_session(code["harbor-app"], days, 640_000)
claude_session(code["harbor-app"], 4, 9)
claude_session(code["lumen-dashboard"], 1.5, 12)
claude_session(code["lumen-dashboard"], 8, 10)
claude_session(code["brand-tokens"], 21, 5)
write(p(".claude.json"), json.dumps({
    "mcpServers": {"github": {}},
    "projects": {code["lumen-dashboard"]: {"mcpServers": {"postgres": {}}}},
}))

# ---------------------------------------------------------------- Scout's own files
store = p("Library/Application Support/Scout")
os.makedirs(store, exist_ok=True)


def save(name, value):
    with open(os.path.join(store, name), "w") as f:
        json.dump(value, f, indent=2)


CL = os.path.join(NW, "Clients")
status, client, due, amount = (str(uuid.uuid4()).upper() for _ in range(4))
fields = [
    {"id": status, "name": "Status", "kind": "choice", "choices": ["To do", "In progress", "Review", "Done"]},
    {"id": client, "name": "Client", "kind": "text", "choices": []},
    {"id": due, "name": "Due", "kind": "date", "choices": []},
]
today = datetime.now()
def day(n): return (today + timedelta(days=n)).strftime("%Y-%m-%d")
styles = {
    os.path.join(CL, "Acme Coffee"): {"color": "orange", "fields": {status: "In progress", client: "Acme Coffee", due: day(9)},
        "links": [{"title": "Brief", "url": "https://www.notion.so/northwind/acme-brief"},
                  {"title": "Packaging concepts", "url": "https://www.figma.com/file/acme-packaging"}]},
    os.path.join(CL, "Harbor & Pine"): {"color": "blue", "fields": {status: "Review", client: "Harbor & Pine", due: day(3)},
        "links": [{"title": "Brief", "url": "https://www.notion.so/northwind/harbor-brief"},
                  {"title": "Moodboard", "url": "https://www.figma.com/file/harbor-moodboard"},
                  {"title": "harbor-app", "url": "https://github.com/northwind/harbor-app"}]},
    os.path.join(CL, "Lumen Health"): {"color": "green", "fields": {status: "Done", client: "Lumen Health", due: day(-6)}},
    os.path.join(CL, "Acme Coffee/Packaging Concepts.pdf"): {"fields": {status: "Review", client: "Acme Coffee", due: day(5)}},
    os.path.join(CL, "Acme Coffee/Brief - Acme Coffee.docx"): {"fields": {status: "Done", client: "Acme Coffee"}},
    os.path.join(CL, "Harbor & Pine/Proposal - Harbor & Pine.pdf"): {"fields": {status: "Review", client: "Harbor & Pine", due: day(3)}},
    os.path.join(CL, "Harbor & Pine/Meeting Notes - Kickoff.docx"): {"fields": {status: "Done", client: "Harbor & Pine"}},
    os.path.join(CL, "Lumen Health/Website Sitemap.pdf"): {"fields": {status: "Done", client: "Lumen Health"}},
    os.path.join(NW, "Launch Plan.docx"): {"fields": {status: "In progress", due: day(12)}},
    os.path.join(NW, "Pitch Deck.pdf"): {"fields": {status: "To do", due: day(16)}},
    os.path.join(NW, "Projects/northwind-site"): {"fields": {status: "In progress"},
        "links": [{"title": "northwind-site", "url": "https://github.com/northwind/northwind-site"}]},
    os.path.join(NW, "Finance/Invoices"): {"color": "green"},
    os.path.join(NW, "Photos"): {"color": "pink"},
}
save("customizations.json", {"styles": styles, "pinned": {}, "fieldDefinitions": fields})

save("workspaces.json", [{"id": str(uuid.uuid4()).upper(), "name": "Spring Launch", "symbol": "sparkles", "paths": [
    os.path.join(NW, "Photos/Product Shoot"), os.path.join(NW, "Launch Plan.docx"), code["northwind-site"],
    os.path.join(NW, "Brand")]}])

# Folder visits, for the sidebar's Frequent list and ⌘K ranking.
visits = {
    NW: 40, CL: 26, os.path.join(CL, "Harbor & Pine"): 18, os.path.join(NW, "Finance/Invoices"): 14,
    os.path.join(NW, "Photos/Product Shoot"): 10, code["northwind-site"]: 9, p("Code/harbor-app"): 6,
    os.path.join(NW, "Research"): 4, dl: 22,
}
# Folders get a date that matches what's inside (the newest file), like a real disk.
for root, dirs, files in sorted(os.walk(NW), key=lambda w: -w[0].count("/")):
    if "/.git" in root:
        continue
    times = [os.path.getmtime(os.path.join(root, n)) for n in files + dirs if n != ".git"]
    if times:
        os.utime(root, (max(times), max(times)))
    for n in files + dirs:
        if n != ".git":
            f = os.path.join(root, n)
            added(f, (NOW - os.path.getmtime(f)) / 86400)

# The last visit is now, so files made by this script don't get the "new since your last visit"
# dot. Downloads keeps its dots: those files really are new.
history = {path: sorted(iso(random.uniform(0.5, 20)) for _ in range(n)) for path, n in visits.items()}
for path in history:
    if path != dl:
        history[path].append((datetime.now(timezone.utc) + timedelta(minutes=2)).strftime("%Y-%m-%dT%H:%M:%SZ"))
save("history.json", {"entries": history})

# Where downloads went before, so Triage has something to suggest.
entries = []
def moved(name, dest, days_ago, site=None, action="move"):
    change = {"from": os.path.join(dl, name), "to": os.path.join(dest, name)}
    if site:
        change["site"] = site
    entries.append({"id": str(uuid.uuid4()).upper(), "date": iso(days_ago, 10), "action": action, "changes": [change]})
inv = os.path.join(NW, "Finance/Invoices")
for i, d in enumerate((40, 31, 19, 9)):
    moved(f"Invoice {1036 + i} - Acme Coffee.pdf", inv, d, "billing.acmecoffee.com")
moved("Invoice 1041 - Lumen Health.pdf", inv, 7)
moved("harbor-sketches.pdf", os.path.join(CL, "Harbor & Pine"), 12, "figma.com")
moved("harbor-type-specimens.pdf", os.path.join(CL, "Harbor & Pine"), 5, "figma.com")
moved("acme-labels-v2.pdf", os.path.join(CL, "Acme Coffee"), 15, "figma.com")
moved("Shoot day 1.zip", os.path.join(NW, "Photos/Product Shoot"), 11, "dropbox.com")
moved("Shoot day 2.zip", os.path.join(NW, "Photos/Product Shoot"), 10, "dropbox.com")
moved("Packaging survey.csv", os.path.join(NW, "Research"), 18, "forms.studio-research.com")
entries.sort(key=lambda e: e["date"])
with open(os.path.join(store, "file-history.jsonl"), "w") as f:
    f.writelines(json.dumps(e) + "\n" for e in entries)

# Two "Always do this" rules, for the Triage page (they don't match anything waiting, so nothing moves).
save("triage-rules.json", [
    {"id": str(uuid.uuid4()).upper(), "name": "Bank statements", "site": None, "extensions": ["pdf"],
     "nameContains": "statement", "destination": os.path.join(NW, "Finance/Taxes 2026"), "isEnabled": True, "created": iso(30)},
    {"id": str(uuid.uuid4()).upper(), "name": "Fonts from fonts.studio-type.com", "site": "fonts.studio-type.com",
     "extensions": ["otf", "ttf"], "nameContains": None, "destination": os.path.join(NW, "Brand"), "isEnabled": True, "created": iso(45)},
])

# ---------------------------------------------------------------- Settings for the demo app
def tab(path, view="list"):
    return {"path": path, "mode": {"folder": {}}, "viewMode": view}
layouts = [
    {"id": str(uuid.uuid4()).upper(), "name": "Client work", "session": {"panes": [
        {"tabs": [tab(CL)], "selected": 0},
        {"tabs": [tab(dl), tab(inv)], "selected": 0}], "focused": 0}},
    {"id": str(uuid.uuid4()).upper(), "name": "Month-end close", "session": {"panes": [
        {"tabs": [tab(inv), tab(os.path.join(NW, "Finance"))], "selected": 0},
        {"tabs": [tab(dl)], "selected": 0}], "focused": 0}},
]
subprocess.run(["defaults", "delete", BUNDLE], capture_output=True)   # start clean
for key, kind, value in [
    ("developerTools", "-bool", "true"), ("welcomeShown", "-bool", "true"), ("menuBarIcon", "-bool", "false"),
    ("inspectorShown", "-bool", "true"),
    ("jumpHotKey", "-string", "optionSpace"), ("appearance", "-string", "dark"), ("NSQuitAlwaysKeepsWindows", "-bool", "false"),
]:
    run("defaults", "write", BUNDLE, key, kind, value)
run("defaults", "write", BUNDLE, "savedLayouts", "-data", json.dumps(layouts).encode().hex())

print("Built", HOME)
