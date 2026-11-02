class AddLogLinesToDeploys < ActiveRecord::Migration[8.1]
  def change
    add_column :deploys, :log_lines, :integer, default: 0, null: false

    reversible do |direction|
      direction.up do
        execute "UPDATE deploys SET log_lines = length(log) - length(replace(log, char(10), ''))"
      end
    end
  end
end
