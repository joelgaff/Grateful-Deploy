class AddHttpsHealthChecks < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :proxy_https_port, :integer, default: 443, null: false
    add_column :apps, :health_https, :boolean, default: false, null: false
  end
end
