# frozen_string_literal: true

require 'kitchen'
require 'securerandom'
require_relative 'proxmox_version'
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

      required_config :proxmox_url
      required_config :proxmox_token_id
      required_config :proxmox_token_secret
      default_config :node, nil
      default_config :template_id, nil

      default_config :ssl_verify, true
      default_config :pool, nil
      default_config :vm_name_prefix, 'kitchen-'
      default_config :cpus, 1
      default_config :memory, 1024
      default_config :storage, nil
      default_config :network_bridge, 'vmbr0'
      default_config :clone_timeout, 300
      default_config :start_timeout, 300
      default_config :ip_wait_timeout, 120

      def create(state)
        return if state[:vm_id]

        validate_config!
        clone_and_start(state)
      end

      def destroy(state)
        return unless state[:vm_id]

        vm_id = state[:vm_id]
        info("Destroying Proxmox VM #{state[:vm_name]} (#{vm_id})...")
        safe_stop_vm(vm_id)
        api_client.destroy_vm(node: config[:node], vm_id:)
        clear_state(state)
        info("Proxmox VM #{vm_id} destroyed.")
      end

      private

      def api_client
        @api_client ||= ApiClient.new(
          base_url: config[:proxmox_url],
          token_id: config[:proxmox_token_id],
          token_secret: config[:proxmox_token_secret],
          ssl_verify: config[:ssl_verify]
        )
      end

      def clone_and_start(state)
        info("Creating Proxmox VM from template #{config[:template_id]}...")

        vm_id = allocate_vm_id
        vm_name = generate_vm_name(instance.name)

        clone_template(vm_id, vm_name)
        configure_hardware(vm_id)
        start_and_wait_for_ip(state, vm_id)

        state[:vm_id] = vm_id
        state[:vm_name] = vm_name

        info("Proxmox VM #{vm_name} (#{vm_id}) created.")
      end

      def allocate_vm_id
        Integer(api_client.next_vm_id)
      end

      def generate_vm_name(suite_name)
        "#{config[:vm_name_prefix]}#{suite_name}-#{SecureRandom.hex(4)}"
      end

      def clone_template(vm_id, vm_name)
        node = config[:node]
        upid = api_client.clone_vm(
          node:, template_id: config[:template_id],
          new_id: vm_id, name: vm_name,
          pool: config[:pool], storage: config[:storage]
        )
        api_client.wait_for_task(node:, upid:, timeout: config[:clone_timeout])
      end

      def configure_hardware(vm_id)
        api_client.configure_vm(
          node: config[:node],
          vm_id:,
          cpus: config[:cpus],
          memory: config[:memory],
          network_bridge: config[:network_bridge]
        )
      end

      def start_and_wait_for_ip(state, vm_id)
        api_client.start_vm(node: config[:node], vm_id:)
        ip = wait_for_ip(vm_id)
        state[:hostname] = ip
      end

      def stop_vm(vm_id)
        status = api_client.vm_status(node: config[:node], vm_id:)
        return unless status['status'] == 'running'

        upid = api_client.stop_vm(node: config[:node], vm_id:)
        api_client.wait_for_task(node: config[:node], upid:, timeout: 60)
      end

      def safe_stop_vm(vm_id)
        stop_vm(vm_id)
      rescue ::StandardError => e
        warn("Failed to stop VM #{vm_id}: #{e.message}")
      end

      def wait_for_ip(vm_id)
        deadline = Time.now + config[:ip_wait_timeout]
        loop do
          ip = fetch_ip(vm_id)
          return ip if ip
          raise "Timed out waiting for IP on VM #{vm_id}" if Time.now > deadline

          sleep 3
        end
      end

      def fetch_ip(vm_id)
        interfaces = api_client.agent_network_interfaces(
          node: config[:node],
          vm_id:
        )
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
        errors << validate_node if config[:node].nil?
        errors << validate_template_id if config[:template_id].nil?
        return if errors.empty?

        raise Kitchen::UserError, errors.join("\n\n")
      end

      def validate_node
        msg = "Missing required config: node\n"
        begin
          nodes = api_client.list_nodes
          msg += "Available Proxmox nodes:\n"
          nodes.each { |n| msg += "  - #{n['node']} (#{n['status']})\n" }
        rescue ::StandardError
          msg += "  (could not retrieve node list from Proxmox API)\n"
        end
        msg
      end

      def validate_template_id
        msg = "Missing required config: template_id\n"
        msg + format_template_list
      end

      def format_template_list
        templates = api_client.list_templates
        return "  No templates found on the Proxmox cluster.\n" if templates.empty?

        lines = "Available templates:\n"
        templates.each { |t| lines += "  - #{t['vmid']}: #{t['name']} (node: #{t['node']})\n" }
        lines
      rescue ::StandardError
        "  (could not retrieve template list from Proxmox API)\n"
      end

      def clear_state(state)
        state.delete(:vm_id)
        state.delete(:vm_name)
        state.delete(:hostname)
      end
    end
  end
end
