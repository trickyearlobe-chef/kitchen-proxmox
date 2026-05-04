# Cluster Awareness

Three related features that make the driver work well in multi-node Proxmox clusters.

## Feature 1: Automatic Node Selection

### Problem

The `node` config is currently required. In a cluster the user shouldn't need to hard-code a single node — the driver should pick one automatically.

### Behaviour

- When `node` is omitted (nil), the driver queries `GET /api2/json/nodes` and selects a target node.
- Selection strategy: **least-allocated memory** among nodes with `status == "online"`.
- The `node` config remains available to pin a specific node. When set, no selection occurs.
- A new optional config `node_pool` (Array of Strings) restricts auto-selection to named nodes. Nodes not online are excluded from the pool.
- If `node_pool` is set but all listed nodes are offline, raise `Kitchen::UserError` with the statuses.
- The selected node is stored in `state[:node]` for use in subsequent operations (destroy, etc.).
- The template must be accessible from the selected node. If the template lives on a different node, the clone API's `target` parameter handles cross-node cloning automatically.

### Config

| Key | Type | Default | Description |
|---|---|---|---|
| `node` | String | `nil` | Pin to a specific node (bypasses selection) |
| `node_pool` | Array | `nil` | Restrict auto-selection to these node names |

### API Endpoints Used

- `GET /api2/json/nodes` — returns `[{node, status, mem, maxmem, cpu, maxcpu, ...}]`
- Clone's `target` parameter routes the new VM to the selected node.

## Feature 2: Multi-URL Failover

### Problem

Each Proxmox node runs its own API server. If the single configured URL's node goes down, the driver can't reach the cluster even though other nodes are up.

### Behaviour

- `proxmox_url` accepts a String (single URL) or an Array of Strings (multiple URLs). The driver normalizes to an array internally via `Array(config[:proxmox_url])`.
- On each API call, the client tries URLs in order. If a connection fails (timeout, refused, DNS error), it tries the next URL. Non-connection HTTP errors (4xx, 5xx) are NOT retried on a different URL — those indicate a real API problem.
- Connection timeout per URL: 10 seconds (configurable via `connect_timeout`).
- Once a working URL is found, it becomes the "preferred" URL for subsequent calls in that session (sticky). If it later fails, failover resumes from the full list.
- All URLs must point to the same Proxmox cluster (same auth credentials work on all).

### Config

| Key | Type | Default | Description |
|---|---|---|---|
| `proxmox_url` | String or Array | (required) | One or more Proxmox API base URLs |
| `connect_timeout` | Integer | `10` | Per-URL connection timeout in seconds |

### Kitchen YAML Examples

Single node:
```yaml
driver:
  proxmox_url: https://pve1.example.com:8006
```

Multiple nodes (failover):
```yaml
driver:
  proxmox_url:
    - https://pve1.example.com:8006
    - https://pve2.example.com:8006
```

### Error Semantics

- Connection errors: `Errno::ECONNREFUSED`, `Errno::ETIMEDOUT`, `Net::OpenTimeout`, `SocketError`, `OpenSSL::SSL::SSLError` (cert errors when host is wrong).
- If ALL URLs fail, raise `ApiError` with a message listing each URL and its failure reason.

## Feature 3: Template Lookup by Name

### Problem

Template VMIDs are opaque numbers that differ across clusters. Users prefer to reference templates by their human-readable name (e.g. `alma10-template`).

### Behaviour

- A new config `template_name` (String) resolves a template by its Proxmox VM name.
- Exactly one of `template_id` or `template_name` must be set. If both are set, raise `Kitchen::UserError`. If neither is set, raise with the existing helpful template list.
- Resolution: query `GET /api2/json/cluster/resources?type=vm`, filter for `template == 1` and `name == template_name`.
- If zero matches: raise `Kitchen::UserError` listing available templates.
- If multiple matches (same name on different nodes): use the one on the selected target node. If none is on the target node, use the first match (clone API handles cross-node).
- The resolved VMID is stored in `state[:template_id]` for idempotency — subsequent operations don't re-resolve.
- Template resolution happens AFTER node selection so node affinity can influence the choice.

### Config

| Key | Type | Default | Description |
|---|---|---|---|
| `template_id` | Integer | `nil` | Template VMID (existing) |
| `template_name` | String | `nil` | Template name to resolve |

### API Endpoints Used

- `GET /api2/json/cluster/resources?type=vm` — returns `[{vmid, name, node, template, status, ...}]`

## Interaction Between Features

1. Multi-URL failover is established first (ApiClient layer).
2. Node selection happens next (uses the working API connection).
3. Template resolution happens last (needs the selected node for affinity).

## Backward Compatibility

- All new configs are optional with nil defaults.
- `proxmox_url` continues to accept a plain String — existing configs work unchanged.
- Existing configs (`proxmox_url`, `node`, `template_id`) remain fully valid.
- A `.kitchen.yml` with only the existing fields requires no changes.
