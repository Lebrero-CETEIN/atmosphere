module Atmosphere
  module Api
    module V1
      class VirtualMachinesController < Atmoshpere::Api::ApplicationController
        load_and_authorize_resource :virtual_machine
        respond_to :json

        def index
          respond_with @virtual_machines.where(filter).order(:id).distinct
        end

        def show
          respond_with @virtual_machine
        end

        private

        def filter
          filter = super
          appliance_id = params[:appliance_id]
          filter[:appliances] = {id: appliance_id} unless appliance_id.blank?
          filter[:virtual_machine_flavor_id] = params[:flavor_id] if params[:flavor_id]

          filter
        end
      end
    end
  end
end