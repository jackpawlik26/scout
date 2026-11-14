// Builds the "Northwind Studio" demo folder: real images and PDFs (so previews and thumbnails
// work), rendered with headless Chrome. Office files, tags, dates and git come from build.sh.
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
import { chromePath as chrome } from '../chrome.mjs';

const ROOT = process.argv[2];
const browser = await puppeteer.launch({ executablePath: chrome, headless: 'shell' });
const page = await browser.newPage();
const FONT = `-apple-system, system-ui, sans-serif`;

async function image(file, w, h, body, css = '') {
  const out = path.join(ROOT, file);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
  await page.setContent(`<style>*{margin:0;box-sizing:border-box}html,body{width:${w}px;height:${h}px;overflow:hidden;font-family:${FONT}}${css}</style>${body}`);
  await page.screenshot({ path: out, type: file.endsWith('.png') ? 'png' : 'jpeg', ...(file.endsWith('.png') ? {} : { quality: 88 }) });
}

async function pdf(file, html, { landscape = false } = {}) {
  const out = path.join(ROOT, file);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  await page.setContent(`<style>*{margin:0;box-sizing:border-box}body{font-family:${FONT};color:#1d1d1f}
    .page{page-break-after:always;position:relative;overflow:hidden}
    h1{font-size:34px;font-weight:600;letter-spacing:-.6px} h2{font-size:20px;font-weight:600;margin:26px 0 8px}
    p,li{font-size:13px;line-height:1.6;color:#3a3a3c} table{border-collapse:collapse;width:100%;font-size:12.5px}
    td,th{padding:9px 10px;border-bottom:1px solid #e5e5ea;text-align:left} th{color:#6e6e73;font-weight:500}
    .num{text-align:right;font-variant-numeric:tabular-nums} .muted{color:#86868b}</style>${html}`);
  await page.pdf({ path: out, format: 'Letter', landscape, printBackground: true, margin: { top: 0, bottom: 0, left: 0, right: 0 } });
}

// ---------- Scenes: flat "photos" that read well as thumbnails ----------
const scene = (sky, sun, layers, sunPos = '62% 38%') => `
  <div style="position:absolute;inset:0;background:linear-gradient(180deg,${sky})"></div>
  <div style="position:absolute;width:22%;aspect-ratio:1;border-radius:50%;left:${sunPos.split(' ')[0]};top:${sunPos.split(' ')[1]};background:${sun};filter:blur(1px);box-shadow:0 0 120px 40px ${sun}55"></div>
  ${layers.map(([c, poly]) => `<div style="position:absolute;inset:0;background:${c};clip-path:polygon(${poly})"></div>`).join('')}`;
const hills = (y, amp, seed) => {
  const pts = []; for (let i = 0; i <= 12; i++) pts.push(`${(i / 12) * 100}% ${y + Math.sin(i * 1.3 + seed) * amp + Math.cos(i * .7 + seed * 2) * amp * .6}%`);
  return `0% 100%, ${pts.join(', ')}, 100% 100%`;
};
const scenes = [
  ['#FF9A62 0%,#FFC58A 45%,#FDE2C3 100%', '#FFF3D6', [['#C4673F', hills(66, 4, 1)], ['#8A3B2A', hills(78, 5, 3)], ['#4E2219', hills(90, 3, 5)]]],
  ['#1E3C72 0%,#5B7DB8 55%,#F2B5A0 100%', '#FFE2C2', [['#2C4A6E', hills(70, 6, 2)], ['#1B2F48', hills(82, 4, 4)]], '30% 52%'],
  ['#9BD6F4 0%,#D9F1FB 60%,#FFFFFF 100%', '#FFFFFF', [['#7FB5C9', hills(60, 2, 0)], ['#3E8BA6', '0% 72%, 100% 68%, 100% 100%, 0% 100%'], ['#E9D8B4', '0% 86%, 100% 82%, 100% 100%, 0% 100%']], '70% 18%'],
  ['#2B1055 0%,#7597DE 100%', '#F8F1FF', [['#3B2370', hills(64, 7, 6)], ['#21123F', hills(80, 5, 1)]], '20% 20%'],
  ['#F6D365 0%,#FDA085 100%', '#FFFFFF', [['#E07A5F', hills(72, 3, 7)], ['#3D405B', hills(86, 2, 2)]], '45% 30%'],
  ['#0F2027 0%,#203A43 50%,#2C5364 100%', '#F4F1DE', [['#16313B', hills(68, 8, 3)], ['#0B1A20', hills(84, 4, 8)]], '75% 22%'],
  ['#A8E6CF 0%,#DCEDC1 60%,#FFF8E1 100%', '#FFFFFF', [['#5FA77C', hills(62, 6, 9)], ['#2E6B4F', hills(78, 5, 2)], ['#1D4434', hills(90, 2, 4)]], '15% 15%'],
  ['#FFAFBD 0%,#FFC3A0 100%', '#FFF6E9', [['#D9707F', hills(70, 5, 5)], ['#8E3E5C', hills(84, 4, 7)]], '55% 40%'],
  ['#355C7D 0%,#6C5B7B 50%,#C06C84 100%', '#FFE5B4', [['#2E3F59', hills(74, 3, 1)], ['#1C2639', '0% 88%, 100% 86%, 100% 100%, 0% 100%']], '48% 50%'],
  ['#E0EAFC 0%,#CFDEF3 100%', '#FFFFFF', [['#9FB4CC', hills(58, 9, 4)], ['#6F86A3', hills(72, 7, 6)], ['#47596F', hills(88, 3, 3)]], '80% 12%'],
  ['#FBD786 0%,#F7797D 100%', '#FFF9E6', [['#C65B5F', hills(76, 4, 2)], ['#6E2C3F', hills(88, 3, 9)]], '25% 35%'],
  ['#43C6AC 0%,#F8FFAE 100%', '#FFFFFF', [['#2F9C88', hills(66, 5, 8)], ['#1E5F55', hills(82, 4, 1)]], '68% 26%'],
];

