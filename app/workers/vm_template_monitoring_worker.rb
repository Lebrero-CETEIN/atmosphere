class VmTemplateMonitoringWorker
  include Sidekiq::Worker

  sidekiq_options queue: :monitoring
  sidekiq_options :retry => false

  def perform(site_id)
    site = ComputeSite.find(site_id)
    update_images(site, site.cloud_client.images)
  end

  private

  def update_images(site, images)
    all_site_templates = site.virtual_machine_templates.to_a
    images.each do |image|
      template = site.virtual_machine_templates.find_or_initialize_by(id_at_site: image.id)
      template.id_at_site =  image.id
      template.name = image.name
      template.state = image.status.downcase.to_sym

      all_site_templates.delete template

      unless template.save
        error("unable to create/update #{template.id} template because: #{template.errors.to_json}")
      end
    end

    #remove deleted templates
    all_site_templates.each { |t| t.destroy(false) }
  end

  def error(message)
    Rails.logger.error "MONITORING: #{message}"
  end
end