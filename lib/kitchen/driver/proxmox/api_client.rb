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
      #
      # Supports multiple API URLs for failover. On connection
      # errors the client tries the next URL. Once a URL works
      # it becomes the sticky preference for subsequent calls.
      class ApiClient
        CONNECTION_ERRORS = [
          Errno::ECONNREFUSED,
          Errno::ECONNRESET,
          Errno::ETIMEDOUT,
          Errno::EHOSTUNREACH,
          Net::OpenTimeout,
          Net::ReadTimeout,
          SocketError,
          OpenSSL::SSL::SSLError
        ].freeze

        attr_reader :base_urls, :token_id, :token_secret, :ssl_verify, :connect_timeout

        # Accepts either base_url (String) or base_urls (Array).
        # The String form is normalized to a one-element array.
        def initialize(token_id:, token_secret:, base_url: nil, base_urls: nil, ssl_verify: true, connect_timeout: 10)
          urls = base_urls || Array(base_url)
          @base_urls = urls.map { |u| u.chomp('/') }
          @token_id = token_id
          @token_secret = token_secret
          @ssl_verify = ssl_verify
          @connect_timeout = connect_timeout
          @preferred_url_index = nil
        end

        # Backward-compat reader: returns the first (or preferred) URL.
        def base_url
          @base_urls[@preferred_url_index || 0]
        end

        def next_vm_id
          get('/api2/json/cluster/nextid')
        end

        def validate_vmid(vm_id)
          get("/api2/json/cluster/nextid?vmid=#{vm_id}")
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
            if status['status'] == 'stopped'
              exitstatus = status['exitstatus'].to_s
              raise ProxmoxErrors::ApiError.new(500, exitstatus) unless exitstatus == 'OK'

              return status
            end
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
          with_failover do |url|
            uri = URI.parse("#{url}#{path}")
            uri.query = URI.encode_www_form(params) unless params.empty?
            http = build_http(uri)
            req = Net::HTTP::Delete.new(uri.request_uri)
            apply_headers(req)
            handle_response(http.request(req))
          end
        end

        def request(method_class, path, body = nil)
          with_failover do |url|
            uri = URI.parse("#{url}#{path}")
            http = build_http(uri)
            req = method_class.new(uri.request_uri)
            apply_headers(req)

            if body && !body.empty? && req.respond_to?(:body=)
              req['Content-Type'] = 'application/x-www-form-urlencoded'
              req.body = URI.encode_www_form(body)
            end

            handle_response(http.request(req))
          end
        end

        # Tries the preferred URL first, then all others in order.
        # On connection errors, advances to the next URL.
        # On success, sets the working URL as preferred.
        def with_failover
          urls_to_try = failover_order
          failures = []

          urls_to_try.each_with_index do |url, idx|
            return yield(url).tap { @preferred_url_index = @base_urls.index(url) }
          rescue *CONNECTION_ERRORS => e
            failures << [url, e]
            # Reset preference if the preferred URL just failed
            @preferred_url_index = nil if idx.zero? && @preferred_url_index
          end

          msg = "All Proxmox API URLs failed:\n"
          failures.each { |url, err| msg += "  #{url}: #{err.class} - #{err.message}\n" }
          raise ProxmoxErrors::ApiError.new(0, msg)
        end

        # Returns URLs ordered with preferred first, then the rest.
        def failover_order
          return @base_urls unless @preferred_url_index

          preferred = @base_urls[@preferred_url_index]
          [preferred] + @base_urls.reject { |u| u == preferred }
        end

        def build_http(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.verify_mode = ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
          http.open_timeout = @connect_timeout
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