for (let i = 0; i < 12; i++) {
  const [sky, sun, layers, pos] = scenes[i];
  await image(`Photos/Lisbon Offsite/IMG_${4101 + i * 3}.JPG`, 1600, 1200, scene(sky, sun, layers, pos));
}
for (const [i, n] of [[0, 'Studio Wall'], [3, 'Team Offsite'], [8, 'Hero Render']]) {
  const [sky, sun, layers, pos] = scenes[i];
  await image(`${n}.png`, 2000, 1250, scene(sky, sun, layers, pos));
}

// Product shots: a soft object on a colored backdrop.
const products = [['Ceramic Mug', '#F1E4D3', '#D9774B'], ['Desk Lamp', '#DDE7F0', '#2F5D8A'], ['Notebook', '#EDE3F7', '#6553F0'], ['Water Bottle', '#E2F2EA', '#2F8F6B'], ['Tote Bag', '#F7E8E1', '#B5523B'], ['Headphones', '#E9E9EC', '#1D1D1F']];
for (const [n, bg, fg] of products) {
  await image(`Photos/Product Shoot/${n}.jpg`, 1400, 1400, `
    <div style="position:absolute;inset:0;background:radial-gradient(circle at 50% 40%, #fff 0%, ${bg} 70%)"></div>
    <div style="position:absolute;left:50%;top:78%;width:46%;height:6%;transform:translate(-50%,-50%);border-radius:50%;background:#0002;filter:blur(18px)"></div>
    <div style="position:absolute;left:50%;top:48%;width:40%;height:52%;transform:translate(-50%,-50%);border-radius:28% 28% 22% 22%;background:linear-gradient(140deg, ${fg}cc, ${fg});box-shadow:inset -30px -40px 80px #0003, inset 30px 30px 60px #fff4"></div>`);
}

// Brand assets: logo marks and a palette card.
const mark = (bg, fg, r = '28%') => `<div style="position:absolute;inset:0;background:${bg};display:grid;place-items:center">
  <div style="width:46%;aspect-ratio:1;border-radius:${r};background:${fg};display:grid;place-items:center;color:${bg};font:700 260px/1 ${FONT};letter-spacing:-10px">N</div></div>`;
await image('Brand/Logo/Northwind Mark.png', 1024, 1024, mark('#FFFFFF', '#1F3A5F'));
await image('Brand/Logo/Northwind Mark (Dark).png', 1024, 1024, mark('#1F3A5F', '#FFFFFF'));
await image('Brand/Logo/Northwind Mark (Coral).png', 1024, 1024, mark('#FFF4EE', '#E8735A', '50%'));
await image('Brand/Logo/Northwind Wordmark.png', 1600, 600, `<div style="position:absolute;inset:0;background:#fff;display:flex;align-items:center;justify-content:center;gap:40px">
  <div style="width:180px;height:180px;border-radius:28%;background:#1F3A5F;color:#fff;display:grid;place-items:center;font:700 120px/1 ${FONT}">N</div>
  <div style="font:600 150px/1 ${FONT};letter-spacing:-6px;color:#1F3A5F">northwind</div></div>`);
