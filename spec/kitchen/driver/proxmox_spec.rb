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

    it 'declares node as required' do
      expect(validations).to have_key(:node)
    end

    it 'declares template_id as required' do
      expect(validations).to have_key(:template_id)
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
  end

  describe '#create' do
    let(:api_client) { instance_double(Kitchen::Driver::Proxmox::ApiClient) }

    before do
      allow(driver).to receive(:api_client).and_return(api_client)
      allow(api_client).to receive(:next_vm_id).and_return('200')
      allow(api_client).to receive(:clone_vm).and_return('UPID:pve:clone')
      allow(api_client).to receive(:wait_for_task)
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
      expect(api_client).not_to receive(:next_vm_id)
      driver.create(state)
    end

    it 'allocates a VM ID' do
      state = {}
      driver.create(state)
      expect(state[:vm_id]).to eq(200)
    end

    it 'clones the template' do
      state = {}
      expect(api_client).to receive(:clone_vm).with(
        hash_including(node: 'pve', template_id: 9000, new_id: 200)
      )
      driver.create(state)
    end

    it 'waits for the clone task' do
      state = {}
      expect(api_client).to receive(:wait_for_task).with(
        hash_including(node: 'pve', upid: 'UPID:pve:clone')
      )
      driver.create(state)
    end

    it 'configures hardware' do
      state = {}
      expect(api_client).to receive(:configure_vm).with(
        hash_including(node: 'pve', vm_id: 200, cpus: 1, memory: 1024, network_bridge: 'vmbr0')
      )
      driver.create(state)
    end

    it 'starts the VM' do
      state = {}
      expect(api_client).to receive(:start_vm).with(node: 'pve', vm_id: 200)
      driver.create(state)
    end

    it 'waits for an IP and stores hostname in state' do
      state = {}
      driver.create(state)
      expect(state[:hostname]).to eq('10.0.0.5')
    end

    it 'generates a vm_name with prefix and random suffix' do
      state = {}
      driver.create(state)
      expect(state[:vm_name]).to match(/\Akitchen-default-ubuntu-2204-[0-9a-f]{8}\z/)
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
      allow(api_client).to receive(:wait_for_task)
      expect(api_client).to receive(:destroy_vm).with(node: 'pve', vm_id: 200)
      driver.destroy(state)
    end

    it 'clears state after destroy' do
      state = { vm_id: 200, vm_name: 'kitchen-test-abc123', hostname: '10.0.0.5' }
      allow(api_client).to receive(:vm_status).and_return({ 'status' => 'running' })
      allow(api_client).to receive(:stop_vm).and_return('UPID:pve:stop')
      allow(api_client).to receive(:wait_for_task)
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
  end
end
