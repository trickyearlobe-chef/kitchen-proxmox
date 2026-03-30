# Plan: Helpful validation for missing node/template_id

## Goal

When the user omits `node` or `template_id`, show a helpful list of available options fetched from the Proxmox API instead of a generic "missing config" error.

## Steps

1. Add `list_nodes` and `list_templates` methods to `ApiClient`.
2. Change `node` and `template_id` from `required_config` to `default_config nil`.
3. Add `validate_config!` private method in the driver that runs at the start of `create`.
4. If `node` is nil, call `list_nodes`, format and log them, then raise.
5. If `template_id` is nil, call `list_templates`, format and log them, then raise.
6. Update specs for both `ApiClient` and the driver.

## API Endpoints

- `GET /api2/json/nodes` — returns `[{node: "pve", status: "online", ...}, ...]`
- `GET /api2/json/cluster/resources?type=vm` — returns all VMs/templates with `vmid`, `name`, `node`, `template`, `status` fields. Filter client-side where `template == 1`.

## Acceptance Criteria

- `proxmox_url`, `proxmox_token_id`, `proxmox_token_secret` remain `required_config`.
- Missing `node` logs a formatted table of available nodes and raises `Kitchen::UserError`.
- Missing `template_id` logs a formatted table of templates (VMID, name, node) and raises `Kitchen::UserError`.
- Both missing shows both lists.
- Existing behaviour is unchanged when both are provided.
