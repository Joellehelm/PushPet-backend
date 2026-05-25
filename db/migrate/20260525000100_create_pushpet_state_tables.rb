class CreatePushpetStateTables < ActiveRecord::Migration[8.0]
  def change
    create_table :individual_pushpets do |t|
      t.string :username, null: false
      t.string :species, null: false, default: "goat_dragon"
      t.string :color, null: false, default: "blue"
      t.string :accessory, null: false, default: "none"
      t.jsonb :equipped_accessories, null: false, default: {}
      t.datetime :hatched_at, null: false

      t.timestamps
    end

    add_index :individual_pushpets, "lower(username)", unique: true, name: "index_individual_pushpets_on_lower_username"

    create_table :leaderboard_entries do |t|
      t.string :username, null: false
      t.integer :score, null: false, default: 0
      t.integer :searches, null: false, default: 0
      t.string :avatar_url
      t.string :mood
      t.string :dormancy_state
      t.string :species, null: false, default: "goat_dragon"
      t.string :color, null: false, default: "blue"
      t.string :accessory, null: false, default: "none"
      t.jsonb :equipped_accessories, null: false, default: {}
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :leaderboard_entries, "lower(username)", unique: true, name: "index_leaderboard_entries_on_lower_username"
    add_index :leaderboard_entries, [:score, :last_seen_at]

    create_table :community_pet_states do |t|
      t.string :key, null: false
      t.jsonb :state, null: false, default: {}

      t.timestamps
    end

    add_index :community_pet_states, :key, unique: true
  end
end
