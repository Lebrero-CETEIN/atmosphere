require 'spec_helper'
require 'zabbix'

describe VmMonitoringWorker do
  let(:vm_updater_class) { double }
  let(:vm_destroyer_class) { double('destroyer') }

  before {
    Fog.mock!
    Zabbix.stub(:register_host).and_return 1
    Zabbix.stub(:unregister_host)
    Zabbix.stub(:host_metrics)
  }

  subject { VmMonitoringWorker.new(vm_updater_class, vm_destroyer_class) }

  context 'as a sidekiq worker' do
    it 'responds to #perform' do
      expect(subject).to respond_to(:perform)
    end

    it { should be_retryable false }
    it { should be_processed_in :monitoring }
  end

  context 'when updating VMs' do
    let(:cloud_client) { double }
    let(:cs) { double('cs', cloud_client: cloud_client) }

    before do
      allow(ComputeSite).to receive(:find).with(1).and_return(cs)
    end

    context 'and cloud client returns information about VMs' do
      before do
        allow(cloud_client).to receive(:servers).and_return(['1', '2'])
        updater1 = double
        expect(updater1).to receive(:update).and_return('1')
        expect(vm_updater_class).to receive(:new).with(cs, '1').and_return(updater1)

        updater2 = double
        expect(updater2).to receive(:update).and_return('2')
        expect(vm_updater_class).to receive(:new).with(cs, '2').and_return(updater2)
      end

      it 'updates VMs' do
        allow(cs).to receive(:virtual_machines).and_return([])

        subject.perform(1)
      end

      it 'deletes VMs not found on compute site' do
        old_vm = double
        allow(cs).to receive(:virtual_machines).and_return(['1', old_vm, '2'])
        destroyer = double

        expect(destroyer).to receive(:destroy).with(false)
        expect(vm_destroyer_class).to receive(:new).with(old_vm).and_return(destroyer)

        subject.perform(1)
      end
    end

    context 'and fog error occurs' do
      let(:logger) { double }

      before do
        Air.stub(:monitoring_logger).and_return(logger)
        expect(logger).to receive(:error)
        allow(logger).to receive(:info)

        allow(cloud_client).to receive(:servers).and_raise(Excon::Errors::Unauthorized.new 'error')
      end

      it 'logs error into rails logs' do
        subject.perform(1)
      end
    end
  end
end