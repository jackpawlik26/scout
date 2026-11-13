import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useExec } from "@raycast/utils";
import { useState } from "react";
import { openInScout, RankedFolder, SCOUT_CLI } from "./scout";

export default function JumpToFolder() {
  const [query, setQuery] = useState("");

  // Ranking happens in Scout's own CLI, so results match ⌘K inside Scout exactly.
  const { data, isLoading, error } = useExec(SCOUT_CLI ?? "false", ["rank", query, "--json", "--limit", "60"], {
    execute: SCOUT_CLI !== undefined,
    keepPreviousData: true,
    parseOutput: ({ stdout, stderr, exitCode }) => {
      if (exitCode !== 0) throw new Error(stderr.trim() || `scout exited with code ${exitCode}`);
      return JSON.parse(stdout) as RankedFolder[];
    },
  });

  if (!SCOUT_CLI) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.Warning}
          title="Scout isn't installed"
          description="Run ~/Scout/scripts/install.sh to install Scout.app."
        />
      </List>
    );
  }

  return (
    <List
      isLoading={isLoading}
      filtering={false}
      throttle
      onSearchTextChange={setQuery}
      searchBarPlaceholder="Jump to a folder…"
    >
      {error ? (
        <List.EmptyView icon={Icon.Warning} title="Couldn't search Scout's index" description={error.message} />
      ) : (
        <List.Section title={query ? "Folders" : "Most Used"}>
          {data?.map((folder) => (
            <FolderItem key={folder.path} folder={folder} />
          ))}
        </List.Section>
      )}
    </List>
  );
}

function FolderItem({ folder }: { folder: RankedFolder }) {
  return (
    <List.Item
      title={folder.name}
      subtitle={folder.displayPath}
      icon={{ fileIcon: folder.path }}
      accessories={folder.visits > 0 ? [{ icon: Icon.Clock, tooltip: `Visited ${folder.visits}× recently` }] : []}
      actions={
        <ActionPanel>
          <ActionPanel.Section>
            <Action title="Open in Scout" icon={Icon.Binoculars} onAction={() => openInScout(folder.path)} />
            <Action
              title="Open in New Scout Tab"
              icon={Icon.NewDocument}
              shortcut={{ modifiers: ["cmd"], key: "return" }}
              onAction={() => openInScout(folder.path, { newTab: true })}
            />
          </ActionPanel.Section>
          <ActionPanel.Section>
            <Action.Open
              title="Open in Terminal"
              icon={Icon.Terminal}
              target={folder.path}
              application="com.apple.Terminal"
              shortcut={{ modifiers: ["cmd"], key: "t" }}
            />
            <Action.OpenWith path={folder.path} shortcut={{ modifiers: ["cmd"], key: "o" }} />
            <Action.ShowInFinder path={folder.path} shortcut={{ modifiers: ["cmd"], key: "f" }} />
            <Action.CopyToClipboard
              title="Copy Path"
              content={folder.path}
              shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
            />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}
