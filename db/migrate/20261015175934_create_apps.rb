class CreateApps < ActiveRecord::Migration[8.1]
  def change
    create_table :apps do |t|
      t.references :server, null: false, foreign_key: true
      t.string :name, null: false
      t.string :repo_path, null: false
      t.string :kamal_mode, null: false, default: "destination"
      t.string :destination
      t.string :config_file
      t.string :kamal_binary, null: false, default: "bundled"
      t.string :service, null: false
      t.string :health_path, null: false, default: "/up"
      t.json :domains, null: false, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :apps, %i[server_id name], unique: true
  end
end
