require 'gdocs_export'
require 'course_refresher'
require 'system_commands'
require 'date_and_time_utils'

class Course < ActiveRecord::Base
  include SystemCommands

  self.include_root_in_json = false

  validates :name,
            :presence   => true,
            :uniqueness => true,
            :length     => { :within => 1..40 },
            :format     => {
              :without => / /,
              :message  => 'should not contain white spaces'
            }

  validates :source_url, :presence => true
  validate :check_source_backend
  after_initialize :set_default_source_backend

  has_many :exercises, :dependent => :delete_all
  has_many :submissions, :dependent => :delete_all
  has_many :available_points, :through => :exercises
  has_many :awarded_points, :dependent => :delete_all
  has_many :test_scanner_cache_entries, :dependent => :delete_all
  has_many :feedback_questions, :dependent => :delete_all
  has_many :feedback_answers  # destroyed transitively when questions are destroyed
  has_many :student_events, :dependent => :delete_all

  def destroy
    # Optimization: delete dependent objects quickly.
    # Rails' :dependent => :delete_all is very slow.
    # Even self.association.delete_all first does a SELECT.
    # This relies on the database to cascade deletes.
    self.connection.execute("DELETE FROM courses WHERE id = #{self.id}")

    # Delete cache.
    delete_cache # Would be an after_destroy callback normally
  end

  scope :ongoing, lambda { where(["hide_after IS NULL OR hide_after > ?", Time.now]) }
  scope :expired, lambda { where(["hide_after IS NOT NULL AND hide_after <= ?", Time.now]) }

  def visible_to?(user)
    user.administrator? || (
      !hidden &&
      (hide_after == nil || hide_after > Time.now) &&
      (hidden_if_registered_after == nil || (!user.guest? && hidden_if_registered_after > user.created_at))
    )
  end

  def hide_after=(x)
    super(DateAndTimeUtils.to_time(x, :prefer_end_of_day => true))
  end

  def hidden_if_registered_after=(x)
    super(DateAndTimeUtils.to_time(x, :prefer_end_of_day => false))
  end

  def options=(new_options)
    if !new_options["hide_after"].blank?
      self.hide_after = new_options["hide_after"]
    else
      self.hide_after = nil
    end

    if !new_options["hidden_if_registered_after"].blank?
      self.hidden_if_registered_after = new_options["hidden_if_registered_after"]
    else
      self.hidden_if_registered_after = nil
    end

    self.hidden = !!new_options['hidden']
    self.spreadsheet_key = new_options['spreadsheet_key']
  end

  def self.default_options
    {
      :hidden => false,
      :hide_after => nil
    }
  end

  def gdocs_sheets(exercises = nil)
    exercises = self.exercises.select(&:visible_to_users?) unless exercises
    exercises.map(&:gdocs_sheet).reject(&:nil?).uniq
  end

  def refresh_gdocs_worksheet sheetname
    GDocsExport.refresh_course_worksheet_points self, sheetname
  end
  
  def self.cache_root
    "#{FileStore.root}/course"
  end

  def cache_path
    "#{Course.cache_root}/#{self.name}-#{self.cache_version}"
  end
  
  # A clone of the course repository
  def clone_path
    "#{cache_path}/clone"
  end

  def git_revision
    begin
      Dir.chdir clone_path do
        output = `git rev-parse --verify HEAD`
        if $?.success?
          output.strip
        else
          nil
        end
      end
    rescue
      nil
    end
  end
  
  # Directory for solutions
  def solution_path
    "#{cache_path}/solution"
  end
  
  # Directory for stubs
  def stub_path
    "#{cache_path}/stub"
  end
  
  # Directory for zips of the stubs
  def stub_zip_path
    "#{cache_path}/stub_zip"
  end

  def solution_zip_path
    "#{cache_path}/solution_zip"
  end
  
  def refresh
    CourseRefresher.new.refresh_course(self)
  end
  
  def delete_cache
    FileUtils.rm_rf cache_path
  end
  
  def self.valid_source_backends
    ['git']
  end
  
  def self.default_source_backend
    'git'
  end

  def time_of_first_submission
    sub = self.submissions.order('created_at ASC').limit(1).first
    if sub
      sub.created_at
    else
      nil
    end
  end

  def time_of_last_submission
    sub = self.submissions.order('created_at DESC').limit(1).first
    if sub
      sub.created_at
    else
      nil
    end
  end

  def reviews_required(include_reviewed = false)
    result = self.submissions.where(:requires_review => true)
    result = result.where(:reviewed => false) unless include_reviewed
    result
  end

  def reviews_requested(include_reviewed = false)
    result = self.submissions.where(:requests_review => true)
    result = result.where(:reviewed => false) unless include_reviewed
    result
  end

  def submissions_to_review
    self.submissions.where('(requests_review OR requires_review) AND NOT reviewed')
  end

  # Returns a hash of exercise group => {
  #   :available_points => number of available points,
  #   :points_by_user => {user_id => number_of_points}
  # }
  def exercise_group_completion_by_user
    #TODO: clean up exercise group discovery

    groups = self.exercises.map(&:name).map {|name| if name =~ /^(.+)-[^-]+$/ then $1 else "" end }.uniq

    result = {}
    for group in groups
      conn = self.connection

      # FIXME: this bit is duplicated in MetadataValue in master branch.
      # http://stackoverflow.com/questions/5709887/a-proper-way-to-escape-when-building-like-queries-in-rails-3-activerecord
      pattern = (group.gsub(/[!%_]/) {|x| '!' + x }) + '-%'

      sql = <<EOS
SELECT available_points.name
FROM exercises, available_points
WHERE exercises.course_id = #{conn.quote(self.id)} AND
      exercises.name LIKE #{conn.quote(pattern)} AND
      exercises.id = available_points.exercise_id
EOS
      available_points = conn.select_values(sql)
      next if available_points.empty?

      sql = <<EOS
SELECT user_id, COUNT(*)
FROM awarded_points
WHERE course_id = #{conn.quote(self.id)} AND
      name IN (#{available_points.map {|ap| conn.quote(ap)}.join(',')})
GROUP BY user_id
EOS
      by_user = Hash[conn.select_rows(sql).map! {|uid, count| [uid.to_i, count.to_i]}]

      result[group] = {
        :available_points => available_points.size,
        :points_by_user => by_user
      }
    end
    result
  end

  
private
  def check_source_backend
    unless Course.valid_source_backends.include?(source_backend)
      errors.add(:source_backend, 'must be one of [' + Course.valid_source_backends.join(', ') + "]")
    end
  end
  
  def set_default_source_backend
    self.source_backend ||= Course.default_source_backend
  end
end

