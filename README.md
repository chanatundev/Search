# Search — fork additions

This fork adds the features below to [upstream Search](https://github.com/driceroland/Search). See upstream for the base browser, its setup, and general project documentation.

## Command Palette

`⌘E` opens a searchable palette of browser actions. Use `↑` and `↓`, then `Return`, or click an action; `esc` closes it. The palette includes:

- **Numbered Spaces:** press `1`–`9` to switch directly to that Space. Other Spaces remain selectable from the list.
- **Background sleep actions:** put eligible tabs in the current Space or in background Spaces to sleep.

## Multi-tab selection and actions

In either tab layout, `⌘`-click toggles a tab in the selection. `⌘⇧`-click extends the selection across the range from the last Command-clicked tab. Right-click a selected tab to act on the selection:

- Copy selected addresses as newline-separated URLs.
- Paste multiple HTTP or HTTPS URLs with `⇧⌘V` to open them as tabs.
- Close the selected tabs together.
- Move one or more tabs to another Space.

For regular web tabs moved into a Space with a different WebKit data store, Search recreates them at their current addresses in the destination. The destination keeps its own cookies and site data.
