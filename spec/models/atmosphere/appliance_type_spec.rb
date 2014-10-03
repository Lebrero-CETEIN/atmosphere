# == Schema Information
#
# Table name: appliance_types
#
#  id                 :integer          not null, primary key
#  name               :string(255)      not null
#  description        :text
#  shared             :boolean          default(FALSE), not null
#  scalable           :boolean          default(FALSE), not null
#  visible_to         :string(255)      default("owner"), not null
#  preference_cpu     :float
#  preference_memory  :integer
#  preference_disk    :integer
#  security_proxy_id  :integer
#  user_id            :integer
#  created_at         :datetime
#  updated_at         :datetime
#  metadata_global_id :string(255)
#

require 'rails_helper'

describe Atmosphere::ApplianceType do

  subject { FactoryGirl.create(:appliance_type) }

  it { should be_valid }

  it { should validate_presence_of :name }
  it { should validate_presence_of :visible_to }

  it { should validate_uniqueness_of :name }

  it { should ensure_inclusion_of(:visible_to).in_array(%w(owner developer all)) }

  it { should have_db_index(:name).unique(true) }

  [:preference_memory, :preference_disk, :preference_cpu].each do |attribute|
    it { should validate_numericality_of attribute }
    it { should_not allow_value(-1).for(attribute) }
  end


  it 'should set proper default values' do
    expect(subject.visible_to).to eql 'owner'
    expect(subject.shared).to eql false
    expect(subject.scalable).to eql false
  end

  it { should belong_to :security_proxy }
  it { should belong_to :author }
  it { should have_many :appliances }
  it { should have_many(:port_mapping_templates).dependent(:destroy) }
  it { should have_many(:appliance_configuration_templates).dependent(:destroy) }
  it { should have_many(:virtual_machine_templates) }

  context 'has virtual_machine_templates or appliances (aka "is used")' do
    let(:appliance_type) { create(:appliance_type) }
    let(:user)  { create(:user) }
    let(:appliance_set) { create(:appliance_set, user: user) }
    let!(:appliance) { create(:appliance, appliance_set: appliance_set, appliance_type: appliance_type) }

    it 'is valid' do
      expect(appliance_type).to be_valid
      expect(appliance_type.appliances).not_to be_empty
    end

    it 'has a proper dependencies detection' do
      expect(appliance_type.has_dependencies?).to be_truthy
    end

    it 'is not destroyable without force' do
      appliance_type.destroy
      expect(appliance_type.errors).not_to be_empty
    end
  end

  describe '#create_from' do
    let(:dev_set) { create(:dev_appliance_set) }
    let(:at) { create(:appliance_type) }
    let(:appl) { create(:appliance, appliance_type: at, appliance_set: dev_set) }
    let(:dev_props) { appl.dev_mode_property_set }

    it 'creates appliance type from appliance' do
      at = Atmosphere::ApplianceType.create_from(appl)
      expect(at.name).to eq(dev_props.name)
      expect(at.description).to eq(dev_props.description)
      expect(at.shared).to eq(dev_props.shared)
      expect(at.scalable).to eq(dev_props.scalable)
      expect(at.preference_cpu).to eq(dev_props.preference_cpu)
      expect(at.preference_memory).to eq(dev_props.preference_memory)
      expect(at.preference_disk).to eq(dev_props.preference_disk)
      expect(at.security_proxy).to eq(dev_props.security_proxy)
    end

    let(:overwrite) do
      {
        name: 'my name',
        description: 'desc',
        scalable: true,
        preference_memory: 1024,
        appliance_id: 23
      }
    end

    it 'overwrite data from appliance' do
      at = Atmosphere::ApplianceType.create_from(appl, overwrite)
      expect(at.name).to eq(overwrite[:name])
      expect(at.description).to eq(overwrite[:description])
      expect(at.scalable).to eq(overwrite[:scalable])
      expect(at.preference_memory).to eq(overwrite[:preference_memory])
    end

    context 'when port mappings, endpoints, properties defined' do
      let(:endpoint1) { build(:endpoint) }
      let(:endpoint2) { build(:endpoint) }

      let(:port_mapping_property1) { build(:pmt_property) }
      let(:port_mapping_property2) { build(:pmt_property) }

      let(:port_mapping1) { create(:port_mapping_template,
          endpoints: [endpoint1, endpoint2],
          port_mapping_properties: [
            port_mapping_property1,
            port_mapping_property2
          ]
        )
      }

      let(:port_mapping2) { create(:port_mapping_template) }

      let(:at_with_pmt) { create(:filled_appliance_type,
          port_mapping_templates: [port_mapping1, port_mapping2]
        )
      }

      let(:appl_with_pmt) { create(:appliance, appliance_type: at_with_pmt, appliance_set: dev_set) }
      let(:dev_props_with_pmt) { appl.dev_mode_property_set }

      it 'creates pmt, endpoints, properties copy' do
        at = Atmosphere::ApplianceType.create_from(appl_with_pmt, overwrite)
        expect(at.port_mapping_templates.length).to eq 2
        expect(at.port_mapping_templates[0].endpoints.length).to eq 2
        expect(at.port_mapping_templates[0].port_mapping_properties.length).to eq 2

        expect(at.port_mapping_templates[1].endpoints.length).to eq 0
        expect(at.port_mapping_templates[1].port_mapping_properties.length).to eq 0
      end
    end

    context 'when AT has appliance configuration templates' do
      let(:act1) { build(:appliance_configuration_template, name: 'act1') }
      let(:act2) { build(:appliance_configuration_template, name: 'act2') }

      before do
        at.appliance_configuration_templates << [act1, act2]
        appl.reload
      end

      it 'copies initial configuration templates' do
        at = Atmosphere::ApplianceType.create_from(appl, overwrite)

        init_confs = at.appliance_configuration_templates.sort {|x,y| x.name <=> y.name}

        expect(init_confs.size).to eq 2
        expect(init_confs[0].name).to eq act1.name
        expect(init_confs[0].payload).to eq act1.payload
        expect(init_confs[1].name).to eq act2.name
        expect(init_confs[1].payload).to eq act2.payload
      end
    end
  end

  describe 'as_metadata_xml' do
    let(:at) { create(:appliance_type) }
    let(:devel_at) { create(:appliance_type, visible_to: 'developer') }
    let(:evil_at) { create(:appliance_type, name: '</name></AtomicService>WE RULE!') }
    let(:user) { create(:user) }
    let(:owned_at) { create(:appliance_type, author: user) }
    let(:published_at) { create(:appliance_type, metadata_global_id: 'MDGLID') }
    let(:endp11) { build(:endpoint) }
    let(:endp12) { build(:endpoint, description: 'ENDP_DESC') }
    let(:endp21) { build(:endpoint) }
    let(:pmt1) { build(:port_mapping_template, endpoints: [endp11, endp12]) }
    let(:pmt2) { build(:port_mapping_template, endpoints: [endp21]) }
    let(:pmt3) { build(:port_mapping_template) }
    let(:complex_at) { create(:appliance_type, port_mapping_templates: [pmt1, pmt2, pmt3], description: 'DESC') }

    it 'creates minimal valid metadata xml document' do
      xml = at.as_metadata_xml.strip
      sleep 1
      expect(xml).to start_with('<resource_metadata>')
      expect(xml).to include('<atomicService>')
      expect(xml).to include('<name>'+at.name+'</name>')
      expect(xml).to include('<localID>'+at.id.to_s+'</localID>')
      expect(xml).to include('<author></author>')
      expect(xml).to include('<development>false</development>')
      expect(xml).to include('<description></description>')
      expect(xml).to include('<type>AtomicService</type>')
      expect(xml).to include('<category>None</category>')
      expect(xml).to include('<metadataUpdateDate>')
      expect(xml).to include('<metadataCreationDate>')
      update_time = Time.parse(xml.scan(/<metadataUpdateDate>(.*)<\/metadataUpdateDate>/).first.first)
      creation_time = Time.parse(xml.scan(/<metadataCreationDate>(.*)<\/metadataCreationDate>/).first.first)
      expect(update_time).to be_within(10.seconds).of(Time.now)
      expect(creation_time).to be_within(10.seconds).of(Time.now)
      expect(xml).to include('<creationDate>'+at.created_at.strftime('%Y-%m-%d %H:%M:%S')+'</creationDate>')
      expect(xml).to include('<updateDate>'+at.updated_at.strftime('%Y-%m-%d %H:%M:%S')+'</updateDate>')
      expect(xml).to include('</atomicService>')
      expect(xml).to end_with('</resource_metadata>')
    end

    it 'assigns correct user login' do
      xml = owned_at.as_metadata_xml.strip
      expect(xml).to include('<author>'+user.login+'</author>')
    end

    it 'creates proper update metadata xml document' do
      xml = published_at.as_metadata_xml.strip
      expect(xml).to include('<globalID>MDGLID</globalID>')
      expect(xml).to_not include('metadataCreationDate')
      expect(xml).to_not include('category')
    end

    it 'puts development state in metadata xml document' do
      xml = devel_at.as_metadata_xml.strip
      expect(xml).to include('<development>true</development>')
    end

    it 'handles endpoints properly' do
      xml = complex_at.as_metadata_xml.strip
      expect(xml).to include('<description>DESC</description>')
      expect(xml).to include('<endpoint>')
      expect(xml.scan('<endpoint>').size).to eq 3
      [endp11, endp12, endp21].each do |endp|
        expect(
          xml.split('Endpoint').any? do |endp_xml|
            if endp_xml.include? endp.name
              expect(endp_xml).to include('<endpointID>'+endp.id.to_s+'</endpointID>')
              expect(endp_xml).to include('<name>'+endp.name+'</name>')
              expect(endp_xml).to include('<description>'+endp.description.to_s+'</description>')
              true
            else
              false
            end
          end).to eq true
      end
    end

    it 'escapes XML content for proper document structure' do
      xml = evil_at.as_metadata_xml.strip
      expect(xml).to include('<name>&lt;/name&gt;&lt;/AtomicService&gt;WE RULE!</name>')
    end
  end

  describe 'manage metadata' do
    let(:at) { create(:appliance_type) }
    let(:public_at) { create(:appliance_type, visible_to: :all) }
    let(:devel_at) { create(:appliance_type, visible_to: :developer) }
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:published_at) { create(:appliance_type, visible_to: :all, metadata_global_id: 'mgid', preference_memory: 500, author: user) }
    let(:published_devel_at) { create(:appliance_type, visible_to: :developer, metadata_global_id: 'mgid') }

    it 'does not publish private appliance types' do
      expect(at).not_to receive(:publish_metadata)
      at.run_callbacks(:create)
    end

    it 'publishes new pubic appliance type' do
      expect(public_at).to receive(:publish_metadata)
      public_at.run_callbacks(:create)
    end

    it 'publishes new development appliance type' do
      expect(devel_at).to receive(:publish_metadata)
      devel_at.run_callbacks(:create)
    end

    it 'publishes private appliance type made public' do
      expect(public_at).to receive(:publish_metadata)
      public_at.save

      at.visible_to = :all
      mrc = Atmosphere::MetadataRepositoryClient.instance
      expect(mrc).to receive(:publish_appliance_type).with(at)
      at.save
    end

    it 'publishes private appliance type made development' do
      at.visible_to = :developer
      mrc = Atmosphere::MetadataRepositoryClient.instance
      expect(mrc).to receive(:publish_appliance_type).with(at)
      at.save
    end

    it 'does not publish private updated appliance type' do
      expect(at).to receive(:manage_metadata).once
      expect(at).not_to receive(:publish_metadata)
      at.run_callbacks(:update)
    end

    it 'does not unregister private or unpublished destroyed appliance type metadata' do
      expect(at).not_to receive(:remove_metadata)
      published_at.run_callbacks(:destroy)
      expect(public_at).not_to receive(:remove_metadata)
      public_at.run_callbacks(:destroy)
    end

    it 'unregisters published destroyed appliance type metadata' do
      expect(published_at).to receive(:remove_metadata).once
      published_at.run_callbacks(:destroy)

      expect(published_devel_at).to receive(:remove_metadata).once
      published_devel_at.run_callbacks(:destroy)
    end

    it 'does not try to update appliance type about to be destroyed' do
      expect{published_at.destroy}.not_to raise_exception
    end

    it 'updates metadata of published appliance type' do
      expect(published_at).to receive(:update_metadata).twice
      published_at.description = 'sth else'
      published_at.save
      published_at.name = 'new name'
      published_at.save
      expect(published_at).to receive(:update_metadata).once
      published_at.visible_to = :all # No real change here
      published_at.save
      published_at.visible_to = :developer
      published_at.save
    end

    it 'unregisters published appliance type made private' do
      expect(published_at).to receive(:remove_metadata).once
      published_at.visible_to = :owner
      published_at.save
    end

    it 'sets published appliance type made private mgid to nil' do
      expect(published_at.metadata_global_id).to eq 'mgid'
      published_at.visible_to = :owner
      published_at.save
      expect(published_at.metadata_global_id).to eq nil
    end

    it 'updates user login metadata on author change' do
      expect(published_at).to receive(:update_metadata).once
      published_at.author = other_user
      published_at.save
    end

    it 'updates user login metadata on author login change' do
      allow(user).to receive(:appliance_types).and_return([published_at])
      expect(published_at).to receive(:update_metadata).once
      user.login = 'Mr. Cellophane'
      user.save
    end

    it 'does not update metadata of published appliance type when no metadata change occurred' do
      expect(published_at).not_to receive(:update_metadata)
      published_at.preference_memory = 600
      published_at.save
    end

  end

  describe 'destroy object and relation to VMT' do
    let(:vmt1) { create(:virtual_machine_template) }
    let(:vmt2) { create(:virtual_machine_template) }
    let!(:at) { create(:appliance_type, virtual_machine_templates: [vmt1, vmt2]) }

    it 'removes all assigned virtual machine templates' do
      expect {
        at.destroy
      }.to change { Atmosphere::VirtualMachineTemplate.count }.by(-2)
    end

    it 'does not remove VMT when removed from relation' do
      expect {
        at.virtual_machine_templates = [ vmt1 ]
      }.to change { Atmosphere::VirtualMachineTemplate.count }.by(0)
    end
  end

  it 'allow to be started only on active compute site' do
    active_cs = create(:compute_site, active: true)
    inactive_cs = create(:compute_site, active: false)
    active_vmt = create(:virtual_machine_template, compute_site: active_cs)
    inactive_vmt = create(:virtual_machine_template, compute_site: inactive_cs)
    at = create(:appliance_type,
      virtual_machine_templates: [active_vmt, inactive_vmt])

    expect(at.compute_sites).to eq [active_cs]
  end
end