class AddDisplayNameToIndividualPushpets < ActiveRecord::Migration[8.0]
  def change
    add_column :individual_pushpets, :display_name, :string
  end
end
