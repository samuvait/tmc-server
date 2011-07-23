# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20110723190455) do

  create_table "awarded_points", :force => true do |t|
    t.integer "course_id",     :null => false
    t.integer "user_id",       :null => false
    t.text    "name",          :null => false
    t.integer "submission_id"
  end

  add_index "awarded_points", ["course_id", "user_id", "name"], :name => "index_awarded_points_on_course_id_and_user_id_and_name", :unique => true

  create_table "courses", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "hide_after"
    t.string   "remote_repo_url"
  end

  create_table "exercises", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "course_id"
    t.datetime "deadline"
    t.datetime "publish_date"
    t.string   "gdocs_sheet"
    t.boolean  "deleted",      :default => false, :null => false
  end

  create_table "points_upload_queues", :force => true do |t|
    t.integer  "point_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "submissions", :force => true do |t|
    t.integer  "user_id"
    t.integer  "exercise_id"
    t.binary   "return_file"
    t.text     "pretest_error"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "test_case_runs", :force => true do |t|
    t.integer  "submission_id"
    t.text     "test_case_name"
    t.string   "message"
    t.boolean  "successful"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", :force => true do |t|
    t.string   "login",                                           :null => false
    t.text     "password_hash", :limit => 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "salt"
    t.boolean  "administrator",                :default => false, :null => false
  end

end
