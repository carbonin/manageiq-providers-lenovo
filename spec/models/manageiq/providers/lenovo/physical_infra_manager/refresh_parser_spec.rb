describe ManageIQ::Providers::Lenovo::PhysicalInfraManager::RefreshParser do
  before(:all) do
    vcr_path = File.dirname(described_class.name.underscore)
    options = {:allow_playback_repeats => true}

    VCR.insert_cassette("#{vcr_path}/mock_aicc", options)
    VCR.insert_cassette("#{vcr_path}/mock_cabinet", options)
    VCR.insert_cassette("#{vcr_path}/mock_config_patterns", options)
    VCR.insert_cassette("#{vcr_path}/mock_switches", options)
    VCR.insert_cassette("#{vcr_path}/mock_compliance_policy", options)
  end
  after(:all) do
    while VCR.cassettes.last
      VCR.eject_cassette
    end
  end

  let(:auth) do
    FactoryGirl.create(:authentication,
                       :userid   => "admin",
                       :password => "password",
                       :authtype => "default")
  end

  let(:ems) do
    ems = FactoryGirl.create(:physical_infra,
                             :name      => "LXCA",
                             :hostname  => "10.243.9.123",
                             :port      => "443",
                             :ipaddress => "https://10.243.9.123/443")
    ems.authentications = [auth]
    ems
  end

  let(:ems_inv_to_hashes) { described_class.new(ems).ems_inv_to_hashes }

  it 'will return its miq_template_type' do
    expect(described_class.miq_template_type).to eq("ManageIQ::Providers::Lenovo::PhysicalInfraManager::Template")
  end

  context "parse physical switches" do
    before do
      @result = ems_inv_to_hashes
    end

    it 'will retrieve physical switches' do
      expect(@result[:physical_switches].size).to eq(1)
    end

    it 'will retrieve switch details from physical switches' do
      switch = @result[:physical_switches].first

      expect(switch[:name]).to eq("ThinkAgile-VX-NE1032-SW03")
      expect(switch[:uid_ems]).to eq("00000000000010008000A48CDB984B00")
      expect(switch[:switch_uuid]).to eq("00000000000010008000A48CDB984B00")
      expect(switch[:health_state]).to eq("Valid")
      expect(switch[:power_state]).to eq("on")
      expect(switch[:asset_detail][:product_name]).to eq("Lenovo ThinkSystem NE1032 RackSwitch")
    end

    it 'will retrieve a port from physical switches' do
      switch = @result[:physical_switches].first
      port   = switch[:hardware][:guest_devices].first

      expect(port[:peer_mac_address]).to eq("7c:d3:0a:e6:47:51")
      expect(port[:device_type]).to eq("physical_port")
      expect(port[:vlan_enabled]).to eq(true)
      expect(port[:vlan_key]).to eq("\"Lenovo-Network-VLAN546\"")
    end

    it 'will retrieve a firmware from physical switches' do
      switch   = @result[:physical_switches].first
      firmware = switch[:hardware][:firmwares].first

      expect(firmware[:name]).to eq("Uboot-N/A")
      expect(firmware[:version]).to eq("10.4.2.0")
    end

    it 'will retrieve network details from physical switches' do
      switch       = @result[:physical_switches].first
      hardware     = switch[:hardware]
      network_ipv4 = hardware[:networks].first
      network_ipv6 = hardware[:networks].second

      expect(network_ipv4[:subnet_mask]).to eq("127.0.0.1")
      expect(network_ipv4[:default_gateway]).to eq("0.0.0.0")
      expect(network_ipv4[:ipaddress]).to eq("10.243.4.79")
      expect(network_ipv6[:ipv6address]).to eq("fe80:0:0:0:a68c:dbff:fe98:4b00")
    end
  end

  context 'parse physical servers' do
    before do
      @result = ems_inv_to_hashes
      physical_server = @result[:physical_servers].second
      computer_system = physical_server[:computer_system]
      @hardware = computer_system[:hardware]
    end

    it 'will retrieve physical servers' do
      expect(@result[:physical_servers].size).to eq(2)
    end

    it 'will retrieve addin cards on the physical servers' do
      guest_device = @hardware[:guest_devices][0]

      expect(guest_device[:device_name]).to eq("Broadcom 2-port 1GbE NIC Card for IBM")
      expect(guest_device[:device_type]).to eq("ethernet")
      expect(guest_device[:firmwares][0][:name]).to eq("Primary 17.4.4.2a-Active")
      expect(guest_device[:firmwares][0][:version]).to eq("17.4.4.2a")
      expect(guest_device[:manufacturer]).to eq("IBM")
      expect(guest_device[:field_replaceable_unit]).to eq("90Y9373")
      expect(guest_device[:location]).to eq("Bay 7")

      child_device = guest_device[:child_devices][0]

      expect(child_device[:address]).to eq("00:0A:F7:25:67:38")
      expect(child_device[:device_type]).to eq("physical_port")
      expect(child_device[:device_name]).to eq("Physical Port 1")
    end

    it 'will retrieve storage device' do
      storage_device = @hardware[:guest_devices].second

      expect(storage_device[:device_name]).to eq("ServeRAID M5210")
      expect(storage_device[:device_type]).to eq("storage")
      expect(storage_device[:manufacturer]).to eq("IBM")
      expect(storage_device[:location]).to eq("Bay 12")
    end

    %i(
      field_replaceable_unit
      contact
      location
      room
      rack_name
    ).each do |attr|
      it "will retrieve nil for #{attr} if parsed data is an empty string" do
        asset_detail = @result[:physical_servers].first[:asset_detail]
        expect(asset_detail[attr]).to be(nil)
      end
    end

    %i(
      product_name
      manufacturer
      machine_type
      model
      serial_number
      description
      lowest_rack_unit
    ).each do |attr|
      it "will retrieve #{attr} of asset detail" do
        asset_detail = @result[:physical_servers].first[:asset_detail]
        expect(asset_detail[attr]).to_not be(nil)
      end
    end

    it 'will retrieve compliance policy information from a physical server' do
      ph1 = @result[:physical_servers][0]
      ph2 = @result[:physical_servers][1]

      expect(ph2[:ems_compliance_name]).to eq('No policy assigned')
      expect(ph2[:ems_compliance_status]).to eq('None')
      expect(ph1[:ems_compliance_name]).to eq('policy1')
      expect(ph1[:ems_compliance_status]).to eq('Compliant')
    end

    it 'will retrieve the amout of memory in MB' do
      physical_server = @result[:physical_servers][1]
      memory_amount = physical_server[:computer_system][:hardware][:memory_mb]
      expect(memory_amount).to eq(16_384)
    end

    it 'will retrieve disk capacity from a physical server' do
      physical_server_with_disk = @result[:physical_servers][1]
      computer_system = physical_server_with_disk[:computer_system]
      hardware = computer_system[:hardware]

      expect(hardware[:disk_capacity]).to eq(300_000_000_000)
    end

    it 'will try to retrieve disk capacity from a physical server without RAID information' do
      physical_server = @result[:physical_servers][0]
      computer_system = physical_server[:computer_system]
      hardware = computer_system[:hardware]

      expect(hardware[:disk_capacity]).to be_nil
    end
  end

  context 'retrieve physical rack info' do
    let(:result) do
      VCR.use_cassette("#{described_class.name.underscore}_ems_inv_to_hashes") do
        ems_inv_to_hashes
      end
    end

    it 'will retrieve physical racks' do
      expect(result[:physical_racks].size).to eq(1)
    end

    it 'will retrieve physical racks fields' do
      physical_rack = result[:physical_racks].first

      expect(physical_rack[:uid_ems]).to eq('096F8C92-08D4-4A24-ABD8-FE56D482F8C4')
      expect(physical_rack[:name]).to eq('cabinet71')
    end

    it 'will retrieve physical server with rack' do
      physical_rack = result[:physical_racks].first
      physical_server = result[:physical_servers][1]

      expect(physical_server[:physical_rack]).to be_truthy
      expect(physical_server[:physical_rack][:ems_ref]).to eq(physical_rack[:ems_ref])
    end
  end

  context 'parse config patterns' do
    before do
      @result = ems_inv_to_hashes
    end

    it 'will retrieve config patterns' do
      config_pattern1 = @result[:customization_scripts][0]
      config_pattern2 = @result[:customization_scripts][1]
      expect(config_pattern1[:manager_ref]).to eq("65")
      expect(config_pattern1[:name]).to eq("17dspncsvdm-config")
      expect(config_pattern1[:in_use]).to eq(false)
      expect(config_pattern2[:manager_ref]).to eq("54")
      expect(config_pattern2[:name]).to eq("DaAn")
      expect(config_pattern2[:in_use]).to eq(false)
    end
  end
end
