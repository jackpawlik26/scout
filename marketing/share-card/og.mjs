// Renders og.html to og.png (2400x1260). The site uses it as assets/og.jpg:
//   ffmpeg -i og.png -q:v 2 ../../site/assets/og.jpg
import puppeteer from 'puppeteer-core';
import path from 'node:path';
import { chromePath } from '../chrome.mjs';

const browser = await puppeteer.launch({ executablePath: chromePath, headless: 'shell', args: ['--force-color-profile=srgb'] });
const page = await browser.newPage();
await page.setViewport({ width: 1200, height: 630, deviceScaleFactor: 2 });
await page.goto('file://' + path.resolve('og.html'));
await page.evaluate(() => Promise.all([...document.images].map(i => i.decode())));
await page.screenshot({ path: 'og.png' });
await browser.close();
console.log('wrote share-card/og.png');
