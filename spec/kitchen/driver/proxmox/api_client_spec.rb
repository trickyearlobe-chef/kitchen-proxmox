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
    allow(http).to receive(:open_timeout=)
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

  describe '#validate_vmid' do
    it 'returns the validated VMID when it is available' do
      allow(http).to receive(:request).and_return(json_response('900001'))
      expect(client.validate_vmid(900_001)).to eq('900001')
    end

    it 'raises ApiError when the VMID is already taken' do
      allow(http).to receive(:request).and_return(error_response('400', 'VM 900001 already exists'))
      expect { client.validate_vmid(900_001) }
        .to raise_error(Kitchen::Driver::ProxmoxErrors::ApiError)
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

    it 'raises ApiError when task exits with error' do
      stopped = json_response({ 'status' => 'stopped',
                                'exitstatus' => "can't lock file '/var/lock/qemu-server/lock-113.conf' - got timeout" })
      allow(http).to receive(:request).and_return(stopped)

      upid = 'UPID:pve:00001234:00000000:12345678:qmclone:9000:user@pam:'
      expect { client.wait_for_task(node: 'pve', upid:, timeout: 10, interval: 0) }
        .to raise_error(Kitchen::Driver::ProxmoxErrors::ApiError, /can't lock file/)
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

  describe 'multi-URL failover' do
    let(:url1) { 'https://pve1.example.com:8006' }
    let(:url2) { 'https://pve2.example.com:8006' }
    let(:url3) { 'https://pve3.example.com:8006' }

    let(:multi_client) do
      described_class.new(
        base_urls: [url1, url2, url3],
        token_id:,
        token_secret:,
        ssl_verify: false,
        connect_timeout: 5
      )
    end

    let(:http1) { instance_double(Net::HTTP) }
    let(:http2) { instance_double(Net::HTTP) }
    let(:http3) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).with('pve1.example.com', 8006).and_return(http1)
      allow(Net::HTTP).to receive(:new).with('pve2.example.com', 8006).and_return(http2)
      allow(Net::HTTP).to receive(:new).with('pve3.example.com', 8006).and_return(http3)
      [http1, http2, http3].each do |h|
        allow(h).to receive(:use_ssl=)
        allow(h).to receive(:verify_mode=)
        allow(h).to receive(:open_timeout=)
      end
    end

    describe '#initialize with base_urls' do
      it 'accepts an array of URLs' do
        expect(multi_client.base_urls).to eq([url1, url2, url3])
      end

      it 'normalizes a single base_url string to a one-element array' do
        c = described_class.new(base_url: url1, token_id:, token_secret:)
        expect(c.base_urls).to eq([url1])
      end

      it 'strips trailing slashes from all URLs' do
        c = described_class.new(
          base_urls: ["#{url1}/", "#{url2}/"],
          token_id:,
          token_secret:
        )
        expect(c.base_urls).to eq([url1, url2])
      end

      it 'stores connect_timeout' do
        expect(multi_client.connect_timeout).to eq(5)
      end

      it 'defaults connect_timeout to 10' do
        c = described_class.new(base_url: url1, token_id:, token_secret:)
        expect(c.connect_timeout).to eq(10)
      end
    end

    describe 'connection failover' do
      it 'uses the first URL when it works' do
        allow(http1).to receive(:request).and_return(json_response('100'))
        expect(multi_client.next_vm_id).to eq('100')
      end

      it 'falls over to second URL when first refuses connection' do
        allow(http1).to receive(:request).and_raise(Errno::ECONNREFUSED)
        allow(http2).to receive(:request).and_return(json_response('100'))
        expect(multi_client.next_vm_id).to eq('100')
      end

      it 'falls over to third URL when first two time out' do
        allow(http1).to receive(:request).and_raise(Net::OpenTimeout)
        allow(http2).to receive(:request).and_raise(Errno::ETIMEDOUT)
        allow(http3).to receive(:request).and_return(json_response('100'))
        expect(multi_client.next_vm_id).to eq('100')
      end

      it 'falls over on SocketError (DNS failure)' do
        allow(http1).to receive(:request).and_raise(SocketError, 'getaddrinfo: Name does not resolve')
        allow(http2).to receive(:request).and_return(json_response('100'))
        expect(multi_client.next_vm_id).to eq('100')
      end

      it 'falls over on OpenSSL::SSL::SSLError' do
        allow(http1).to receive(:request).and_raise(OpenSSL::SSL::SSLError, 'SSL_connect returned=1')
        allow(http2).to receive(:request).and_return(json_response('100'))
        expect(multi_client.next_vm_id).to eq('100')
      end

      it 'does NOT fail over on HTTP 4xx/5xx errors' do
        allow(http1).to receive(:request).and_return(error_response('401', 'unauthorized'))
        expect { multi_client.next_vm_id }
          .to raise_error(Kitchen::Driver::ProxmoxErrors::ApiError, /401/)
      end

      it 'raises with all failures when every URL is unreachable' do
        allow(http1).to receive(:request).and_raise(Errno::ECONNREFUSED)
        allow(http2).to receive(:request).and_raise(Net::OpenTimeout)
        allow(http3).to receive(:request).and_raise(SocketError, 'Name does not resolve')
        expect { multi_client.next_vm_id }
          .to raise_error(Kitchen::Driver::ProxmoxErrors::ApiError, /All Proxmox API URLs failed/)
      end

      it 'includes each URL and its error in the all-failed message' do
        allow(http1).to receive(:request).and_raise(Errno::ECONNREFUSED)
        allow(http2).to receive(:request).and_raise(Net::OpenTimeout)
        allow(http3).to receive(:request).and_raise(SocketError, 'Name does not resolve')
        expect { multi_client.next_vm_id }
          .to raise_error(Kitchen::Driver::ProxmoxErrors::ApiError, /pve1.*pve2.*pve3/m)
      end
    end

    describe 'sticky preference' do
      it 'reuses the last working URL on subsequent calls' do
        # First call: url1 fails, url2 works
        allow(http1).to receive(:request).and_raise(Errno::ECONNREFUSED)
        allow(http2).to receive(:request).and_return(json_response('100'))
        multi_client.next_vm_id

        # Second call: should go straight to url2
        expect(http1).not_to receive(:request)
        allow(http2).to receive(:request).and_return(json_response('101'))
        expect(multi_client.next_vm_id).to eq('101')
      end

      it 'resets sticky preference when the preferred URL fails' do
        # First call: url1 fails, url2 works → sticky to url2
        allow(http1).to receive(:request).and_raise(Errno::ECONNREFUSED).once
        allow(http2).to receive(:request).and_return(json_response('100')).once
        multi_client.next_vm_id

        # Second call: url2 now fails, should try all from start
        allow(http1).to receive(:request).and_return(json_response('101'))
        allow(http2).to receive(:request).and_raise(Errno::ECONNREFUSED)
        expect(multi_client.next_vm_id).to eq('101')
      end
    end

    describe 'connect_timeout' do
      it 'sets open_timeout on the HTTP connection' do
        expect(http1).to receive(:open_timeout=).with(5)
        allow(http1).to receive(:request).and_return(json_response('100'))
        multi_client.next_vm_id
      end
    end
  end
end
