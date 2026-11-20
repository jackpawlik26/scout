#!/bin/zsh
# Builds the demo folder in a staging dir, then swaps it in at /Users/Shared/Northwind Studio.
set -e
HERE=${0:A:h}
STAGE=$HERE/stage/Northwind\ Studio
DEST="${NORTHWIND_DEST:-/Users/Shared/Northwind Studio}"
rm -rf "$HERE/stage"; mkdir -p "$STAGE"
cd "$HERE/.."   # marketing/, where puppeteer-core is installed
node demo-folder/gen.mjs "$STAGE"
cd "$STAGE"

# ---- Word documents (textutil turns HTML into real .docx) ----
doc() { # path, title, body html
  mkdir -p "${1:h}"
  print -r -- "<html><body style='font-family:Helvetica'><h1>$2</h1>$3</body></html>" > /tmp/scout-demo-$$.html
  textutil -convert docx /tmp/scout-demo-$$.html -output "$1"; rm /tmp/scout-demo-$$.html
}
doc "Launch Plan.docx" "Spring Collection Launch Plan" "<p>Launch date: March 12, 2026.</p><h2>Goals</h2><ul><li>2,000 pre-orders</li><li>Press in three design outlets</li></ul><h2>Owners</h2><p>Marta (brand), Joao (web), Ines (social).</p>"
doc "Clients/Acme Coffee/Brief - Acme Coffee.docx" "Acme Coffee Brief" "<p>Acme wants packaging that feels warm and local without looking old-fashioned.</p>"
doc "Clients/Harbor & Pine/Meeting Notes - Kickoff.docx" "Kickoff Notes" "<p>Attendees: Marta, Joao, Jamie Pine.</p><p>Next step: discovery interviews next week.</p>"
doc "Brand/Brand Guidelines.docx" "Northwind Brand Guidelines" "<p>Use the mark on white or navy only. Leave space equal to the height of the N on every side.</p>"
doc "Inbox/notes (1).docx" "Notes" "<p>Call the printer about paper samples.</p>"

# ---- Spreadsheets (a minimal real .xlsx) ----
xlsx() { # path, rows as "a|b|c;d|e|f"
  local dir=$(mktemp -d)
  mkdir -p "$dir/_rels" "$dir/xl/_rels" "$dir/xl/worksheets"
  print -r -- '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>' > "$dir/[Content_Types].xml"
  print -r -- '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>' > "$dir/_rels/.rels"
  print -r -- '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>' > "$dir/xl/workbook.xml"
  print -r -- '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>' > "$dir/xl/_rels/workbook.xml.rels"
  local rows="" r=0
  for line in ${(s:;:)2}; do
    r=$((r+1)); rows+="<row r=\"$r\">"
    for cell in ${(s:|:)line}; do
      if [[ $cell == <-> ]]; then rows+="<c><v>$cell</v></c>"; else rows+="<c t=\"inlineStr\"><is><t>$cell</t></is></c>"; fi
    done
    rows+="</row>"
  done
  print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>$rows</sheetData></worksheet>" > "$dir/xl/worksheets/sheet1.xml"
  mkdir -p "${1:h}"; local out="$PWD/$1"
  (cd "$dir" && zip -qX -r "$out" "[Content_Types].xml" _rels xl); rm -rf "$dir"
}
xlsx "Q4 Budget.xlsx" "Category|October|November|December;Payroll|42000|42000|44500;Rent|2100|2100|2100;Software|860|910|910;Travel|1200|3400|600"
xlsx "Finance/Revenue by Client.xlsx" "Client|2025|2026;Acme Coffee|38000|52400;Harbor & Pine|0|36000;Lumen Health|21000|47500"
xlsx "Finance/Taxes 2026/Expenses 2026.xlsx" "Month|Expenses;January|7100;February|6900;March|7450"
xlsx "Research/Survey Results.xlsx" "Question|Yes|No;Would refill|412|88;Prefers paper|377|123"

# ---- Plain text, Markdown, CSV ----
mkdir -p Research Inbox Projects
cat > "Meeting Notes.md" <<'EOF'
# Studio meeting · Nov 13

- Harbor & Pine kickoff went well; discovery starts Monday
- Spring Collection photos are in **Photos/Product Shoot**
- Move old client folders into Archive before the year ends

