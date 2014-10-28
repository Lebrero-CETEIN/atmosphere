module Atmosphere
  class ClewApplianceInstancesSerializer < ActiveModel::Serializer
    attribute :appliances

    def appliances
      appl_sets = object[:appliance_sets]
      appliances = Set.new
      appl_sets.each do |appl_set|
        appl_set.appliances.each do |appl|
          appliances.add(map_appliance(appl))
        end
      end
      appliances
    end

    def map_appliance(appliance)
      {
        id: appliance.id,
        name: appliance.name,
        appliance_set_id: appliance.appliance_set_id,
        description: appliance.description,
        state: appliance.state,
        state_explanation: appliance.state_explanation,
        amount_billed: appliance.amount_billed,
        prepaid_until: appliance.prepaid_until,
        port_mapping_templates: pmts(appliance),
        virtual_machines: appliance.deployments.map { |depl| map_vm(depl.virtual_machine) },
      }
    end

    def pmts(appliance)
      pmts_hsh = appliance_pmts(appliance).inject({}) do |hsh, pmt|
        hsh[pmt.id] = map_pmt(pmt)
        hsh
      end

      add_http_mappings(appliance.http_mappings, pmts_hsh)

      pmts_hsh.values
    end

    def appliance_pmts(appliance)
      if appliance.development?
        appliance.dev_mode_property_set.port_mapping_templates
      else
        appliance.appliance_type.port_mapping_templates
      end
    end

    def add_http_mappings(http_mappings, pmts_hsh)
      http_mappings.each do |http_mapping|
        pmt = pmts_hsh[http_mapping.port_mapping_template_id]
        pmt[:http_mappings] << map_hm(http_mapping)
      end
    end

    def map_pmt(pmt)
      {
        id: pmt.id,
        service_name: pmt.service_name,
        target_port: pmt.target_port,
        transport_protocol: pmt.transport_protocol,
        application_protocol: pmt.application_protocol,
        http_mappings: [],
        endpoints: pmt.endpoints
      }
    end

    def map_hm(hm)
      {
        id: hm.id,
        application_protocol: hm.application_protocol,
        url: hm.url,
        appliance_id: hm.appliance_id,
        port_mapping_template_id: hm.port_mapping_template_id,
        compute_site_id: hm.compute_site_id,
        monitoring_status: hm.monitoring_status,
        custom_name: hm.custom_name,
        custom_url: hm.custom_url
      }
    end

    def map_vm(vm)
      {
        id: vm.id,
        ip: vm.ip,
        state: vm.state,
        compute_site: map_cs(vm.compute_site),
        virtual_machine_flavor: vm.virtual_machine_flavor,
        port_mappings: vm.port_mappings
      }
    end

    def map_cs(cs)
      {
        id: cs.id,
        site_id: cs.site_id,
        name: cs.name,
        location: cs.location,
        site_type: cs.site_type,
        technology: cs.technology,
        http_proxy_url: cs.http_proxy_url,
        https_proxy_url: cs.https_proxy_url,
        config: "SANITIZED",
        template_filters: cs.template_filters,
        active: cs.active
      }
    end
  end
end
