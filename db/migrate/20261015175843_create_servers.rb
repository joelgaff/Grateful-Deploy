class CreateServers < ActiveRecord::Migration[8.1]
  def change
    create_table :servers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :host, null: false
      t.string :ssh_user, null: false, default: "root"
      t.string :region
      t.integer :proxy_http_port, null: false, default: 80
      t.text :notes

      t.timestamps
    end
    add_index :servers, %i[organization_id name], unique: true
  end
end
