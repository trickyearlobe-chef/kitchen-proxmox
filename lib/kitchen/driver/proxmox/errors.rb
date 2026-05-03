# frozen_string_literal: true

module Kitchen
  module Driver
    module ProxmoxErrors
      # Structured error raised by ApiClient on non-2xx responses.
      class ApiError < ::StandardError
        attr_reader :status_code, :response_body

        def initialize(status_code, response_body)
          @status_code = status_code.to_i
          @response_body = response_body
          super("Proxmox API error #{status_code}: #{response_body}")
        end

        # Returns true when the error indicates a VMID is already in use.
        def vmid_conflict?
          return false unless status_code == 400 || status_code == 500

          response_body.match?(/already exists/i) ||
            response_body.match?(/unable to create VM \d+/i)
        end
      end
    end
  end
end
