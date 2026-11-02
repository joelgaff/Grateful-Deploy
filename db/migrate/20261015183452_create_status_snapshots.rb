class CreateStatusSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :status_snapshots do |t|
      t.references :app, null: false, foreign_key: true
      t.string :version
      t.string :container_state
      t.string :container_status
      t.bigint :memory_bytes
      t.integer :health_code
      t.integer :response_ms
      t.string :error
      t.datetime :checked_at, null: false

      t.timestamps
    end
    add_index :status_snapshots, %i[app_id checked_at]
  end
end
