# == Schema Information
#
# Table name: appliances
#
#  id                                  :integer          not null, primary key
#  appliance_set_id                    :integer          not null
#  appliance_type_id                   :integer          not null
#  created_at                          :datetime
#  updated_at                          :datetime
#  appliance_configuration_instance_id :integer          not null
#

class Appliance < ActiveRecord::Base
  extend Enumerize

  belongs_to :appliance_set
  belongs_to :appliance_type
  belongs_to :appliance_configuration_instance

  validates_presence_of :appliance_set, :appliance_type, :appliance_configuration_instance

  enumerize :state, in: [:new, :satisfied, :unsatisfied], predicates: true
  validates_presence_of :state

  has_many :http_mappings, dependent: :destroy
  has_and_belongs_to_many :virtual_machines

  has_one :dev_mode_property_set, dependent: :destroy, autosave: true
  attr_readonly :dev_mode_property_set

  before_create :create_dev_mode_property_set, if: :development?
  after_destroy :remove_appliance_configuration_instance_if_needed
  after_destroy :optimize_destroyed_appliance
  after_create :optimize_saved_appliance

  before_destroy :generate_proxy_conf

  def to_s
    "#{id} #{appliance_type.name} with configuration #{appliance_configuration_instance_id}"
  end

  def development?
    appliance_set.appliance_set_type.development?
  end

  private

  def create_dev_mode_property_set
    self.dev_mode_property_set = DevModePropertySet.create_from(appliance_type)
  end

  def remove_appliance_configuration_instance_if_needed
    if appliance_configuration_instance.appliances.blank?
      appliance_configuration_instance.destroy
    end
  end

  def optimize_saved_appliance
    Optimizer.instance.run(created_appliance: self)
  end

  def optimize_destroyed_appliance
    Optimizer.instance.run(destroyed_appliance: self)
  end

  def generate_proxy_conf
    affected_compute_sites = ComputeSite.joins(virtual_machines: :appliances).where(appliances: {id: id})
    affected_compute_sites.each do |cs|
      ProxyConfWorker.new.perform(cs.id)
    end
  end
end
