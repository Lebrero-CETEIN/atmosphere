require 'spec_helper'

describe VmTagsCreatorWorker do

  server_id = 'SERVER_ID'
  site_id = 1
  tags_map = {'1_tag_name' => '1_value', '2_tag_name' => '2_value'}

  let(:cs_mock) {double('compute site')}
  let(:cloud_client_mock) {double('cloud client')}

  before do
    allow(ComputeSite).to receive(:find).with(site_id).and_return cs_mock
    allow(cs_mock).to receive(:cloud_client).and_return cloud_client_mock
  end

  it 'calls cloud client with appropriate tag parameters' do
    expect(cloud_client_mock).to receive(:create_tags_for_vm).with(server_id, tags_map)
    expect(Raven).not_to receive(:capture_exception)
    VmTagsCreatorWorker.new.perform(server_id, site_id, tags_map)
  end

  it 'reports error to Raven' do
    exc = Fog::Compute::AWS::NotFound.new
    expect(cloud_client_mock).to receive(:create_tags_for_vm).with(server_id, tags_map).and_raise(exc)
    expect(Raven).to receive(:capture_message).with(start_with('Failed to annotate'), anything)
    begin
      VmTagsCreatorWorker.new.perform(server_id, site_id, tags_map)
    rescue
      # exc is expected to be raised
    end
  end

  it 'reraise exception' do
    exc = Fog::Compute::OpenStack::NotFound.new
    expect(cloud_client_mock).to receive(:create_tags_for_vm).with(server_id, tags_map).and_raise(exc)
    expect { VmTagsCreatorWorker.new.perform(server_id, site_id, tags_map) }
      .to raise_error(Fog::Compute::OpenStack::NotFound)
  end

end