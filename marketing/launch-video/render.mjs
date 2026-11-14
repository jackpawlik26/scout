// Renders index.html frame by frame and pipes the frames into ffmpeg.
// Usage: node render.mjs out.mp4 [--stills 1,4,7.5,10,14]
import puppeteer from 'puppeteer-core';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { chromePath as chrome } from '../chrome.mjs';
import fs from 'node:fs';

const out = process.argv[2] ?? 'out.mp4';
const stillsArg = process.argv.indexOf('--stills');
const FPS = 60, DURATION = 15, W = 1920, H = 1080;

const browser = await puppeteer.launch({ executablePath: chrome, headless: 'shell', args: ['--force-color-profile=srgb', '--hide-scrollbars'] });
const page = await browser.newPage();
await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.resolve('index.html')).href);
await page.evaluate(() => window.ready);
await page.evaluate(() => document.fonts.ready);

if (stillsArg > 0) {
  fs.mkdirSync('stills', { recursive: true });
  for (const t of process.argv[stillsArg + 1].split(',').map(Number)) {
    await page.evaluate(t => window.render(t), t);
    await page.screenshot({ path: `stills/t${t}.png` });
  }
  await browser.close();
  process.exit(0);
}

const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
  '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-movflags', '+faststart', out],
  { stdio: ['pipe', 'inherit', 'inherit'] });

const frames = FPS * DURATION;
for (let i = 0; i < frames; i++) {
  await page.evaluate(t => window.render(t), i / FPS);
  const buf = await page.screenshot({ type: 'png' });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % 120 === 0) process.stdout.write(`frame ${i}/${frames}\n`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log('wrote', out);
