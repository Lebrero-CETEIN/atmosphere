# require 'config/boot'
# require 'config/environment'

require_relative "../config/boot"
require_relative "../config/environment"

module Clockwork
  every(5.seconds, 'proxyconf.regenerate') do
    ProxyConfWorker.regenerate_proxy_confs
  end

  every(1.minute, 'monitoring.templates') do
    ComputeSite.select(:id, :name).each do |cs|
      Rails.logger.debug "Creating templates monitoring task for #{cs.name}"
      VmTemplateMonitoringWorker.perform_async(cs.id)
    end
  end

  every(30.seconds, 'monitoring.vms') do
    ComputeSite.select(:id, :name).each do |cs|
      Rails.logger.debug "Creating vms monitoring task for #{cs.name}"
      VmMonitoringWorker.perform_async(cs.id)
    end
  end
end