const pal = ['#1F3A5F', '#E8735A', '#F4D35E', '#7FB7BE', '#F7F3EE'];
await image('Brand/Color Palette.png', 1600, 900, `<div style="position:absolute;inset:0;display:flex">${pal.map(c => `<div style="flex:1;background:${c};display:flex;align-items:flex-end;padding:40px;font:500 34px ${FONT};color:${c === '#F7F3EE' || c === '#F4D35E' ? '#1F3A5F' : '#fff'}">${c}</div>`).join('')}</div>`);
await image('Brand/Social/Launch Banner.png', 1500, 500, `<div style="position:absolute;inset:0;background:linear-gradient(120deg,#1F3A5F,#3E6C9B);display:flex;align-items:center;padding:0 90px;gap:50px">
  <div style="width:150px;height:150px;border-radius:28%;background:#fff;color:#1F3A5F;display:grid;place-items:center;font:700 100px/1 ${FONT}">N</div>
  <div style="color:#fff"><div style="font:600 84px/1 ${FONT};letter-spacing:-3px">Spring Collection</div><div style="font:400 36px ${FONT};opacity:.8;margin-top:16px">Designed in Lisbon. Made to last.</div></div></div>`);
await image('Brand/Social/Instagram Post.jpg', 1080, 1080, scene(...scenes[4]) + `<div style="position:absolute;left:70px;bottom:80px;color:#fff;font:700 96px/1 ${FONT};letter-spacing:-4px;text-shadow:0 4px 30px #0004">New in.</div>`);

// Screenshots in the Inbox (the kind of clutter Tidy Folder sorts).
for (const [n, i] of [['Screenshot 2026-11-03 at 9.41.12 AM', 2], ['Screenshot 2026-11-10 at 4.18.55 PM', 9]]) {
  await image(`Inbox/${n}.png`, 1440, 900, scene(...scenes[i]));
}
await image('Inbox/IMG_8820.JPG', 1600, 1200, scene(...scenes[6]));
await image('Inbox/IMG_8821.JPG', 1600, 1200, scene(...scenes[10]));

// ---------- PDFs ----------
const cover = (title, sub, bg, fg = '#fff') => `<div class="page" style="height:11in;background:${bg};color:${fg};padding:1in">
  <div style="width:70px;height:70px;border-radius:28%;background:${fg};color:${bg};display:grid;place-items:center;font:700 44px/1 ${FONT}">N</div>
  <div style="position:absolute;left:1in;bottom:1.2in;right:1in"><div style="font:600 54px/1.05 ${FONT};letter-spacing:-1.5px">${title}</div>
  <div style="font:400 20px ${FONT};opacity:.8;margin-top:18px">${sub}</div></div></div>`;
const body = (...sections) => `<div class="page" style="height:11in;padding:.9in 1in">${sections.join('')}</div>`;
const lorem = [
  'Northwind is a small design studio in Lisbon. We make brands, packaging and websites for companies that care about the details.',
  'This document covers how we work, who does what, and what clients can expect at each step, from first call to launch.',
  'Every project starts with a two-week discovery: interviews, a competitive review and a written brief that both sides sign off on.',
  'We share work every Friday. Feedback goes in one shared document so nothing gets lost in email threads.',
];

await pdf('Studio Handbook.pdf', cover('Studio Handbook', 'How we work · 2026 edition', '#1F3A5F') +
  body(`<h1>Welcome</h1>${lorem.map(p => `<p style="margin-top:12px">${p}</p>`).join('')}<h2>Our week</h2><ul style="margin-left:18px">${['Monday: planning and studio standup', 'Wednesday: internal critique', 'Friday: client share-outs'].map(l => `<li>${l}</li>`).join('')}</ul><h2>Tools</h2><p>Figma for design, Notion for docs, and Scout for keeping project folders tidy.</p>`));

await pdf('Clients/Harbor & Pine/Proposal - Harbor & Pine.pdf', cover('Brand Refresh Proposal', 'Prepared for Harbor & Pine · November 2026', '#2E6B4F') +
  body(`<h1>Scope</h1><p style="margin-top:12px">${lorem[2]}</p><h2>Timeline</h2><table><tr><th>Phase</th><th>Weeks</th><th class="num">Fee</th></tr>
  ${[['Discovery', '1–2', '€6,000'], ['Identity', '3–6', '€14,500'], ['Packaging', '7–10', '€11,000'], ['Launch kit', '11–12', '€4,500']].map(r => `<tr><td>${r[0]}</td><td>${r[1]}</td><td class="num">${r[2]}</td></tr>`).join('')}
  <tr><td><b>Total</b></td><td></td><td class="num"><b>€36,000</b></td></tr></table>`));
await pdf('Clients/Acme Coffee/Packaging Concepts.pdf', cover('Packaging Concepts', 'Acme Coffee · Round 2', '#8A3B2A') + body(`<h1>Three directions</h1><p style="margin-top:12px">${lorem[3]}</p>`), {});
await pdf('Clients/Lumen Health/Website Sitemap.pdf', cover('Website Sitemap', 'Lumen Health · Draft for review', '#2B1055') + body(`<h1>Pages</h1><ul style="margin:12px 0 0 18px">${['Home', 'Services', 'Find a clinic', 'About', 'Careers', 'Contact'].map(l => `<li>${l}</li>`).join('')}</ul>`));

