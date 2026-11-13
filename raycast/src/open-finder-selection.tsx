import { getSelectedFinderItems, showHUD } from "@raycast/api";
import { runAppleScript } from "@raycast/utils";
import { openInScout } from "./scout";

/** Opens what you've selected in Finder, or else the front Finder window's folder, in Scout. */
export default async function OpenFinderSelection() {
  let path: string | undefined;

  try {
    path = (await getSelectedFinderItems())[0]?.path;
  } catch {
    // Nothing selected, or Finder isn't frontmost. Fall back to the front window.
  }

  if (!path) {
    try {
      path = await runAppleScript(
        'tell application "Finder" to if (count of Finder windows) > 0 then return POSIX path of (target of front Finder window as alias)',
      );
    } catch {
      path = undefined;
    }
  }

  if (!path) {
    await showHUD("No Finder selection or window to open");
    return;
  }
  await openInScout(path);
}
