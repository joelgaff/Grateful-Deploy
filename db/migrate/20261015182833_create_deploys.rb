class CreateDeploys < ActiveRecord::Migration[8.1]
  def change
    create_table :deploys do |t|
      t.references :app, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: "queued"
      t.string :triggered_by, null: false, default: "ui"
      t.string :version
      t.string :git_sha
      t.string :git_branch
      t.string :git_message
      t.text :log, null: false, default: ""
      t.integer :exit_code
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    # One deploy in flight per app, enforced by SQLite itself.
    add_index :deploys, :app_id, unique: true, where: "status IN ('queued', 'running')",
                                 name: "index_deploys_one_in_flight_per_app"
  end
end
