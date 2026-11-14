# Marketing

The launch video, the link-preview card and the demo folder used for screenshots. Each is
plain HTML rendered with headless Chrome, so changing a word or a color is a quick edit.

```sh
cd marketing && npm install
npx @puppeteer/browsers install chrome-headless-shell@127.0.6533.72   # once, or set CHROME_PATH
```

| Folder | What it makes | Run |
|---|---|---|
| [`launch-video/`](launch-video) | The 15-second launch video, 1080p at 60 fps (needs `ffmpeg`). Scenes and timing are in `index.html`; `render.mjs` renders every frame into `scout-launch.mp4`. `node render.mjs out.mp4 --stills 1,4,7` saves a few frames to check first. | `npm run video` |
| [`share-card/`](share-card) | The image shown when a Scout link is shared (`site/assets/og.jpg`, 2400×1260). | `npm run share-card` |
| [`demo-folder/`](demo-folder) | `/Users/Shared/Northwind Studio`: a made-up design studio with real images, PDFs, Word and Excel files, tags, varied dates and a small git repo, for screenshots that don't show anyone's own files. An existing copy goes to the Trash. | `npm run demo-folder` |

When taking screenshots in the palette, search with the **In Northwind Studio** chip on:
`/Users/Shared` isn't in Scout's folder index, so a plain search shows your own files instead.
