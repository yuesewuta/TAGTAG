# 01 - Domain

State: resolved
Type: task

- Resolved 2026-08-19: `_withTagOperation` 新增 `context` 参数（lib/state/tagtag_controller.dart），各记录点写入撤销快照：createPlacement {placementId, tagId, createdNewTag}；updateTag {tagId, previousName, previousColorValue}；reparentPlacement {placementId, previousParentId, previousSortOrder}；deletePlacement {placementId, tagId, parentId, sortOrder, promotedChildIds, reassignedAssignmentIds, replacementPlacementId, droppedAssignments}（含被去重丢弃的原有标注，保证精确还原）；deleteTagEntity {tag, placements[], assignments[], inheritanceRules[], promotedChildren[]}；togglePinned/Hidden {placementId, previous}。同名策略从 `edit` 拆为独立 `TagDomainOperationType.policy`（枚举追加值，旧 merge/split 等 JSON 记录仍可解析）。`undoTagOperation` 重构为按类型分派：create 删除位置并在 createdNewTag 时连带删除实体（已有子位置/标注/继承规则/其他位置则以 StateError 拒绝）、edit 还原名称与颜色、policy 还原策略、reparent 还原上级与排序、deletePlacement 重建位置并回移子位置与标注、deleteEntity 整体还原快照、pin/hide 还原集合成员；保留从新到旧顺序约束与重复撤销报错，缺上下文的旧记录（如资源标注类 edit）以明确 StateError 拒绝而不破坏状态；撤销后校正失效的 activePlacementId（删除类撤销恢复到还原的位置）。
- 证据：新增 test/tag_operation_undo_test.dart 11 个测试（各类型撤销往返、复用实体创建、持久化重载后连续撤销、重复撤销报错、无上下文旧记录拒绝、JSON 向后兼容）；`analyze --no-pub` 0 问题；全量 `test --no-pub` 173/173 通过。
