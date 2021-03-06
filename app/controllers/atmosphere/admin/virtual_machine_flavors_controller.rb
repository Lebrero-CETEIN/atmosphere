class Atmosphere::Admin::VirtualMachineFlavorsController < Atmosphere::Admin::ApplicationController
  load_and_authorize_resource :virtual_machine_flavor,
                              class: 'Atmosphere::VirtualMachineFlavor'

  # GET /virtual_machine_flavors/1/edit
  def edit
  end

  # PATCH/PUT /virtual_machine_flavors/1
  def update
    alert = nil
    params[:virtual_machine_flavor][:hourly_cost].each do |os_family_id, cost|
      os_family = Atmosphere::OSFamily.find_by(id: os_family_id)
      if cost.strip.empty? &&
         os_family &&
         @virtual_machine_flavor.get_hourly_cost_for(os_family)
        unless @virtual_machine_flavor.remove_hourly_cost_for(os_family)
          alert = I18n.t('virtual_machine_flavor.cant_destroy',
                         os_family: os_family.name)
        end
      elsif cost.strip.present? && cost.to_i >= 0  && os_family
        @virtual_machine_flavor.set_hourly_cost_for(os_family, cost.to_i)
      end
    end
    redirect_to admin_tenants_path, alert: alert
  end

  private

  # Only allow a trusted parameter "white list" through.
  def virtual_machine_flavor_params
    params.require(:virtual_machine_flavor).tap do |whitelisted|
      whitelisted[:hourly_cost] = params[:virtual_machine_flavor][:hourly_cost]
    end
  end
end
