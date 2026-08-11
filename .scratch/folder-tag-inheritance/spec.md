# Folder tag inheritance

A folder can explicitly enable child inheritance for one of its direct tags. The rule is off by default and dynamically contributes an effective tag to managed descendants without creating direct child assignments.

## Acceptance

- A rule identifies the source folder and tag entity, not a tag display name or child copy.
- Current and future managed descendants gain the effective tag while they remain under the source folder.
- A resource moved outside the source folder loses the inherited tag; a resource moved inside gains it.
- Direct and inherited sources remain distinguishable in the resource list.
- The current-space inbox is calculated from effective tags.
- Clearing the source folder's direct tags also removes its inheritance rules.
- Rules survive restart and full backup through the existing tag-domain state document.
- The Quick Tag dialog can enable or disable inheritance for one selected folder without opening a second dialog.
