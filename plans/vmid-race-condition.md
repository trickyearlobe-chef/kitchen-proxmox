# Fix VMID Race Condition

## Goal

Replace sequential VMID allocation (`GET /cluster/nextid`) with random high-range allocation + validation to eliminate concurrent clone collisions.

## Context

- Nuclia doc: "Proxmox VMID Race Condition — Empirical Test Results (2026-05-04)"
- `GET /cluster/nextid` doesn't reserve — concurrent instances get the same ID
- Fix: random VMID in 900000–999999, validate with `GET /cluster/nextid?vmid=X`

## Steps

1. Add `validate_vmid` to ApiClient (calls `GET /cluster/nextid?vmid=X`)
2. Add config options: `vmid_range_min` (900000), `vmid_range_max` (999999)
3. Rewrite `allocate_vm_id` to pick random + validate
4. Update specs (TDD — specs first)
5. Run tests, confirm green

## Acceptance Criteria

- `allocate_vm_id` no longer calls `next_vm_id`
- Random VMID in configurable high range
- Validation call before clone
- Existing retry/backoff logic unchanged
- All specs pass
