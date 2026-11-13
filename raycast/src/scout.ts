import { closeMainWindow, open } from "@raycast/api";
import { existsSync } from "node:fs";
import { homedir } from "node:os";

/** The `scout` CLI that ships inside Scout.app (or the dev symlink). */
export const SCOUT_CLI = [
  "/Applications/Scout.app/Contents/Helpers/scout",
  `${homedir()}/.local/bin/scout`,
].find((path) => existsSync(path));

export type RankedFolder = {
  path: string;
  name: string;
  displayPath: string;
  score: number;
  visits: number;
};

/** Opens a folder (or reveals a file) in Scout via a scout:// link. */
export async function openInScout(path: string, options: { newTab?: boolean } = {}) {
  const params = new URLSearchParams({ path });
  if (options.newTab) params.set("newTab", "1");
  await closeMainWindow({ clearRootSearch: true });
  await open(`scout://open?${params.toString()}`);
}
