class AddKamalEnvToApps < ActiveRecord::Migration[8.1]
  def change
    add_column :apps, :kamal_env, :json, default: {}, null: false
  end
end
