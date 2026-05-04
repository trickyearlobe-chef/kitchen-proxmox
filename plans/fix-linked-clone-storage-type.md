# Fix: Linked Clone Storage Type Detection

## Goal

Linked clones require storage that supports snapshots. Plain LVM (`type: lvm`) does NOT support linked clones even when shared. Fix `detect_clone_strategy` to check storage `type` in addition to `shared` flag.

## Spec to Read

- `specifications/cluster-awareness.md` — Feature 4 (Smart Clone Strategy)

## Logic

Linked clone is valid only when storage is BOTH:
1. Shared (`shared == 1`)
2. Supports linked clones (storage type in allowlist)

Allowlist: `lvmthin`, `nfs`, `dir`, `cephfs`, `rbd`, `zfspool`, `btrfs`
Denylist: `lvm`, `iscsi`, `iscsidirect`

Node pinning: only when storage is NOT shared (local). Shared storage that doesn't support linked clones → full clone, no pinning needed.

## Steps

1. Write new/updated specs for the four cases:
   - Shared + supports linked → linked clone, any node
   - Shared + no linked support (lvm) → full clone, any node (NO pinning)
   - Local + supports linked → full clone, pin to template node
   - Local + no linked support → full clone, pin to template node
2. Rename `template_on_shared_storage?` → `storage_supports_linked_clone?`
3. Update `detect_clone_strategy` with the new logic
4. Run specs, verify green
5. Run rubocop, verify clean

## Acceptance Criteria

- SharedLVM (type: lvm, shared: 1) → full clone, no node pinning
- Shared NFS (type: nfs, shared: 1) → linked clone, no node pinning
- Local lvmthin (type: lvmthin, shared: 0) → full clone, pinned
- All 117+ specs pass
- Rubocop clean
