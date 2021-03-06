require 'rails_helper'

describe Atmosphere::VmTemplateMonitoringWorker do

  before { Fog.mock! }

  context 'as a sidekiq worker' do
    it 'responds to #perform' do
      expect(subject).to respond_to(:perform)
    end

    it { should be_retryable false }
    it { should be_processed_in :monitoring }
  end

  context 'updating tenant images' do
    let(:cyfronet_folsom) do
      create(:tenant, tenant_id: 'cyfronet-folsom', \
      config: '{"provider": "openstack", "openstack_auth_url": "http://10.100.0.2:5000/v2.0/tokens",
      "openstack_api_key": "key", "openstack_username": "user"}')
    end
    let(:ubuntu_data) { image 'ubuntu', 'Ubuntu 12.04', :ACTIVE }
    let(:arch_data)   { image 'arch',   'Arch',         :SAVING }
    let(:centos_data) { image 'centos', 'Centos',       :ERROR }

    before do
      data = cyfronet_folsom.cloud_client.data
      images = data[:images]

      ## remove mock provided by Fog
      images.delete("0e09fbd6-43c5-448a-83e9-0d3d05f9747e")

      ## create 3 new one with different states
      images["ubuntu"] = ubuntu_data
      images["arch"]   = arch_data
      images["centos"] = centos_data

      # fog change saving into active after defined period of time
      data[:last_modified][:images]['arch'] = Time.new
    end

    context 'when no templates registered' do
      it 'creates 3 new templates' do
        expect {
          subject.perform(cyfronet_folsom.id)
        }.to change{ Atmosphere::VirtualMachineTemplate.count }.by(3)
      end

      it 'creates new templates and set details' do
        subject.perform(cyfronet_folsom.id)

        db_ubuntu = Atmosphere::VirtualMachineTemplate.find_by(id_at_site: 'ubuntu')
        db_arch = Atmosphere::VirtualMachineTemplate.find_by(id_at_site: 'arch')
        db_centos = Atmosphere::VirtualMachineTemplate.find_by(id_at_site: 'centos')

        expect(db_ubuntu).to vmt_fog_data_equals ubuntu_data, cyfronet_folsom
        expect(db_arch).to vmt_fog_data_equals arch_data, cyfronet_folsom
        expect(db_centos).to vmt_fog_data_equals centos_data, cyfronet_folsom
      end

      it 'deletes template record when not bound to any tenants' do
        subject.perform(cyfronet_folsom.id)
        db_ubuntu = Atmosphere::VirtualMachineTemplate.find_by(id_at_site: 'ubuntu')
        db_ubuntu.created_at -= 2.hours
        db_ubuntu.save
        cyfronet_folsom.cloud_client.data[:images].delete("ubuntu")
        subject.perform(cyfronet_folsom.id)
        db_ubuntu = Atmosphere::VirtualMachineTemplate.find_by(id_at_site: 'ubuntu')
        expect(db_ubuntu).to be_blank
      end
    end

    context 'when some templates exist' do
      let!(:ubuntu) { create(:virtual_machine_template, id_at_site: 'ubuntu', tenants: [cyfronet_folsom], state: :saving) }

      it 'does not create duplicated templates' do
        expect {
          subject.perform(cyfronet_folsom.id)
        }.to change{ Atmosphere::VirtualMachineTemplate.count }.by(2)
      end

      it 'updates existing template details' do
        subject.perform(cyfronet_folsom.id)
        db_ubuntu = Atmosphere::VirtualMachineTemplate.find_by(id_at_site: 'ubuntu')

        expect(db_ubuntu).to vmt_fog_data_equals ubuntu_data, cyfronet_folsom
      end
    end

    context 'when template removed' do
      before do
        create(:virtual_machine_template, id_at_site: 'ubuntu', tenants: [cyfronet_folsom])
        create(:virtual_machine_template, id_at_site: 'arch', tenants: [cyfronet_folsom])
        create(:virtual_machine_template, id_at_site: 'centos', tenants: [cyfronet_folsom])
        create(:virtual_machine_template, id_at_site: 'old_vmt', tenants: [cyfronet_folsom], created_at: 6.minutes.ago)
        create(:virtual_machine_template, id_at_site: 'young_vmt', tenants: [cyfronet_folsom])
      end

      it 'removes deleted template' do
        expect {
          subject.perform(cyfronet_folsom.id)
        }.to change{ Atmosphere::VirtualMachineTemplate.count }.by(-1)
      end
    end

    context 'when fog error occurs' do
      let(:cloud_client) { double }
      let(:logger) { double }

      before do
        allow(Atmosphere).to receive(:monitoring_logger).and_return(logger)
        expect(logger).to receive(:error)
        allow(logger).to receive(:debug)

        allow_any_instance_of(Atmosphere::Tenant)
          .to receive(:cloud_client).and_return(cloud_client)
        allow(cloud_client).to receive(:images).and_raise(Excon::Errors::Unauthorized.new 'error')
      end

      it 'logs error into rails logs' do
        subject.perform(cyfronet_folsom.id)
      end
    end
  end

  def image(id, name, status)
    {
      "id"        =>id,
      "name"      => name,
      'progress'  => 100,
      'status'    => status.to_s.upcase,
      'updated'   => "",
      'minRam'    => 0,
      'minDisk'   => 0,
      'metadata'  => {},
      'links'     => [{"href"=>"http://nova1:8774/v1.1/admin/images/1", "rel"=>"self"}, {"href"=>"http://nova1:8774/admin/images/2", "rel"=>"bookmark"}]
    }
  end
end