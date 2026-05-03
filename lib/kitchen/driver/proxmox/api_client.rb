# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'openssl'
require 'kitchen'
require_relative 'errors'

module Kitchen
  module Driver
    class Proxmox < Kitchen::Driver::Base
      # HTTP client for the Proxmox VE REST API.
      # Authenticates via API tokens. Provides convenience
      # methods for VM lifecycle operations.
      class ApiClient
        attr_reader :base_url, :token_id, :token_secret, :ssl_verify

        def initialize(base_url:, token_id:, token_secret:, ssl_verify: true)
          @base_url = base_url.chomp('/')
          @token_id = token_id
          @token_secret = token_secret
          @ssl_verify = ssl_verify
        end

        def next_vm_id
          get('/api2/json/cluster/nextid')
        end

        def clone_vm(node:, template_id:, new_id:, **options)
          full = options.fetch(:full, true)
          body = { newid: new_id, full: full ? 1 : 0, target: node }
          body[:name] = options[:name] if options[:name]
          body[:pool] = options[:pool] if options[:pool]
          body[:storage] = options[:storage] if options[:storage]
          post("/api2/json/nodes/#{node}/qemu/#{template_id}/clone", body)
        end

        def configure_vm(node:, vm_id:, cpus: nil, memory: nil, network_bridge: nil)
          body = {}
          body[:cores] = cpus if cpus
          body[:memory] = memory if memory
          body[:net0] = "virtio,bridge=#{network_bridge}" if network_bridge
          return nil if body.empty?

          put("/api2/json/nodes/#{node}/qemu/#{vm_id}/config", body)
        end

        def start_vm(node:, vm_id:)
          post("/api2/json/nodes/#{node}/qemu/#{vm_id}/status/start")
        end

        def stop_vm(node:, vm_id:)
          post("/api2/json/nodes/#{node}/qemu/#{vm_id}/status/stop")
        end

        def destroy_vm(node:, vm_id:, purge: true)
          params = purge ? { purge: 1 } : {}
          delete("/api2/json/nodes/#{node}/qemu/#{vm_id}", params)
        end

        def vm_status(node:, vm_id:)
          get("/api2/json/nodes/#{node}/qemu/#{vm_id}/status/current")
        end

        def vm_config(node:, vm_id:)
          get("/api2/json/nodes/#{node}/qemu/#{vm_id}/config")
        end

        def task_status(node:, upid:)
          encoded = URI.encode_www_form_component(upid)
          get("/api2/json/nodes/#{node}/tasks/#{encoded}/status")
        end

        def wait_for_task(node:, upid:, timeout: 300, interval: 2)
          deadline = Time.now + timeout
          loop do
            status = task_status(node:, upid:)
            return status if status['status'] == 'stopped'
            raise "Task timeout after #{timeout}s: #{upid}" if Time.now > deadline

            sleep interval
          end
        end

        def agent_network_interfaces(node:, vm_id:)
          get("/api2/json/nodes/#{node}/qemu/#{vm_id}/agent/network-get-interfaces")
        end

        def list_nodes
          get('/api2/json/nodes')
        end

        def list_templates
          resources = get('/api2/json/cluster/resources?type=vm')
          resources.select { |r| r['template'] == 1 }
        end

        private

        def get(path)
          request(Net::HTTP::Get, path)
        end

        def post(path, body = {})
          request(Net::HTTP::Post, path, body)
        end

        def put(path, body = {})
          request(Net::HTTP::Put, path, body)
        end

        def delete(path, params = {})
          uri = URI.parse("#{base_url}#{path}")
          uri.query = URI.encode_www_form(params) unless params.empty?
          http = build_http(uri)
          req = Net::HTTP::Delete.new(uri.request_uri)
          apply_headers(req)
          handle_response(http.request(req))
        end

        def request(method_class, path, body = nil)
          uri = URI.parse("#{base_url}#{path}")
          http = build_http(uri)
          req = method_class.new(uri.request_uri)
          apply_headers(req)

          if body && !body.empty? && req.respond_to?(:body=)
            req['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(body)
          end

          handle_response(http.request(req))
        end

        def build_http(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.verify_mode = ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
          http
        end

        def apply_headers(req)
          req['Authorization'] = "PVEAPIToken=#{token_id}=#{token_secret}"
          req['Accept'] = 'application/json'
        end

        def handle_response(response)
          raise ProxmoxErrors::ApiError.new(response.code, response.body) unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)['data']
        end
      end
    end
  end
end
