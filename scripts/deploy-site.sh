#!/bin/zsh
# Publishes site/ (landing page + changelog) to Cloudflare as the "scout" Worker (static assets,
# see wrangler.jsonc). First time: `npx wrangler login`. Prints the live URL when done.
set -e
cd "$(dirname "$0")/.."
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
npx -y wrangler@4 deploy
