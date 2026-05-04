# frozen_string_literal: true

require 'spec_helper'
require 'kitchen/driver/proxmox/errors'

RSpec.describe Kitchen::Driver::ProxmoxErrors::ApiError do
  describe '#vmid_conflict?' do
    it 'returns true for 400 with "already exists"' do
      err = described_class.new(400, '{"errors":{"newid":"VM 113 already exists"},"data":null}')
      expect(err.vmid_conflict?).to be true
    end

    it 'returns true for 500 with "already exists"' do
      err = described_class.new(500, '{"message":"VM 113 already exists on node pve\\n","data":null}')
      expect(err.vmid_conflict?).to be true
    end

    it 'returns true for "unable to create VM" pattern' do
      err = described_class.new(500, '{"message":"unable to create VM 113 - already exists\\n","data":null}')
      expect(err.vmid_conflict?).to be true
    end

    it 'returns true for lock file timeout (concurrent clone race)' do
      err = described_class.new(500,
                                '{"data":null,"message":"can\'t lock file \'/var/lock/qemu-server/lock-116.conf\' - got timeout\\n"}')
      expect(err.vmid_conflict?).to be true
    end

    it 'returns false for auth errors' do
      err = described_class.new(401, '{"errors":{"username":"invalid credentials"}}')
      expect(err.vmid_conflict?).to be false
    end

    it 'returns false for unrelated 500 errors' do
      err = described_class.new(500, '{"message":"storage not found\\n","data":null}')
      expect(err.vmid_conflict?).to be false
    end

    it 'returns false for 400 without conflict text' do
      err = described_class.new(400, '{"errors":{"net0":"hotplug problem"}}')
      expect(err.vmid_conflict?).to be false
    end
  end

  describe '#vmid_race_lost?' do
    it 'returns true for "already running"' do
      err = described_class.new(500, '{"data":null,"message":"VM 113 already running\\n"}')
      expect(err.vmid_race_lost?).to be true
    end

    it 'returns true for "hotplug problem"' do
      err = described_class.new(400,
                                '{"data":null,"errors":{"net0":"hotplug problem - error on hot-unplugging device \'net0\'\\n"},"message":"Parameter verification failed.\\n"}')
      expect(err.vmid_race_lost?).to be true
    end

    it 'returns true for "does not exist"' do
      err = described_class.new(500,
                                '{"message":"Configuration file \'nodes/um890/qemu-server/113.conf\' does not exist\\n","data":null}')
      expect(err.vmid_race_lost?).to be true
    end

    it 'returns true for lock file timeout' do
      err = described_class.new(500, "can't lock file '/var/lock/qemu-server/lock-113.conf' - got timeout")
      expect(err.vmid_race_lost?).to be true
    end

    it 'returns false for unrelated errors' do
      err = described_class.new(500, '{"message":"storage not found\\n","data":null}')
      expect(err.vmid_race_lost?).to be false
    end

    it 'returns false for auth errors' do
      err = described_class.new(401, '{"errors":{"username":"invalid credentials"}}')
      expect(err.vmid_race_lost?).to be false
    end
  end

  describe '#message' do
    it 'includes status code and body' do
      err = described_class.new(500, 'Internal Server Error')
      expect(err.message).to eq('Proxmox API error 500: Internal Server Error')
    end
  end

  describe '#status_code' do
    it 'returns integer status code' do
      err = described_class.new('404', 'Not Found')
      expect(err.status_code).to eq(404)
    end
  end
end
