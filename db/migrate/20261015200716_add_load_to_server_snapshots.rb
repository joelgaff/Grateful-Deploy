class AddLoadToServerSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :server_snapshots, :load_1, :float
    add_column :server_snapshots, :load_5, :float
    add_column :server_snapshots, :load_15, :float
    add_column :server_snapshots, :cpus, :integer
  end
end
