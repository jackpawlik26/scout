#!/bin/zsh
# Publishes site/ (landing page + changelog) to Cloudflare Pages as the "scout-app" project.
# First time: run `npx wrangler login` once. Prints the live URL when done.
set -e
cd "$(dirname "$0")/.."
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
npx -y wrangler@4 pages project create scout-app --production-branch main 2>/dev/null || true
npx -y wrangler@4 pages deploy site --project-name scout-app --branch main --commit-dirty=true
