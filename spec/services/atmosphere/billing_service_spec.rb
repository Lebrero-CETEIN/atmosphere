require 'rails_helper'

describe Atmosphere::BillingService do

  let!(:t) { create(:openstack_with_flavors) }
  let!(:t_fund) { create(:fund, tenants: [t]) }
  let!(:non_t_fund) { create(:fund, tenants: [])}
  let!(:empty_fund) { create(:fund, balance: 0, overdraft_limit: 0, tenants: [t] )}
  let!(:non_t_fund) { create(:fund, tenants: [])}

  let!(:wf) { create(:workflow_appliance_set) }

  let!(:windows_osfamily) { create(:os_family, name: 'Windows') }
  let!(:linux_osfamily) { create(:os_family, name: 'Linux') }

  let!(:shareable_appl_type) { create(:shareable_appliance_type) }
  let!(:not_shareable_appl_type) { create(:not_shareable_appliance_type) }
  let!(:tmpl_of_shareable_at) { create(:virtual_machine_template, appliance_type: shareable_appl_type, tenants: [t])}
  let!(:tmpl_of_not_shareable_at) { create(:virtual_machine_template, appliance_type: not_shareable_appl_type, tenants: [t])}

  let!(:not_shareable_vm1) { create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: t.virtual_machine_flavors.first)  }
  let!(:not_shareable_vm2) { create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: t.virtual_machine_flavors.first)  }
  let!(:not_shareable_vm3) { create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: t.virtual_machine_flavors.first)  }
  let!(:not_shareable_vm4) { create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: t.virtual_machine_flavors.first)  }
  let!(:shareable_vm) { create(:virtual_machine, tenant: t, source_template: tmpl_of_shareable_at, virtual_machine_flavor: t.virtual_machine_flavors.first)  }

  let(:optimizer) { double("optimizer") }

  before do
    allow(optimizer).to receive(:run)
    allow(Atmosphere::Optimizer).to receive(:instance).and_return(optimizer)
  end

  context 'new user obtains default fund' do
    it 'creates new user' do
      u = create(:user, funds: [] )
      expect(u.default_fund).to be_a Atmosphere::Fund
    end
  end

  context 'new appliance created and billed' do

    let(:config_inst) { create(:appliance_configuration_instance) }

    it 'creates new funded non-shareable appliance as default' do
      appl = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm1])

      vmf = appl.virtual_machines.first.virtual_machine_flavor
      vmf.set_hourly_cost_for(Atmosphere::OSFamily.first, 10)

      expect(Atmosphere::BillingService.can_afford_vm?(appl, not_shareable_vm1)).to eq true

      Atmosphere::BillingService.bill_appliance(appl, Time.now.utc, "mockup billing", true)

      appl.reload
      expect(appl.deployments.first.billing_state).to eq("prepaid")
      expect(appl.amount_billed).to eq appl.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost
      expect(Atmosphere::BillingLog.all.count).to eq 1
    end

    it 'creates new unfunded non-shareable appliance' do
      appl = create(:appliance, fund: empty_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm1])
      expect(appl.deployments.first.billing_state).to eq("expired")

      expect(Atmosphere::BillingService.can_afford_vm?(appl, not_shareable_vm1)).to eq false

      vmf = appl.virtual_machines.first.virtual_machine_flavor
      vmf.set_hourly_cost_for(Atmosphere::OSFamily.first, 10)

      Atmosphere::BillingService.bill_appliance(appl, Time.now.utc, "mockup billing", true)

      expect(appl.deployments.first.billing_state).to eq("expired")

      # Add funds to empty_fund and retry
      empty_fund.balance = 10000
      empty_fund.save
      appl.reload

      expect(Atmosphere::BillingService.can_afford_vm?(appl, not_shareable_vm1)).to eq true

      Atmosphere::BillingService.bill_appliance(appl, Time.now.utc, "mockup billing", true)


      appl.reload
      expect(appl.deployments.first.billing_state).to eq("prepaid")
    end

    it 'creates new funded shareable appliance' do

      original_balance = t_fund.balance

      appl1 = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [shareable_vm])

      vmf = appl1.virtual_machines.first.virtual_machine_flavor
      vmf.set_hourly_cost_for(Atmosphere::OSFamily.first, 10)

      Atmosphere::BillingService.bill_appliance(appl1, Time.now.utc, "mock billing", true)
      appl1.reload
      expect(Atmosphere::BillingLog.all.count).to eq 1

      t_fund.reload
      expect(t_fund.balance).to eq original_balance - ((appl1.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost))

      appl2 = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [shareable_vm])

      Atmosphere::BillingService.bill_appliance(appl2, Time.now.utc, "mock billing", true)
      appl2.reload
      expect(appl1.amount_billed).to eq appl1.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost
      expect(appl2.amount_billed).to eq (appl2.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost*0.5).round

      t_fund.reload
      expect(t_fund.balance).to eq original_balance - (appl2.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost*1.5).round

    end
  end

  context 'affording flavors' do

    let(:config_inst) { create(:appliance_configuration_instance) }

    let!(:free_flavor) { create(:virtual_machine_flavor, tenant: t) }
    let!(:cheap_flavor) { create(:virtual_machine_flavor, tenant: t) }
    let!(:expensive_flavor) { create(:virtual_machine_flavor, tenant: t) }

    let!(:switzerland) { create(:fund, balance: 1000000, overdraft_limit: 0, tenants: [t])}
    let!(:middle_class) { create(:fund, balance: 100, overdraft_limit: 0, tenants: [t] )}
    let!(:zus) { create(:fund, balance: 5, overdraft_limit: 0, tenants: [t] )}
    let!(:amber_gold) { create(:fund, balance: 0, overdraft_limit: -1000, tenants: [t] )}
    let!(:alien_fund) { create(:fund, balance: 1000000, overdraft_limit: 0, tenants: [])}

    let!(:rich_appl) { create(:appliance, fund: switzerland, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm1]) }
    let!(:middle_class_appl) { create(:appliance, fund: middle_class, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm2]) }
    let!(:zus_appl1) { create(:appliance, fund: zus, appliance_set: wf, appliance_type: shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [shareable_vm]) }
    let!(:zus_appl2) { create(:appliance, fund: zus, appliance_set: wf, appliance_type: shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [shareable_vm]) }
    let!(:standalone_zus_appl) { create(:appliance, fund: zus, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm3]) }
    let!(:amber_gold_appl) { create(:appliance, fund: amber_gold, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm4]) }
    let!(:alien_appl) { create(:appliance, fund: alien_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines:[])}

    it 'can or cannot afford flavors' do
      free_flavor.flavor_os_families.first.update_attribute(:hourly_cost, 0)
      cheap_flavor.flavor_os_families.first.update_attribute(:hourly_cost, 10)
      expensive_flavor.flavor_os_families.first.update_attribute(:hourly_cost, 100)

      rich_appl = create(:appliance, fund: switzerland, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm1])
      middle_class_appl = create(:appliance, fund: middle_class, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm2])
      zus_appl1 = create(:appliance, fund: zus, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [shareable_vm])
      zus_appl2 = create(:appliance, fund: zus, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [shareable_vm])
      standalone_zus_appl = create(:appliance, fund: zus, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst, virtual_machines: [not_shareable_vm3])

      expect(Atmosphere::BillingService.can_afford_flavor?(rich_appl, expensive_flavor)).to eq true
      expect(Atmosphere::BillingService.can_afford_flavor?(middle_class_appl, expensive_flavor)).to eq true
      expect(Atmosphere::BillingService.can_afford_flavor?(zus_appl1, expensive_flavor)).to eq false
      expect(Atmosphere::BillingService.can_afford_flavor?(zus_appl1, cheap_flavor)).to eq false
      expect(Atmosphere::BillingService.can_afford_flavor?(standalone_zus_appl, cheap_flavor)).to eq false
      expect(Atmosphere::BillingService.can_afford_flavor?(amber_gold_appl, expensive_flavor)).to eq true

      # alien_appl cannot afford anything because its fund is not bound to Tenant t
      expect(Atmosphere::BillingService.can_afford_flavor?(alien_appl, cheap_flavor)).to eq false
      expect(Atmosphere::BillingService.can_afford_flavor?(alien_appl, free_flavor)).to eq false
    end

    it 'can or cannot afford vms' do
      expensive_vm = create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: expensive_flavor)
      cheap_vm = create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: cheap_flavor)
      free_vm = create(:virtual_machine, tenant: t, source_template: tmpl_of_not_shareable_at, virtual_machine_flavor: free_flavor)
      shareable_vm = create(:virtual_machine, tenant: t, source_template: tmpl_of_shareable_at, virtual_machine_flavor: free_flavor)

      free_flavor.flavor_os_families.first.update_attribute(:hourly_cost, 0)
      cheap_flavor.flavor_os_families.first.update_attribute(:hourly_cost, 10)
      expensive_flavor.flavor_os_families.first.update_attribute(:hourly_cost, 100)

      expect(Atmosphere::BillingService.can_afford_vm?(rich_appl, expensive_vm)).to eq true
      expect(Atmosphere::BillingService.can_afford_vm?(zus_appl1, shareable_vm)).to eq true
      expect(Atmosphere::BillingService.can_afford_vm?(zus_appl1, cheap_vm)).to eq false
      expect(Atmosphere::BillingService.can_afford_vm?(zus_appl1, free_vm)).to eq true

      # alien_appl cannot afford anything because its fund is not bound to Tenant t
      expect(Atmosphere::BillingService.can_afford_vm?(alien_appl, cheap_vm)).to eq false
      expect(Atmosphere::BillingService.can_afford_vm?(alien_appl, shareable_vm)).to eq false
      expect(Atmosphere::BillingService.can_afford_vm?(alien_appl, free_vm)).to eq false
    end

  end

  context 'os_families' do
    let(:windows_flavor) { create(:virtual_machine_flavor, tenant: t)}
    let(:linux_flavor) { create(:virtual_machine_flavor, tenant: t)}

    let(:poor_fund) { create(:fund, balance: 75, overdraft_limit: 0, tenants: [t] )}

    let(:config_inst) { create(:appliance_configuration_instance) }

    let!(:windows_appl_type) { create(:not_shareable_appliance_type, os_family: windows_osfamily) }
    let!(:linux_appl_type) { create(:not_shareable_appliance_type, os_family: linux_osfamily) }

    let!(:windows_appliance) { create(:appliance, fund: poor_fund, appliance_set: wf,
      appliance_type: windows_appl_type, appliance_configuration_instance: config_inst,
      virtual_machines: [not_shareable_vm1]) }

    let!(:linux_appliance) { create(:appliance, fund: poor_fund, appliance_set: wf,
      appliance_type: linux_appl_type, appliance_configuration_instance: config_inst,
      virtual_machines: [not_shareable_vm2]) }

    it 'can or cannot afford flavors depending on os_family' do

      linux_flavor.set_hourly_cost_for(linux_osfamily, 50)
      windows_flavor.set_hourly_cost_for(windows_osfamily, 100)

      expect(Atmosphere::BillingService.can_afford_flavor?(windows_appliance, windows_flavor)).to eq false
      expect(Atmosphere::BillingService.can_afford_flavor?(linux_appliance, linux_flavor)).to eq true
      expect(Atmosphere::BillingService.can_afford_flavor?(linux_appliance, windows_flavor)).to eq false
    end
  end

  context 'routine billing' do

    let(:config_inst1) { create(:appliance_configuration_instance) }
    let(:config_inst2) { create(:appliance_configuration_instance) }
    let(:config_inst3) { create(:appliance_configuration_instance) }
    let(:config_inst_shared) { create(:appliance_configuration_instance) }

    it 'appliances are billed on a routine basis' do

      empty_fund.balance = 10
      empty_fund.save
      original_balance = t_fund.balance
      empty_original_balance = empty_fund.balance

      # Standard non-shared appliance
      appl1 = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst_shared, virtual_machines: [not_shareable_vm1])
      # Another standard non-shared appliance
      appl2 = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst_shared, virtual_machines: [not_shareable_vm2])
      # An appliance which is shareable but not yet shared
      appl3a = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: shareable_appl_type, appliance_configuration_instance: config_inst_shared, virtual_machines: [shareable_vm])
      # A shareable appliance which should reuse appl3a's VM
      appl3b = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: shareable_appl_type, appliance_configuration_instance: config_inst_shared, virtual_machines: [shareable_vm])
      # An appliance with a nearly-expired fund
      expiring_appl = create(:appliance, fund: empty_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst3, virtual_machines: [not_shareable_vm3])

      vmf = appl1.virtual_machines.first.virtual_machine_flavor
      vmf.set_hourly_cost_for(Atmosphere::OSFamily.first, 10)

      cost_unit = appl1.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost # Cost per 1h of use for a single (full) VM

      Atmosphere::BillingService.bill_all_appliances

      appl1.reload
      appl2.reload
      appl3a.reload
      appl3b.reload
      expiring_appl.reload
      t_fund.reload
      empty_fund.reload

      expect(t_fund.balance).to eq original_balance - (cost_unit*3).round
      expect(empty_fund.balance).to eq empty_original_balance - cost_unit

      # Roll back prepaid_by in each appliance by 2 hours
      dep1 = appl1.deployments.first
      dep2 = appl2.deployments.first
      dep3a = appl3a.deployments.first
      dep3b = appl3b.deployments.first
      expiring_dep = expiring_appl.deployments.first
      dep1.prepaid_until = dep1.prepaid_until - 2.hours
      dep2.prepaid_until = dep2.prepaid_until - 2.hours
      dep3a.prepaid_until = dep3a.prepaid_until - 2.hours
      dep3b.prepaid_until = dep3b.prepaid_until - 2.hours
      expiring_dep.prepaid_until = expiring_dep.prepaid_until - 2.hours
      dep1.save
      dep2.save
      dep3a.save
      dep3b.save
      expiring_dep.save

      # This will bill all appliances, but expiring_appl will have expired since it does not have enough funds assigned
      Atmosphere::BillingService.bill_all_appliances

      expect(Atmosphere::BillingLog.all.count).to eq 10

      appl1.reload
      appl2.reload
      appl3a.reload
      appl3b.reload
      expiring_appl.reload
      t_fund.reload
      empty_fund.reload

      expect(t_fund.balance).to eq original_balance - (cost_unit*9).round # 3 from previous billing and 6 from this billing
      expect(empty_fund.balance).to eq empty_original_balance - cost_unit # No change here

      expect appl1.amount_billed = cost_unit*3
      expect appl2.amount_billed = cost_unit*3
      expect appl3a.amount_billed = cost_unit*2
      expect appl3b.amount_billed = cost_unit*1
      expect expiring_appl.amount_billed = cost_unit

      expect(appl1.deployments.first.billing_state).to eq "prepaid"
      expect(appl2.deployments.first.billing_state).to eq "prepaid"
      expect(appl3a.deployments.first.billing_state).to eq "prepaid"
      expect(appl3b.deployments.first.billing_state).to eq "prepaid"
      expect(expiring_appl.deployments.first.billing_state).to eq "expired"

    end
  end

  context 'final billing' do

    let(:config_inst1) { create(:appliance_configuration_instance) }

    it 'performs final billing for appliance' do
      original_balance = t_fund.balance

      # Standard non-shared appliance
      appl1 = create(:appliance, fund: t_fund, appliance_set: wf, appliance_type: not_shareable_appl_type, appliance_configuration_instance: config_inst1, virtual_machines: [not_shareable_vm1])

      vmf = appl1.virtual_machines.first.virtual_machine_flavor
      vmf.set_hourly_cost_for(Atmosphere::OSFamily.first, 10)

      cost_unit = appl1.virtual_machines.first.virtual_machine_flavor.flavor_os_families.first.hourly_cost # Cost per 1h of use for a single (full) VM

      Atmosphere::BillingService.bill_appliance(appl1, Time.now.utc, "mock billing", true)

      t_fund.reload
      expect(t_fund.balance).to eq original_balance - cost_unit


      # Advance the clock by 1.5 hours and destroy appl1
      appl1.deployments.first.prepaid_until = Time.now - 30.minutes
      appl1.save

      Atmosphere::DestroyAppliance.new(appl1).execute

      expect(Atmosphere::BillingLog.all.count).to eq 2

      # This should incur another 30-minute expense, triggered automatically by Appliance.destroy
      t_fund.reload
      expect(t_fund.balance).to eq original_balance - (cost_unit*1.5).round

    end
  end
end
