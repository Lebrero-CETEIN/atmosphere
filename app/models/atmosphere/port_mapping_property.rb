# == Schema Information
#
# Table name: port_mapping_properties
#
#  id                       :integer          not null, primary key
#  key                      :string(255)      not null
#  value                    :string(255)      not null
#  port_mapping_template_id :integer
#  compute_site_id          :integer
#  created_at               :datetime
#  updated_at               :datetime
#
module Atmosphere
  class PortMappingProperty < ActiveRecord::Base
    belongs_to :port_mapping_template,
      class_name: 'Atmosphere::PortMappingTemplate'

    belongs_to :compute_site,
      class_name: 'Atmosphere::ComputeSite'

    validates_presence_of :key, :value

    validates_presence_of :port_mapping_template, if: 'compute_site == nil'
    validates_presence_of :compute_site, if: 'port_mapping_template == nil'

    validates_absence_of :port_mapping_template, if: 'compute_site != nil'
    validates_absence_of :compute_site, if: 'port_mapping_template != nil'

    validates_uniqueness_of :key, scope: :port_mapping_template_id

    def to_s
      "#{key} #{value}"
    end
  end
end
