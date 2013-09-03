# == Schema Information
#
# Table name: port_mappings
#
#  id                       :integer          not null, primary key
#  public_ip                :string(255)      not null
#  source_port              :integer          not null
#  port_mapping_template_id :integer          not null
#  virtual_machine_id       :integer          not null
#  created_at               :datetime
#  updated_at               :datetime
#

class PortMapping < ActiveRecord::Base

  belongs_to :virtual_machine
  belongs_to :port_mapping_template

  validates_presence_of :public_ip, :source_port, :virtual_machine, :port_mapping_template

  validates :source_port, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

end