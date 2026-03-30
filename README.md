# kitchen-proxmox

A [Test Kitchen](https://kitchen.ci/) driver for [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment/overview). Creates and destroys VMs by cloning templates via the Proxmox REST API.

## Requirements

- [Chef Workstation](https://docs.chef.io/workstation/) (provides Ruby, Test Kitchen, and all dependencies)
- Proxmox VE 7+ with API token authentication
- A VM template to clone (with `qemu-guest-agent` installed for IP detection)

## Installation

```sh
chef exec gem install kitchen-proxmox
```

## Configuration

Add the driver to your `.kitchen.yml`:

```yaml
driver:
  name: proxmox
  proxmox_url: https://proxmox.example.com:8006
  proxmox_token_id: kitchen@pam!kitchen-token
  proxmox_token_secret: 00000000-0000-0000-0000-000000000000
  node: pve
  template_id: 9000
```

To avoid committing secrets, you can use ERB to inject them from environment variables. Test Kitchen processes `.kitchen.yml` as ERB before parsing the YAML:

```yaml
driver:
  name: proxmox
  proxmox_url: https://proxmox.example.com:8006
  proxmox_token_id: <%= ENV['PROXMOX_TOKEN_ID'] %>
  proxmox_token_secret: <%= ENV['PROXMOX_TOKEN_SECRET'] %>
  node: pve
  template_id: 9000
```

Then export the variables before running Kitchen:

```sh
export PROXMOX_TOKEN_ID='kitchen@pam!kitchen-token'
export PROXMOX_TOKEN_SECRET='00000000-0000-0000-0000-000000000000'
kitchen converge
```

You can also put the exports in a `.envrc` (if using [direnv](https://direnv.net/)) or a `.env` file sourced by your shell. Add these files to `.gitignore` so secrets are never committed.

### Required Settings

| Key | Description |
|---|---|
| `proxmox_url` | Proxmox API URL (e.g. `https://host:8006`) |
| `proxmox_token_id` | API token ID (`user@realm!token-name`) |
| `proxmox_token_secret` | API token secret (UUID) |
| `node` | Proxmox node to create VMs on |
| `template_id` | VM ID of the template to clone |

### Optional Settings

| Key | Default | Description |
|---|---|---|
| `ssl_verify` | `true` | Verify TLS certificates |
| `pool` | `nil` | Proxmox resource pool |
| `vm_name_prefix` | `kitchen-` | Prefix for generated VM names |
| `cpus` | `1` | Number of CPU cores |
| `memory` | `1024` | Memory in MB |
| `storage` | `nil` | Target storage for the clone |
| `network_bridge` | `vmbr0` | Network bridge for the VM |
| `clone_timeout` | `300` | Seconds to wait for clone task |
| `start_timeout` | `300` | Seconds to wait for VM start |
| `ip_wait_timeout` | `120` | Seconds to wait for guest IP |

## Proxmox Setup

### Create a Role

1. Go to **Datacenter → Permissions → Roles** and click **Create**.
2. Name the role (e.g. `KitchenDriver`).
3. Select these privileges:
   - `VM.Allocate`, `VM.Clone`, `VM.Audit`, `VM.PowerMgmt`
   - `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Disk`, `VM.Config.Network`
   - `Datastore.AllocateSpace`, `Datastore.Audit`
   - `Pool.Allocate` (only if you use the `pool` config option)
4. Click **Create**.

### Create a User (optional)

You can use an existing user or create a dedicated one:

1. Go to **Datacenter → Permissions → Users** and click **Add**.
2. Set **User name** (e.g. `kitchen`), **Realm** to `pam` or `pve`, and a password.
3. Click **Add**.

### Create an API Token

1. Go to **Datacenter → Permissions → API Tokens** and click **Add**.
2. Select the user, set a **Token ID** (e.g. `kitchen-token`).
3. **Uncheck** "Privilege Separation" — the token inherits the user's permissions.
4. Click **Add** and copy the displayed secret. It is shown only once.

The resulting token ID for `.kitchen.yml` is `kitchen@pam!kitchen-token`.

### Assign Permissions

1. Go to **Datacenter → Permissions** and click **Add → User Permission**.
2. Set **Path** to `/` (or scope to `/vms` and `/storage` as needed).
3. Select the user and the `KitchenDriver` role.
4. Check **Propagate**.
5. Click **Add**.

### Template

The template VM must have `qemu-guest-agent` installed and enabled. The driver uses the guest agent to detect the VM's IP address after boot.

## Development

```sh
make spec    # run tests
make style   # run rubocop
make         # run both
make install # build and install the gem
```

## License

Apache-2.0
