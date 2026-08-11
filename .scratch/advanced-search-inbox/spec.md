# Advanced search and global inbox

The search view filters current-space resources by name, managed path, tag name, resource kind, size, creation time, modification time, and stable tag entity IDs. The inbox view can switch between the active space and all spaces.

## Acceptance

- Keyword search covers resource name, managed path, and effective tag display names without reading resource contents.
- Resource kind supports all, file, and folder.
- Inclusive minimum and maximum filters are available for size, creation time, and modification time.
- Tag AND requires every selected entity, OR requires at least one selected entity when present, and NOT excludes every selected entity.
- Boolean conditions use stable tag entity IDs. Independent same-name tags remain distinct.
- Current-space inbox contains members with no effective tag in the active space.
- Global inbox contains managed resources with no effective tag in any space.
- Legacy state documents without size or creation metadata still load.
