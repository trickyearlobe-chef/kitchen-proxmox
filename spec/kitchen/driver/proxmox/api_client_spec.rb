# frozen_string_literal: true

require 'spec_helper'
require 'kitchen/driver/proxmox/api_client'

RSpec.describe Kitchen::Driver::Proxmox::ApiClient do
  let(:base_url) { 'https://proxmox.example.com:8006' }
  let(:token_id) { 'user@pam!token-name' }
  let(:token_secret) { '00000000-0000-0000-0000-000000000000' }

  subject(:client) do
    described_class.new(
      base_url:,
      token_id:,
      token_secret:,
      ssl_verify: false
    )
  end

  let(:auth_header) { "PVEAPIToken=#{token_id}=#{token_secret}" }

  # Shared mock for Net::HTTP
  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:verify_mode=)
  end

  def json_response(data, code = '200')
    resp = instance_double(Net::HTTPOK, code:, body: JSON.generate({ 'data' => data }))
    allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(code == '200')
    resp
  end

  def error_response(code, body)
    resp = instance_double(Net::HTTPInternalServerError, code:, body:)
    allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    resp
  end

  describe '#initialize' do
    it 'stores connection settings' do
      expect(client.base_url).to eq(base_url)
      expect(client.token_id).to eq(token_id)
      expect(client.token_secret).to eq(token_secret)
      expect(client.ssl_verify).to eq(false)
    end

    it 'strips trailing slash from base_url' do
      c = described_class.new(
        base_url: 'https://proxmox.example.com:8006/',
        token_id:,
        token_secret:
      )
      expect(c.base_url).to eq('https://proxmox.example.com:8006')
    end

    it 'defaults ssl_verify to true' do
      c = described_class.new(
        base_url:,
        token_id:,
        token_secret:
      )
      expect(c.ssl_verify).to eq(true)
    end
  end

  describe '#next_vm_id' do
    it 'returns the next available VM ID' do
      allow(http).to receive(:request).and_return(json_response('100'))
      expect(client.next_vm_id).to eq('100')
    end
  end

  describe '#clone_vm' do
    it 'posts a clone request and returns the UPID' do
      upid = 'UPID:pve:00001234:00000000:12345678:qmclone:9000:user@pam:'
      allow(http).to receive(:request).and_return(json_response(upid))

      result = client.clone_vm(node: 'pve', template_id: 9000, new_id: 100, name: 'test-vm')
      expect(result).to include('UPID')
    end
  end

  describe '#configure_vm' do
    it 'puts hardware config' do
      allow(http).to receive(:request).and_return(json_response(nil))
      client.configure_vm(node: 'pve', vm_id: 100, cpus: 2, memory: 2048, network_bridge: 'vmbr0')
    end

    it 'skips the request when no options given' do
      expect(http).not_to receive(:request)
      expect(client.configure_vm(node: 'pve', vm_id: 100)).to be_nil
    end
  end

  describe '#start_vm' do
    it 'posts a start request' do
      upid = 'UPID:pve:00001234:00000000:12345678:qmstart:100:user@pam:'
      allow(http).to receive(:request).and_return(json_response(upid))

      result = client.start_vm(node: 'pve', vm_id: 100)
      expect(result).to include('UPID')
    end
  end

  describe '#stop_vm' do
    it 'posts a stop request' do
      upid = 'UPID:pve:00001234:00000000:12345678:qmstop:100:user@pam:'
      allow(http).to receive(:request).and_return(json_response(upid))

      result = client.stop_vm(node: 'pve', vm_id: 100)
      expect(result).to include('UPID')
    end
  end

  describe '#destroy_vm' do
    it 'sends a delete request with purge' do
      upid = 'UPID:pve:00001234:00000000:12345678:qmdestroy:100:user@pam:'
      allow(http).to receive(:request).and_return(json_response(upid))

      result = client.destroy_vm(node: 'pve', vm_id: 100)
      expect(result).to include('UPID')
    end
  end

  describe '#vm_status' do
    it 'returns VM status hash' do
      allow(http).to receive(:request).and_return(json_response({ 'status' => 'running', 'vmid' => 100 }))

      result = client.vm_status(node: 'pve', vm_id: 100)
      expect(result['status']).to eq('running')
    end
  end

  describe '#vm_config' do
    it 'returns VM config hash' do
      allow(http).to receive(:request).and_return(json_response({ 'cores' => 2, 'memory' => 2048 }))

      result = client.vm_config(node: 'pve', vm_id: 100)
      expect(result['cores']).to eq(2)
    end
  end

  describe '#task_status' do
    it 'returns task status' do
      allow(http).to receive(:request).and_return(json_response({ 'status' => 'stopped', 'exitstatus' => 'OK' }))

      upid = 'UPID:pve:00001234:00000000:12345678:qmclone:9000:user@pam:'
      result = client.task_status(node: 'pve', upid:)
      expect(result['status']).to eq('stopped')
    end
  end

  describe '#wait_for_task' do
    it 'polls until task is stopped' do
      running = json_response({ 'status' => 'running' })
      stopped = json_response({ 'status' => 'stopped', 'exitstatus' => 'OK' })
      allow(http).to receive(:request).and_return(running, stopped)
      allow(client).to receive(:sleep)

      upid = 'UPID:pve:00001234:00000000:12345678:qmclone:9000:user@pam:'
      result = client.wait_for_task(node: 'pve', upid:, timeout: 10, interval: 0)
      expect(result['status']).to eq('stopped')
    end

    it 'raises on timeout' do
      running = json_response({ 'status' => 'running' })
      allow(http).to receive(:request).and_return(running)
      allow(client).to receive(:sleep)

      upid = 'UPID:pve:00001234:00000000:12345678:qmclone:9000:user@pam:'
      expect { client.wait_for_task(node: 'pve', upid:, timeout: 0, interval: 0) }
        .to raise_error(/Task timeout/)
    end
  end

  describe '#agent_network_interfaces' do
    it 'returns interface data' do
      ifaces = { 'result' => [{ 'name' => 'eth0',
                                'ip-addresses' => [{ 'ip-address' => '10.0.0.5', 'ip-address-type' => 'ipv4' }] }] }
      allow(http).to receive(:request).and_return(json_response(ifaces))

      result = client.agent_network_interfaces(node: 'pve', vm_id: 100)
      expect(result['result'].first['name']).to eq('eth0')
    end
  end

  describe '#list_nodes' do
    it 'returns an array of node hashes' do
      nodes = [
        { 'node' => 'pve1', 'status' => 'online', 'cpu' => 0.05, 'maxcpu' => 4 },
        { 'node' => 'pve2', 'status' => 'online', 'cpu' => 0.12, 'maxcpu' => 8 }
      ]
      allow(http).to receive(:request).and_return(json_response(nodes))

      result = client.list_nodes
      expect(result.length).to eq(2)
      expect(result.first['node']).to eq('pve1')
    end
  end

  describe '#list_templates' do
    it 'returns only resources where template is 1' do
      resources = [
        { 'vmid' => 9000, 'name' => 'ubuntu-2204', 'node' => 'pve1', 'template' => 1, 'status' => 'stopped' },
        { 'vmid' => 100, 'name' => 'webserver', 'node' => 'pve1', 'template' => 0, 'status' => 'running' },
        { 'vmid' => 9001, 'name' => 'debian-12', 'node' => 'pve2', 'template' => 1, 'status' => 'stopped' }
      ]
      allow(http).to receive(:request).and_return(json_response(resources))

      result = client.list_templates
      expect(result.length).to eq(2)
      expect(result.map { |t| t['vmid'] }).to eq([9000, 9001])
    end

    it 'returns an empty array when no templates exist' do
      resources = [
        { 'vmid' => 100, 'name' => 'webserver', 'node' => 'pve1', 'template' => 0, 'status' => 'running' }
      ]
      allow(http).to receive(:request).and_return(json_response(resources))

      result = client.list_templates
      expect(result).to eq([])
    end
  end

  describe 'error handling' do
    it 'raises on non-success HTTP response' do
      allow(http).to receive(:request).and_return(error_response('500', 'Internal Server Error'))
      expect { client.next_vm_id }.to raise_error(/Proxmox API error 500/)
    end

    it 'raises on 401 unauthorized' do
      allow(http).to receive(:request).and_return(error_response('401',
                                                                 '{"errors":{"username":"invalid credentials"}}'))
      expect { client.next_vm_id }.to raise_error(/Proxmox API error 401/)
    end
  end
end
