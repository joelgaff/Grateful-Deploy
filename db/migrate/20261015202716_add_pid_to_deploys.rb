class AddPidToDeploys < ActiveRecord::Migration[8.1]
  def change
    add_column :deploys, :pid, :integer
  end
end
