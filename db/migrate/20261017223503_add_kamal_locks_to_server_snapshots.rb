class AddKamalLocksToServerSnapshots < ActiveRecord::Migration[8.1]
  def change
    # Lock folder name => Kamal's lock details. {} = no locks; NULL = couldn't read (SSH failed).
    add_column :server_snapshots, :kamal_locks, :json
  end
end
