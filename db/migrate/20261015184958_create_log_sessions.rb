class CreateLogSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :log_sessions do |t|
      t.references :app, null: false, foreign_key: true
      t.string :mode, null: false, default: "recent"
      t.string :status, null: false, default: "running"
      t.integer :pid
      t.datetime :finished_at

      t.timestamps
    end
    add_index :log_sessions, :app_id, unique: true, where: "status = 'running'",
                                      name: "index_log_sessions_one_running_per_app"
  end
end
