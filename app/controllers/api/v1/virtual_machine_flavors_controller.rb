module Api
  module V1

    class VirtualMachineFlavorsController < Api::ApplicationController
      authorize_resource :virtual_machine_flavor
      respond_to :json

      # Query params may include either:
      # - appliance_configuration_instance_id and optionally compute_site_id
      # - appliance_type_id and optionally compute_site_id
      # - a combination of compute_site_id, cpu, memory, hdd
      # or be empty.
      def index
        #check_filters!
        @virtual_machine_flavors = []
        if filters_empty? ||requirements_filters?
          conditions_str = build_condition_str
          @virtual_machine_flavors = VirtualMachineFlavor.where(conditions_str, params)
        elsif appliance_conf_inst_filters?

        elsif appliance_type_filters?
          tmpls = params['compute_site_id'] ? VirtualMachineTemplate.where(appliance_type_id: params['appliance_type_id'], state: 'active', compute_site_id: params['compute_site_id']) : VirtualMachineTemplate.where(appliance_type_id: params['appliance_type_id'], state: 'active')
          unless tmpls.blank?
            tmpl, flavor = Optimizer.instance.select_tmpl_and_flavor(tmpls)
            @virtual_machine_flavors = [flavor]
          end
        else
          raise Air::Conflict.new("Illegal combination of filters")
        end
        respond_with @virtual_machine_flavors
      end

      private
      def build_condition_str
        cs_condition = params['compute_site_id'] ? "compute_site_id = :compute_site_id" : ''
        cpu_condition = params['cpu'] ? "cpu >= :cpu" : ''
        mem_condition = params['memory'] ? "memory >= :memory" : ''
        hdd_condition = params['hdd'] ? "hdd >= :hdd" : ''
        [cs_condition, cpu_condition, mem_condition, hdd_condition].reject{|e| e.blank?}.join(" AND ")
      end

      
      def check_filters!
        return if (filters_empty? || appliance_conf_inst_filters? || appliance_type_filters? || requirements_filters?)
        raise Air::Conflict.new("Illegal combination of filters")
      end

      def filters_empty?
        (params.keys & ['appliance_configuration_instance_id', 'appliance_type_id','compute_site_id', 'cpu', 'memory', 'hdd']).empty?
      end

      def appliance_conf_inst_filters?
        keys = params.keys
        (keys.include? 'appliance_configuration_instance_id') && (keys & ['appliance_type_id', 'cpu', 'memory', 'hdd']).empty?
      end

      def appliance_type_filters?
        keys = params.keys
        (keys.include? 'appliance_type_id') && (keys & ['appliance_configuration_instance_id', 'cpu', 'memory', 'hdd']).empty?
      end

      def requirements_filters?
        keys = params.keys
        (not (keys & ['compute_site_id', 'cpu', 'memory', 'hdd']).empty?) && (keys & ['appliance_configuration_instance_id', 'appliance_type_id']).empty?
      end

    end

  end
end