// The headless Chrome these scripts drive. Set CHROME_PATH to use another one, or install this
// one with: npx @puppeteer/browsers install chrome-headless-shell@127.0.6533.72
import os from 'node:os';
import path from 'node:path';

export const chromePath = process.env.CHROME_PATH ?? path.join(os.homedir(),
  '.cache/puppeteer/chrome-headless-shell/mac_arm-127.0.6533.72/chrome-headless-shell-mac-arm64/chrome-headless-shell');
