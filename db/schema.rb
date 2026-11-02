# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_20_170000) do
  create_table "apps", force: :cascade do |t|
    t.integer "server_id", null: false
    t.string "name", null: false
    t.string "repo_path", null: false
    t.string "kamal_mode", default: "destination", null: false
    t.string "destination"
    t.string "config_file"
    t.string "kamal_binary", default: "bundled", null: false
    t.string "service", null: false
    t.string "health_path", default: "/up", null: false
    t.json "domains", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "kamal_env", default: {}, null: false
    t.boolean "health_https", default: false, null: false
    t.index ["server_id", "name"], name: "index_apps_on_server_id_and_name", unique: true
    t.index ["server_id"], name: "index_apps_on_server_id"
  end

  create_table "deploys", force: :cascade do |t|
    t.integer "app_id", null: false
    t.string "kind", null: false
    t.string "status", default: "queued", null: false
    t.string "triggered_by", default: "ui", null: false
    t.string "version"
    t.string "git_sha"
    t.string "git_branch"
    t.string "git_message"
    t.text "log", default: "", null: false
    t.integer "exit_code"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "pid"
    t.integer "log_lines", default: 0, null: false
    t.index ["app_id"], name: "index_deploys_on_app_id"
    t.index ["app_id"], name: "index_deploys_one_in_flight_per_app", unique: true, where: "status IN ('queued', 'running')"
  end

  create_table "identities", force: :cascade do |t|
    t.string "email"
    t.string "login_code_digest"
    t.datetime "login_code_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_identities_on_email", unique: true
  end

  create_table "log_sessions", force: :cascade do |t|
    t.integer "app_id", null: false
    t.string "mode", default: "recent", null: false
    t.string "status", default: "running", null: false
    t.integer "pid"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_log_sessions_on_app_id"
    t.index ["app_id"], name: "index_log_sessions_one_running_per_app", unique: true, where: "status = 'running'"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "server_snapshots", force: :cascade do |t|
    t.integer "server_id", null: false
    t.bigint "memory_total"
    t.bigint "memory_used"
    t.bigint "memory_available"
    t.bigint "swap_total"
    t.bigint "swap_used"
    t.bigint "disk_total"
    t.bigint "disk_used"
    t.bigint "disk_available"
    t.json "containers", default: [], null: false
    t.string "error"
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "load_1"
    t.float "load_5"
    t.float "load_15"
    t.integer "cpus"
    t.json "kamal_locks"
    t.index ["server_id", "checked_at"], name: "index_server_snapshots_on_server_id_and_checked_at"
    t.index ["server_id"], name: "index_server_snapshots_on_server_id"
  end

  create_table "servers", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "name", null: false
    t.string "host", null: false
    t.string "ssh_user", default: "root", null: false
    t.string "region"
    t.integer "proxy_http_port", default: 80, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "proxy_https_port", default: 443, null: false
    t.index ["organization_id", "name"], name: "index_servers_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_servers_on_organization_id"
  end

  create_table "status_snapshots", force: :cascade do |t|
    t.integer "app_id", null: false
    t.string "version"
    t.string "container_state"
    t.string "container_status"
    t.bigint "memory_bytes"
    t.integer "health_code"
    t.integer "response_ms"
    t.string "error"
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "checked_at"], name: "index_status_snapshots_on_app_id_and_checked_at"
    t.index ["app_id"], name: "index_status_snapshots_on_app_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "identity_id", null: false
    t.integer "organization_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_users_on_identity_id"
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "apps", "servers"
  add_foreign_key "deploys", "apps"
  add_foreign_key "log_sessions", "apps"
  add_foreign_key "server_snapshots", "servers"
  add_foreign_key "servers", "organizations"
  add_foreign_key "status_snapshots", "apps"
  add_foreign_key "users", "identities"
  add_foreign_key "users", "organizations"
end
