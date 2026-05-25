class AddBackgroundToPushpets < ActiveRecord::Migration[8.0]
  def change
    add_column :individual_pushpets, :background, :string, null: false, default: "petplace1"
    add_column :leaderboard_entries, :background, :string, null: false, default: "petplace1"
  end
end