const invoice = (n, client, rows, date) => `<div class="page" style="height:11in;padding:.9in 1in">
  <div style="display:flex;justify-content:space-between;align-items:flex-start"><div><div style="width:54px;height:54px;border-radius:28%;background:#1F3A5F;color:#fff;display:grid;place-items:center;font:700 32px/1 ${FONT}">N</div>
  <p style="margin-top:14px">Northwind Studio<br>Rua da Prata 120, Lisbon</p></div><div style="text-align:right"><h1>Invoice</h1><p class="muted">#${n} · ${date}</p></div></div>
  <h2 style="margin-top:50px">Bill to</h2><p>${client}</p>
  <table style="margin-top:30px"><tr><th>Item</th><th class="num">Amount</th></tr>${rows.map(r => `<tr><td>${r[0]}</td><td class="num">${r[1]}</td></tr>`).join('')}</table>
  <p style="margin-top:30px;text-align:right;font-size:18px"><b>Due ${rows.at(-1)[1]}</b></p></div>`;
await pdf('Finance/Invoices/Invoice 1041 - Acme Coffee.pdf', invoice(1041, 'Acme Coffee', [['Packaging concepts', '€8,000'], ['Photography', '€2,400'], ['Total', '€10,400']], 'Oct 3, 2026'));
await pdf('Finance/Invoices/Invoice 1042 - Harbor & Pine.pdf', invoice(1042, 'Harbor & Pine', [['Discovery', '€6,000'], ['Total', '€6,000']], 'Oct 17, 2026'));
await pdf('Finance/Invoices/Invoice 1043 - Lumen Health.pdf', invoice(1043, 'Lumen Health', [['Sitemap and wireframes', '€7,500'], ['Total', '€7,500']], 'Nov 7, 2026'));
await pdf('Contract - Signed.pdf', body(`<h1>Services Agreement</h1><p class="muted" style="margin-top:6px">Northwind Studio and Harbor & Pine · Signed Nov 5, 2026</p>${lorem.map(p => `<p style="margin-top:12px">${p}</p>`).join('')}
  <div style="margin-top:80px;display:flex;gap:80px"><div><div style="font:italic 30px Snell Roundhand, cursive;color:#1F3A5F">M. Costa</div><p class="muted">Northwind Studio</p></div><div><div style="font:italic 30px Snell Roundhand, cursive;color:#1F3A5F">J. Pine</div><p class="muted">Harbor & Pine</p></div></div>`));

const slide = (title, sub, bg, fg = '#fff') => `<div class="page" style="height:8.5in;background:${bg};color:${fg};padding:.8in;display:flex;flex-direction:column;justify-content:flex-end">
  <div style="font:600 50px/1.05 ${FONT};letter-spacing:-1.5px">${title}</div><div style="font:400 20px ${FONT};opacity:.8;margin-top:14px">${sub}</div></div>`;
await pdf('Pitch Deck.pdf', slide('Northwind Studio', 'Design for brands that care about the details', '#1F3A5F') + slide('40 brands launched', 'Across food, health and retail since 2019', '#E8735A') + slide('Small team. Senior work.', 'Six designers, one studio, no handoffs', '#2E6B4F'), { landscape: true });
await pdf('Research/Packaging Trends 2026.pdf', cover('Packaging Trends 2026', 'Research notes · Northwind Studio', '#F4D35E', '#1F3A5F') + body(`<h1>Five things we're seeing</h1><ol style="margin:12px 0 0 18px">${['Refill-first formats', 'Bold flat color', 'Hand-drawn type', 'Paper over plastic', 'QR codes that earn their space'].map(l => `<li>${l}</li>`).join('')}</ol>`));
await pdf('Finance/Taxes 2026/Quarterly Estimate Q3.pdf', body(`<h1>Q3 Estimated Tax</h1><table style="margin-top:20px"><tr><th>Line</th><th class="num">Amount</th></tr>${[['Revenue', '€142,300'], ['Expenses', '€88,950'], ['Taxable income', '€53,350'], ['Estimate due', '€11,200']].map(r => `<tr><td>${r[0]}</td><td class="num">${r[1]}</td></tr>`).join('')}</table>`));
// Inbox clutter, including names the "Remove copy and numbers" preset cleans up.
await pdf('Inbox/invoice_8841.pdf', invoice(8841, 'Northwind Studio', [['Studio rent, November', '€2,100'], ['Total', '€2,100']], 'Nov 1, 2026'));
await pdf('Inbox/Proposal copy 2.pdf', cover('Brand Refresh Proposal', 'Draft', '#2E6B4F'));
await pdf('Inbox/Boarding Pass.pdf', body(`<h1>Boarding Pass</h1><p class="muted">LIS → CHI · Gate 14 · Seat 21A</p>`));

await browser.close();
console.log('images and PDFs done');
