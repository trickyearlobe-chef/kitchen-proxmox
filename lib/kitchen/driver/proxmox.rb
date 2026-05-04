# frozen_string_literal: true

require 'kitchen'
require_relative 'proxmox_version'
require_relative 'proxmox/errors'
require_relative 'proxmox/api_client'

module Kitchen
  module Driver
    # Proxmox VE driver for Test Kitchen.
    #
    # Manages VM lifecycle via the Proxmox REST API:
    # - create: clone a template, configure hardware, start, wait for IP
    # - destroy: stop and delete the VM
    class Proxmox < Kitchen::Driver::Base
      kitchen_driver_api_version 2

      plugin_version Kitchen::Driver::PROXMOX_VERSION

      ApiError = Kitchen::Driver::ProxmoxErrors::ApiError

      required_config :proxmox_url
      required_config :proxmox_token_id
      required_config :proxmox_token_secret
      default_config :node, nil
      default_config :node_pool, nil
      default_config :template_id, nil
      default_config :template_name, nil

      default_config :ssl_verify, true
      default_config :connect_timeout, 10
      default_config :pool, nil
      default_config :vm_name_prefix, 'kitchen-'
      default_config :cpus, 1
      default_config :memory, 1024
      default_config :storage, nil
      default_config :network_bridge, 'vmbr0'
      default_config :clone_timeout, 300
      default_config :start_timeout, 300
      default_config :ip_wait_timeout, 120
      default_config :clone_retries, 5
      default_config :vmid_range_min, 900_000
      default_config :vmid_range_max, 999_999

      def create(state)
        return if state[:vm_id]

        resolve_node(state)
        resolve_template(state)
        validate_config!
        clone_and_start(state)
      end

      def destroy(state)
        return unless state[:vm_id]

        vm_id = state[:vm_id]
        node = state[:node] || config[:node]
        info("Destroying Proxmox VM #{state[:vm_name]} (#{vm_id})...")
        safe_stop_vm(node, vm_id)
        api_client.destroy_vm(node:, vm_id:)
        clear_state(state)
        info("Proxmox VM #{vm_id} destroyed.")
      end

      private

      def api_client
        @api_client ||= ApiClient.new(
          base_urls: Array(config[:proxmox_url]).map(&:to_s),
          token_id: config[:proxmox_token_id],
          token_secret: config[:proxmox_token_secret],
          ssl_verify: config[:ssl_verify],
          connect_timeout: config[:connect_timeout]
        )
      end

      def clone_and_start(state)
        retries = config[:clone_retries]
        last_error = nil
        node = state[:node]
        template_id = state[:template_id] || config[:template_id]

        retries.times do |attempt|
          info("Creating Proxmox VM from template #{template_id}...")

          vm_id, vm_name = allocate_and_clone(node, template_id)
          state[:vm_id] = vm_id
          state[:vm_name] = vm_name

          begin
            configure_hardware(node, vm_id)
            start_and_wait_for_ip(state, node, vm_id)
            info("Proxmox VM #{vm_name} (#{vm_id}) created.")
            return
          rescue ApiError => e
            raise unless e.vmid_race_lost?

            last_error = e
            warn("VMID #{vm_id} race lost (attempt #{attempt + 1}/#{retries}): #{e.message}")
            warn("Another process owns VM #{vm_id} — abandoning and retrying...")
            clear_state(state)
            state[:node] = node
            sleep backoff_delay(attempt)
          end
        end

        raise last_error
      end

      def allocate_and_clone(node, template_id)
        retries = config[:clone_retries]
        last_error = nil

        retries.times do |attempt|
          vm_id = allocate_vm_id
          vm_name = generate_vm_name(instance.name)

          begin
            clone_template(node, vm_id, vm_name, template_id)
            return [vm_id, vm_name]
          rescue ApiError => e
            raise unless e.vmid_conflict?

            last_error = e
            warn("VMID #{vm_id} conflict (attempt #{attempt + 1}/#{retries}), retrying...")
            sleep backoff_delay(attempt)
          end
        end

        raise last_error
      end

      def backoff_delay(attempt)
        (0.5 * (2**attempt)) + rand(0.0..1.0)
      end

      def allocate_vm_id
        vm_id = rand(config[:vmid_range_min]..config[:vmid_range_max])
        api_client.validate_vmid(vm_id)
        vm_id
      end

      def generate_vm_name(suite_name)
        "#{config[:vm_name_prefix]}#{suite_name}-#{Time.now.to_i}"
      end

      def clone_template(node, vm_id, vm_name, template_id)
        upid = api_client.clone_vm(
          node:, template_id:,
          new_id: vm_id, name: vm_name,
          pool: config[:pool], storage: config[:storage]
        )
        api_client.wait_for_task(node:, upid:, timeout: config[:clone_timeout])
      end

      def configure_hardware(node, vm_id)
        api_client.configure_vm(
          node:,
          vm_id:,
          cpus: config[:cpus],
          memory: config[:memory],
          network_bridge: config[:network_bridge]
        )
      end

      def start_and_wait_for_ip(state, node, vm_id)
        api_client.start_vm(node:, vm_id:)
        ip = wait_for_ip(node, vm_id)
        state[:hostname] = ip
      end

      def stop_vm(node, vm_id)
        status = api_client.vm_status(node:, vm_id:)
        return unless status['status'] == 'running'

        upid = api_client.stop_vm(node:, vm_id:)
        api_client.wait_for_task(node:, upid:, timeout: 60)
      end

      def safe_stop_vm(node, vm_id)
        stop_vm(node, vm_id)
      rescue ::StandardError => e
        warn("Failed to stop VM #{vm_id}: #{e.message}")
      end

      def wait_for_ip(node, vm_id)
        deadline = Time.now + config[:ip_wait_timeout]
        loop do
          ip = fetch_ip(node, vm_id)
          return ip if ip
          raise "Timed out waiting for IP on VM #{vm_id}" if Time.now > deadline

          sleep 3
        end
      end

      def fetch_ip(node, vm_id)
        interfaces = api_client.agent_network_interfaces(node:, vm_id:)
        return nil unless interfaces.is_a?(Hash) && interfaces['result']

        extract_ipv4_from_interfaces(interfaces['result'])
      rescue ::StandardError
        nil
      end

      def extract_ipv4_from_interfaces(interfaces)
        interfaces.each do |iface|
          next if iface['name'] == 'lo'

          (iface['ip-addresses'] || []).each do |addr|
            return addr['ip-address'] if addr['ip-address-type'] == 'ipv4'
          end
        end
        nil
      end

      def validate_config!
        errors = []
        errors << 'Set template_id OR template_name, not both.' if config[:template_id] && config[:template_name]
        errors << validate_template_id if config[:template_id].nil? && config[:template_name].nil?
        return if errors.empty?

        raise Kitchen::UserError, errors.join("\n\n")
      end

      def resolve_template(state)
        # Already resolved (e.g. from a previous create attempt)
        return if state[:template_id]

        # If template_id is set in config, use it directly
        if config[:template_id]
          state[:template_id] = config[:template_id]
          return
        end

        # Resolve template_name to VMID
        return unless config[:template_name]

        templates = api_client.list_templates
        matches = templates.select { |t| t['name'] == config[:template_name] }

        if matches.empty?
          msg = "Template '#{config[:template_name]}' not found.\n#{format_template_list_from(templates)}"
          raise Kitchen::UserError, msg
        end

        # Prefer template on the target node
        node = state[:node]
        selected = matches.find { |t| t['node'] == node } || matches.first
        state[:template_id] = selected['vmid']
        info("Resolved template '#{config[:template_name]}' to VMID #{state[:template_id]}")
      end

      def resolve_node(state)
        # Use pinned node from config
        if config[:node]
          state[:node] = config[:node]
          return
        end

        # Use previously resolved node from state
        return if state[:node]

        # Auto-select: query cluster and pick least-loaded online node
        nodes = api_client.list_nodes
        candidates = nodes.select { |n| n['status'] == 'online' }

        # Filter by node_pool if set
        candidates = candidates.select { |n| config[:node_pool].include?(n['node']) } if config[:node_pool]

        if candidates.empty?
          statuses = nodes.map { |n| "  - #{n['node']} (#{n['status']})" }.join("\n")
          raise Kitchen::UserError, "No online nodes available. Node statuses:\n#{statuses}"
        end

        # Select by least memory allocation ratio
        selected = candidates.min_by { |n| n['mem'].to_f / n['maxmem'] }
        state[:node] = selected['node']
        info("Auto-selected node: #{state[:node]}")
      end

      def validate_template_id
        msg = "Missing required config: template_id or template_name\n"
        msg + format_template_list
      end

      def format_template_list
        templates = api_client.list_templates
        format_template_list_from(templates)
      rescue ::StandardError
        "  (could not retrieve template list from Proxmox API)\n"
      end

      def format_template_list_from(templates)
        return "  No templates found on the Proxmox cluster.\n" if templates.empty?

        lines = "Available templates:\n"
        templates.each { |t| lines += "  - #{t['vmid']}: #{t['name']} (node: #{t['node']})\n" }
        lines
      end

      def clear_state(state)
        state.delete(:vm_id)
        state.delete(:vm_name)
        state.delete(:hostname)
      end
    end
  end
end