## To do
- [ ] Send invoice 1043
- [x] Book the Lisbon offsite
EOF
cat > "Research/Interview Notes.md" <<'EOF'
# Customer interviews

> "I keep the tin long after the coffee is gone." — Acme customer

Themes: reuse, warmth, a sense of place.
EOF
cat > "Research/Competitors.csv" <<'EOF'
Name,City,Focus,Team size
Studio Sal,Porto,Packaging,8
Linea,Madrid,Brand,14
Forma,Barcelona,Web,22
EOF
print -r -- "Call the printer about paper samples. Ask about recycled stock." > "Inbox/todo.txt"
print -r -- "Wi-Fi: Northwind-Guest" > "Inbox/Studio Wi-Fi.txt"
cp "Inbox/invoice_8841.pdf" "Inbox/invoice_8841 (1).pdf"

# ---- A small web project (a real git repo, for Developer tools) ----
mkdir -p "Projects/northwind-site/src"
cd "Projects/northwind-site"
cat > README.md <<'EOF'
# northwind-site

The studio website. `npm run dev` to work on it locally.
EOF
print -r -- '{ "name": "northwind-site", "version": "1.4.0", "scripts": { "dev": "vite" } }' > package.json
print -r -- '<!doctype html><title>Northwind Studio</title><h1>Northwind</h1>' > src/index.html
print -r -- 'body { font-family: system-ui; color: #1F3A5F; }' > src/styles.css
git init -q; git config user.name "Northwind"; git config user.email "studio@example.com"
git add -A; git commit -qm "First version of the site"
print -r -- '<!doctype html><title>Northwind Studio</title><h1>Northwind</h1><p>Spring Collection is here.</p>' > src/index.html
print -r -- 'export const launch = "2026-03-12";' > src/launch.js
cd "$STAGE"

# ---- Archive (a real zip of last year's work) ----
mkdir -p "Archive/2025 Client Work"
cp "Clients/Acme Coffee/Packaging Concepts.pdf" "Archive/2025 Client Work/Acme Packaging v1.pdf"
(cd Archive && zip -qr "2025 Client Work.zip" "2025 Client Work")

# ---- Finder tags (Scout shows and filters by these) ----
tag() { # path, then "Name:colorIndex" pairs (2 green, 4 blue, 5 yellow, 6 red, 7 orange)
  local f=$1; shift
  python3 -I - "$f" "$@" <<'PY'
import plistlib, subprocess, sys
f, tags = sys.argv[1], [t.replace(':', '\n') for t in sys.argv[2:]]
data = plistlib.dumps(tags, fmt=plistlib.FMT_BINARY).hex()
subprocess.run(['xattr', '-wx', 'com.apple.metadata:_kMDItemUserTags', data, f], check=True)
PY
}
tag "Launch Plan.docx" "Urgent:6"
tag "Pitch Deck.pdf" "Client:4"
tag "Q4 Budget.xlsx" "Finance:2" "Review:5"
tag "Contract - Signed.pdf" "Finance:2"
tag "Clients/Harbor & Pine" "Client:4"
tag "Clients/Acme Coffee" "Client:4"
tag "Finance/Invoices/Invoice 1043 - Lumen Health.pdf" "Urgent:6"
tag "Photos/Product Shoot" "Review:5"

# ---- Realistic dates, newest at the top level ----
python3 -I - "$STAGE" <<'PY'
import os, sys, random, time
random.seed(7)
root = sys.argv[1]
now = time.time()
for d, dirs, files in os.walk(root):
    if '.git' in d: continue
    for n in files:
        p = os.path.join(d, n)
        depth = p[len(root):].count('/')
        age = random.uniform(0.2, 6) * 86400 if depth == 1 else random.uniform(3, 60) * 86400
        if 'Archive' in p: age = random.uniform(200, 320) * 86400
        os.utime(p, (now - age, now - age))
PY

# ---- Swap it in (the old copy goes to the Trash) ----
if [[ -d "$DEST" ]]; then
  mv "$DEST" ~/.Trash/"Northwind Studio (old demo) $(date +%s)"
fi
mv "$STAGE" "$DEST"
print "Built $DEST"; find "$DEST" -not -path '*/.git/*' | wc -l
