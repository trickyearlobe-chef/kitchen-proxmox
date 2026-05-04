# frozen_string_literal: true

require 'spec_helper'
require 'kitchen/driver/proxmox'

RSpec.describe Kitchen::Driver::Proxmox do
  let(:driver_config) do
    {
      proxmox_url: 'https://proxmox.example.com:8006',
      proxmox_token_id: 'user@pam!token-name',
      proxmox_token_secret: '00000000-0000-0000-0000-000000000000',
      node: 'pve',
      template_id: 9000
    }
  end

  let(:kitchen_instance) do
    instance_double(
      'Kitchen::Instance',
      name: 'default-ubuntu-2204',
      to_str: 'default-ubuntu-2204',
      logger: Kitchen.logger
    )
  end

  subject(:driver) do
    d = described_class.new(driver_config)
    allow(d).to receive(:instance).and_return(kitchen_instance)
    d
  end

  describe 'configuration' do
    let(:validations) { described_class.instance_variable_get(:@validations) }

    it 'declares proxmox_url as required' do
      expect(validations).to have_key(:proxmox_url)
    end

    it 'declares proxmox_token_id as required' do
      expect(validations).to have_key(:proxmox_token_id)
    end

    it 'declares proxmox_token_secret as required' do
      expect(validations).to have_key(:proxmox_token_secret)
    end

    it 'defaults node to nil' do
      d = described_class.new(driver_config.reject { |k| k == :node })
      allow(d).to receive(:instance).and_return(kitchen_instance)
      expect(d[:node]).to be_nil
    end

    it 'defaults template_id to nil' do
      d = described_class.new(driver_config.reject { |k| k == :template_id })
      allow(d).to receive(:instance).and_return(kitchen_instance)
      expect(d[:template_id]).to be_nil
    end

    it 'defaults ssl_verify to true' do
      expect(driver[:ssl_verify]).to eq(true)
    end

    it 'defaults vm_name_prefix to kitchen-' do
      expect(driver[:vm_name_prefix]).to eq('kitchen-')
    end

    it 'defaults cpus to 1' do
      expect(driver[:cpus]).to eq(1)
    end

    it 'defaults memory to 1024' do
      expect(driver[:memory]).to eq(1024)
    end

    it 'defaults network_bridge to vmbr0' do
      expect(driver[:network_bridge]).to eq('vmbr0')
    end

    it 'defaults pool to nil' do
      expect(driver[:pool]).to be_nil
    end

    it 'defaults storage to nil' do
      expect(driver[:storage]).to be_nil
    end

    it 'defaults vmid_range_min to 900000' do
      expect(driver[:vmid_range_min]).to eq(900_000)
    end

    it 'defaults vmid_range_max to 999999' do
      expect(driver[:vmid_range_max]).to eq(999_999)
    end

    it 'defaults node_pool to nil' do
      expect(driver[:node_pool]).to be_nil
    end

    it 'defaults connect_timeout to 10' do
      expect(driver[:connect_timeout]).to eq(10)
    end
  end

  describe 'helpful validation' do
    let(:api_client) { instance_double(Kitchen::Driver::Proxmox::ApiClient) }

    before do
      allow(driver).to receive(:api_client).and_return(api_client)
    end

    context 'when template_id is missing' do
      let(:driver_config) { super().merge(template_id: nil) }

      it 'lists available templates and raises Kitchen::UserError' do
        allow(api_client).to receive(:list_templates).and_return(
          [{ 'vmid' => 9000, 'name' => 'ubuntu-2204', 'node' => 'pve' }]
        )
        expect { driver.create({}) }.to raise_error(Kitchen::UserError, /template_id/)
      end

      it 'includes template VMID and name in the error message' do
        allow(api_client).to receive(:list_templates).and_return(
          [{ 'vmid' => 9000, 'name' => 'ubuntu-2204', 'node' => 'pve' },
           { 'vmid' => 9001, 'name' => 'debian-12', 'node' => 'pve' }]
        )
        expect { driver.create({}) }.to raise_error(Kitchen::UserError, /9000.*ubuntu-2204.*9001.*debian-12/m)
      end
    end

    context 'when API call fails during validation' do
      let(:driver_config) { super().merge(template_id: nil) }

      it 'still raises a useful error without the list' do
        allow(api_client).to receive(:list_templates).and_raise(StandardError, 'connection refused')
        expect { driver.create({}) }.to raise_error(Kitchen::UserError, /template_id/)
      end
    end
  end

  describe 'node auto-selection' do
    let(:api_client) { instance_double(Kitchen::Driver::Proxmox::ApiClient) }
    let(:driver_config) { super().merge(node: nil) }

    before do
      allow(driver).to receive(:api_client).and_return(api_client)
      allow(api_client).to receive(:validate_vmid).and_return('900001')
      allow(driver).to receive(:rand).and_return(900_001)
      allow(api_client).to receive(:clone_vm).and_return('UPID:pve1:clone')
      allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      allow(api_client).to receive(:configure_vm)
      allow(api_client).to receive(:start_vm)
      allow(api_client).to receive(:agent_network_interfaces).and_return(
        { 'result' => [
          { 'name' => 'eth0', 'ip-addresses' => [{ 'ip-address' => '10.0.0.5', 'ip-address-type' => 'ipv4' }] }
        ] }
      )
    end

    it 'selects node with least memory allocation ratio' do
      allow(api_client).to receive(:list_nodes).and_return([
        { 'node' => 'pve1', 'status' => 'online', 'mem' => 80_000, 'maxmem' => 100_000 },
        { 'node' => 'pve2', 'status' => 'online', 'mem' => 20_000, 'maxmem' => 100_000 }
      ])
      state = {}
      driver.create(state)
      expect(state[:node]).to eq('pve2')
    end

    it 'skips offline nodes' do
      allow(api_client).to receive(:list_nodes).and_return([
        { 'node' => 'pve1', 'status' => 'offline', 'mem' => 1000, 'maxmem' => 100_000 },
        { 'node' => 'pve2', 'status' => 'online', 'mem' => 50_000, 'maxmem' => 100_000 }
      ])
      state = {}
      driver.create(state)
      expect(state[:node]).to eq('pve2')
    end

    it 'uses pinned node from config when set' do
      d = described_class.new(driver_config.merge(node: 'pinned-node'))
      allow(d).to receive(:instance).and_return(kitchen_instance)
      allow(d).to receive(:api_client).and_return(api_client)
      state = {}
      d.create(state)
      expect(state[:node]).to eq('pinned-node')
    end

    it 'uses previously resolved node from state' do
      allow(api_client).to receive(:list_nodes).and_return([
        { 'node' => 'pve1', 'status' => 'online', 'mem' => 50_000, 'maxmem' => 100_000 }
      ])
      state = { node: 'already-resolved' }
      # Should not re-resolve since it's in state. But state[:vm_id] is nil so create runs.
      # Actually state[:node] presence alone doesn't skip create. Let me adjust:
      # The driver only skips create if state[:vm_id] is set.
      # resolve_node should return state[:node] if present.
      driver.create(state)
      expect(state[:node]).to eq('already-resolved')
    end

    context 'with node_pool' do
      let(:driver_config) { super().merge(node_pool: %w[pve2 pve3]) }

      it 'restricts selection to pooled nodes' do
        allow(api_client).to receive(:list_nodes).and_return([
          { 'node' => 'pve1', 'status' => 'online', 'mem' => 1000, 'maxmem' => 100_000 },
          { 'node' => 'pve2', 'status' => 'online', 'mem' => 50_000, 'maxmem' => 100_000 },
          { 'node' => 'pve3', 'status' => 'online', 'mem' => 30_000, 'maxmem' => 100_000 }
        ])
        state = {}
        driver.create(state)
        expect(state[:node]).to eq('pve3')
      end

      it 'raises Kitchen::UserError when all pooled nodes are offline' do
        allow(api_client).to receive(:list_nodes).and_return([
          { 'node' => 'pve1', 'status' => 'online', 'mem' => 1000, 'maxmem' => 100_000 },
          { 'node' => 'pve2', 'status' => 'offline', 'mem' => 0, 'maxmem' => 100_000 },
          { 'node' => 'pve3', 'status' => 'offline', 'mem' => 0, 'maxmem' => 100_000 }
        ])
        state = {}
        expect { driver.create(state) }.to raise_error(Kitchen::UserError, /no online nodes/i)
      end
    end

    it 'raises Kitchen::UserError when no nodes are online' do
      allow(api_client).to receive(:list_nodes).and_return([
        { 'node' => 'pve1', 'status' => 'offline', 'mem' => 0, 'maxmem' => 100_000 }
      ])
      state = {}
      expect { driver.create(state) }.to raise_error(Kitchen::UserError, /no online nodes/i)
    end

    it 'stores the selected node in state for destroy' do
      allow(api_client).to receive(:list_nodes).and_return([
        { 'node' => 'pve1', 'status' => 'online', 'mem' => 50_000, 'maxmem' => 100_000 }
      ])
      state = {}
      driver.create(state)
      expect(state[:node]).to eq('pve1')
    end
  end

  describe '#create' do
    let(:api_client) { instance_double(Kitchen::Driver::Proxmox::ApiClient) }

    before do
      allow(driver).to receive(:api_client).and_return(api_client)
      allow(api_client).to receive(:validate_vmid).and_return('900001')
      allow(driver).to receive(:rand).and_return(900_001)
      allow(api_client).to receive(:clone_vm).and_return('UPID:pve:clone')
      allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      allow(api_client).to receive(:configure_vm)
      allow(api_client).to receive(:start_vm)
      allow(api_client).to receive(:agent_network_interfaces).and_return(
        { 'result' => [
          { 'name' => 'lo', 'ip-addresses' => [{ 'ip-address' => '127.0.0.1', 'ip-address-type' => 'ipv4' }] },
          { 'name' => 'eth0', 'ip-addresses' => [{ 'ip-address' => '10.0.0.5', 'ip-address-type' => 'ipv4' }] }
        ] }
      )
    end

    it 'skips if vm_id already present in state' do
      state = { vm_id: 100 }
      expect(api_client).not_to receive(:validate_vmid)
      driver.create(state)
    end

    it 'allocates a VM ID' do
      state = {}
      driver.create(state)
      expect(state[:vm_id]).to eq(900_001)
    end

    it 'clones the template' do
      state = {}
      expect(api_client).to receive(:clone_vm).with(
        hash_including(node: 'pve', template_id: 9000, new_id: 900_001)
      )
      driver.create(state)
    end

    it 'waits for the clone task' do
      state = {}
      expect(api_client).to receive(:wait_for_task).with(
        hash_including(node: 'pve', upid: 'UPID:pve:clone')
      ).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      driver.create(state)
    end

    it 'configures hardware' do
      state = {}
      expect(api_client).to receive(:configure_vm).with(
        hash_including(node: 'pve', vm_id: 900_001, cpus: 1, memory: 1024, network_bridge: 'vmbr0')
      )
      driver.create(state)
    end

    it 'starts the VM' do
      state = {}
      expect(api_client).to receive(:start_vm).with(node: 'pve', vm_id: 900_001)
      driver.create(state)
    end

    it 'waits for an IP and stores hostname in state' do
      state = {}
      driver.create(state)
      expect(state[:hostname]).to eq('10.0.0.5')
    end

    it 'generates a vm_name with prefix and unix timestamp suffix' do
      state = {}
      driver.create(state)
      expect(state[:vm_name]).to match(/\Akitchen-default-ubuntu-2204-\d{10,}\z/)
    end

    context 'VMID conflict retry' do
      let(:conflict_error) do
        Kitchen::Driver::Proxmox::ApiError.new(400, '{"errors":{"newid":"VM 900001 already exists"}}')
      end

      before do
        allow(driver).to receive(:sleep)
        allow(driver).to receive(:rand).with(900_000..999_999).and_return(900_001, 900_002, 900_003, 900_004, 900_005)
        allow(driver).to receive(:rand).with(0.0..1.0).and_return(0.5)
      end

      it 'retries with a new VMID on conflict' do
        allow(api_client).to receive(:validate_vmid)
        allow(api_client).to receive(:clone_vm) do |**args|
          raise conflict_error if args[:new_id] == 900_001

          'UPID:pve:clone'
        end

        state = {}
        driver.create(state)
        expect(state[:vm_id]).to eq(900_002)
      end

      it 'persists vm_id immediately after successful clone' do
        allow(api_client).to receive(:configure_vm).and_raise('hardware config failed')
        state = {}
        expect { driver.create(state) }.to raise_error(/hardware config failed/)
        expect(state[:vm_id]).to eq(900_001)
      end

      it 'raises after exhausting retries' do
        allow(api_client).to receive(:clone_vm).and_raise(conflict_error)
        allow(api_client).to receive(:validate_vmid).and_return('900001')
        state = {}
        expect { driver.create(state) }.to raise_error(Kitchen::Driver::Proxmox::ApiError, /already exists/)
      end

      it 'does not retry on non-conflict errors' do
        auth_error = Kitchen::Driver::Proxmox::ApiError.new(401, 'unauthorized')
        allow(api_client).to receive(:clone_vm).and_raise(auth_error)
        state = {}
        expect(api_client).to receive(:validate_vmid).once
        expect { driver.create(state) }.to raise_error(Kitchen::Driver::Proxmox::ApiError, /unauthorized/)
      end

      it 'uses exponential backoff with jitter between retries' do
        allow(api_client).to receive(:validate_vmid)
        allow(api_client).to receive(:clone_vm) do |**args|
          raise conflict_error if args[:new_id] < 900_003

          'UPID:pve:clone'
        end

        state = {}
        expect(driver).to receive(:sleep).at_least(:twice)
        driver.create(state)
      end
    end

    context 'VMID race recovery' do
      let(:race_error) do
        Kitchen::Driver::Proxmox::ApiError.new(500, '{"data":null,"message":"VM 900001 already running\\n"}')
      end

      before do
        allow(driver).to receive(:sleep)
        allow(driver).to receive(:rand).with(900_000..999_999).and_return(900_001, 900_002, 900_003, 900_004, 900_005)
        allow(driver).to receive(:rand).with(0.0..1.0).and_return(0.5)
      end

      it 'retries from scratch when start detects race loss' do
        allow(api_client).to receive(:validate_vmid)
        allow(api_client).to receive(:clone_vm).and_return('UPID:pve:clone')
        allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
        allow(api_client).to receive(:configure_vm)

        start_call_count = 0
        allow(api_client).to receive(:start_vm) do
          start_call_count += 1
          raise race_error if start_call_count == 1

          'UPID:pve:start'
        end

        state = {}
        driver.create(state)
        expect(state[:vm_id]).to eq(900_002)
      end

      it 'retries from scratch when configure detects hotplug race' do
        hotplug_error = Kitchen::Driver::Proxmox::ApiError.new(
          400, '{"errors":{"net0":"hotplug problem - error on hot-unplugging device \'net0\'\\n"}}'
        )

        allow(api_client).to receive(:validate_vmid)
        allow(api_client).to receive(:clone_vm).and_return('UPID:pve:clone')
        allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
        allow(api_client).to receive(:start_vm).and_return('UPID:pve:start')

        configure_call_count = 0
        allow(api_client).to receive(:configure_vm) do
          configure_call_count += 1
          raise hotplug_error if configure_call_count == 1
        end

        state = {}
        driver.create(state)
        expect(state[:vm_id]).to eq(900_002)
      end

      it 'clears state before retrying so destroy does not target wrong VM' do
        allow(api_client).to receive(:validate_vmid)
        allow(api_client).to receive(:clone_vm).and_return('UPID:pve:clone')
        allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
        allow(api_client).to receive(:configure_vm)

        start_call_count = 0
        allow(api_client).to receive(:start_vm) do
          start_call_count += 1
          raise race_error if start_call_count == 1

          'UPID:pve:start'
        end

        state = {}
        driver.create(state)
        # Final state should be the second VM, not the first
        expect(state[:vm_id]).to eq(900_002)
        expect(state[:vm_name]).to match(/kitchen-/)
      end
    end
  end

  describe '#destroy' do
    let(:api_client) { instance_double(Kitchen::Driver::Proxmox::ApiClient) }

    before do
      allow(driver).to receive(:api_client).and_return(api_client)
    end

    it 'skips if no vm_id in state' do
      state = {}
      expect(api_client).not_to receive(:destroy_vm)
      driver.destroy(state)
    end

    it 'stops and destroys the VM' do
      state = { vm_id: 200, vm_name: 'kitchen-test-abc123', hostname: '10.0.0.5' }
      allow(api_client).to receive(:vm_status).and_return({ 'status' => 'running' })
      allow(api_client).to receive(:stop_vm).and_return('UPID:pve:stop')
      allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      expect(api_client).to receive(:destroy_vm).with(node: 'pve', vm_id: 200)
      driver.destroy(state)
    end

    it 'clears state after destroy' do
      state = { vm_id: 200, vm_name: 'kitchen-test-abc123', hostname: '10.0.0.5' }
      allow(api_client).to receive(:vm_status).and_return({ 'status' => 'running' })
      allow(api_client).to receive(:stop_vm).and_return('UPID:pve:stop')
      allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      allow(api_client).to receive(:destroy_vm)
      driver.destroy(state)
      expect(state).not_to have_key(:vm_id)
      expect(state).not_to have_key(:vm_name)
      expect(state).not_to have_key(:hostname)
    end

    it 'continues destroy even if stop fails' do
      state = { vm_id: 200, vm_name: 'kitchen-test-abc123', hostname: '10.0.0.5' }
      allow(api_client).to receive(:vm_status).and_raise('connection refused')
      expect(api_client).to receive(:destroy_vm).with(node: 'pve', vm_id: 200)
      driver.destroy(state)
    end

    it 'uses state[:node] when node was auto-selected' do
      d = described_class.new(driver_config.merge(node: nil))
      allow(d).to receive(:instance).and_return(kitchen_instance)
      allow(d).to receive(:api_client).and_return(api_client)
      state = { vm_id: 200, vm_name: 'kitchen-test-abc123', hostname: '10.0.0.5', node: 'auto-selected-node' }
      allow(api_client).to receive(:vm_status).and_return({ 'status' => 'running' })
      allow(api_client).to receive(:stop_vm).and_return('UPID:auto-selected-node:stop')
      allow(api_client).to receive(:wait_for_task).and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      expect(api_client).to receive(:destroy_vm).with(node: 'auto-selected-node', vm_id: 200)
      d.destroy(state)
    end
  end
end
