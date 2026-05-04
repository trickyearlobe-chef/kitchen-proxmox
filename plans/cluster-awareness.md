# Plan: Cluster Awareness

## Goal

Implement three features from `specifications/cluster-awareness.md`:
1. Multi-URL failover in ApiClient
2. Automatic node selection
3. Template lookup by name

## Specs to Read

- `specifications/cluster-awareness.md` (primary)
- `lib/kitchen/driver/proxmox/api_client.rb` (current API client)
- `lib/kitchen/driver/proxmox.rb` (current driver)

## Steps

### Phase 1: Multi-URL Failover (ApiClient layer)

1. Write specs for `ApiClient` failover behaviour in `spec/kitchen/driver/proxmox/api_client_spec.rb`
2. Add `connect_timeout` param to `ApiClient#initialize`
3. Accept `base_urls` (Array) in `ApiClient#initialize` — normalize `String | Array` to array
4. Implement connection-error retry across URLs with sticky preference
5. Add `connect_timeout` config to driver
6. Update driver's `api_client` method to normalize `config[:proxmox_url]` (String or Array) via `Array()` and pass as `base_urls`
7. Remove `required_config :proxmox_url` validation (Kitchen's built-in check doesn't understand Array — validate manually)

### Phase 2: Automatic Node Selection

1. Write specs for node selection logic in `spec/kitchen/driver/proxmox_spec.rb`
2. Add `node_pool` config to driver
3. Extract a `resolve_node(state)` private method that:
   - Returns `config[:node]` if set (pinned)
   - Returns `state[:node]` if already resolved
   - Queries `list_nodes`, filters by `node_pool` + online status
   - Selects by least memory allocation ratio (`mem / maxmem`)
   - Stores result in `state[:node]`
4. Update `clone_and_start` to call `resolve_node` before cloning
5. Update `destroy` to use `state[:node]` instead of `config[:node]`
6. Remove `node` from `validate_config!` required check (it's now auto-resolved)

### Phase 3: Template Lookup by Name

1. Write specs for template resolution in `spec/kitchen/driver/proxmox_spec.rb`
2. Add `template_name` config to driver
3. Extract a `resolve_template(state, node)` private method that:
   - Returns `config[:template_id]` if set
   - Returns `state[:template_id]` if already resolved
   - Queries `list_templates`, filters by name match
   - Prefers template on target node if multiple matches
   - Stores result in `state[:template_id]`
4. Validate mutual exclusivity of `template_id` / `template_name`
5. Update create flow: resolve_node → resolve_template → clone

### Phase 4: Integration and Cleanup

1. Update `validate_config!` for new mutual-exclusivity rules
2. Update README with new config options and examples
3. Run full spec suite, fix any failures
4. Run rubocop, fix style issues

## Acceptance Criteria

- `chef exec rspec` passes with all new and existing specs green
- `chef exec rubocop` passes
- Single-URL + pinned-node + template_id configs still work (backward compat)
- `proxmox_url` accepts a String or Array in `.kitchen.yml`
- Multi-URL config fails over when first URL is unreachable
- Omitting `node` triggers auto-selection by memory
- `node_pool` restricts selection to listed nodes
- `template_name: alma10-template` resolves to the correct VMID
- Both `template_id` and `template_name` set raises `Kitchen::UserError`
- `destroy` uses the node stored in state (not config) when node was auto-selected
