class CreateApplianceTypes < ActiveRecord::Migration
  def change
    create_table :appliance_types do |t|

      t.string :name,                   null: false
      t.text :description
      t.boolean :shared,                default: false
      t.boolean :scalable,              default: false
      t.string :visibility,             null:false, default: 'under_development'

      # Incorporated from the old AppliancePreferences model
      t.float :preference_cpu
      t.integer :preference_memory
      t.integer :preference_disk

      t.timestamps
    end

    add_index :appliance_types, :name, unique: true
  end
end
