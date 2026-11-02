class CreateServerSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :server_snapshots do |t|
      t.references :server, null: false, foreign_key: true
      t.bigint :memory_total
      t.bigint :memory_used
      t.bigint :memory_available
      t.bigint :swap_total
      t.bigint :swap_used
      t.bigint :disk_total
      t.bigint :disk_used
      t.bigint :disk_available
      t.json :containers, null: false, default: []
      t.string :error
      t.datetime :checked_at, null: false

      t.timestamps
    end
    add_index :server_snapshots, %i[server_id checked_at]
  end
end
