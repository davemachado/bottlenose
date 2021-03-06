require 'securerandom'
require 'audit'

class Assignment < ActiveRecord::Base
  belongs_to :blame, :class_name => "User", :foreign_key => "blame_id"

  belongs_to :bucket
  belongs_to :course
  belongs_to :team_set

  has_many :submissions, :dependent => :restrict_with_error
  has_many :best_subs, :dependent => :destroy

  validates :name,      :uniqueness => { :scope => :course_id }
  validates :name,      :presence => true
  validates :course_id, :presence => true
  validates :due_date,  :presence => true
  validates :blame_id,  :presence => true
  validates :bucket_id, :presence => true
  validates :points_available, :numericality => true

  def team_for(user)
    if team_set.nil?
      self.team_set = course.solo_team_set
      save!
    end

    ut = TeamUser.where(user: user, team_set: team_set).first
    if ut.nil?
      if user.course_admin?(course)
        team_set.make_teacher_team!
      else
        nil
      end
    else
      ut.team
    end
  end

  def assignment_upload
    Upload.find_by_id(assignment_upload_id)
  end

  def grading_upload
    Upload.find_by_id(grading_upload_id)
  end

  def solution_upload
    Upload.find_by_id(solution_upload_id)
  end

  def assignment_file
    if assignment_upload_id.nil?
      ""
    else
      assignment_upload.file_name
    end
  end

  def assignment_file_name
    assignment_file
  end

  def grading_file
    if grading_upload_id.nil?
      ""
    else
      grading_upload.file_name
    end
  end

  def grading_file_name
    grading_file
  end

  def solution_file
    if solution_upload_id.nil?
      ""
    else
      solution_upload.file_name
    end
  end

  def solution_file_name
    solution_file
  end

  def assignment_full_path
    assignment_upload.full_path
  end

  def grading_full_path
    grading_upload.full_path
  end

  def assignment_file_path
    if assignment_upload_id.nil?
      ""
    else
      assignment_upload.path
    end
  end

  def grading_file_path
    if grading_upload_id.nil?
      ""
    else
      grading_upload.path
    end
  end

  def solution_file_path
    if solution_upload_id.nil?
      ""
    else
      solution_upload.path
    end
  end

  def assignment_file=(data)
    @assignment_file_data = data
  end

  def grading_file=(data)
    @grading_file_data = data
  end

  def solution_file=(data)
    @solution_file_data = data
  end

  def has_grading?
    !grading_upload_id.nil?
  end

  def save_uploads!
    user = User.find(blame_id)

    unless @assignment_file_data.nil?
      unless assignment_upload_id.nil?
        Audit.log("Assn #{id}: Orphaning assignment upload " +
                  "#{assignment_upload_id} (#{assignment_upload.secret_key})")
      end

      up = Upload.new
      up.user_id = user.id
      up.store_meta!({
        type:       "Assignment File",
        user:       "#{user.name} (#{user.id})",
        course:     "#{course.name} (#{course.id})",
        date:       Time.now.strftime("%Y/%b/%d %H:%M:%S %Z")
      })
      up.store_upload!(@assignment_file_data)
      up.save!

      self.assignment_upload_id = up.id
      self.save!

      Audit.log("Assn #{id}: New assignment file upload by #{user.name} " +
                "(#{user.id}) with key #{up.secret_key}")
    end

    unless @grading_file_data.nil?
      unless assignment_upload_id.nil?
        Audit.log("Assn #{id}: Orphaning grading upload " +
                  "#{assignment_upload_id} (#{assignment_upload.secret_key})")
      end

      up = Upload.new
      up.user_id = user.id
      up.store_meta!({
        type:       "Assignment Grading File",
        user:       "#{user.name} (#{user.id})",
        course:     "#{course.name} (#{course.id})",
        date:       Time.now.strftime("%Y/%b/%d %H:%M:%S %Z")
      })
      up.store_upload!(@grading_file_data)
      up.save!

      self.grading_upload_id = up.id
      self.save!

      Audit.log("Assn #{id}: New grading file upload by #{user.name} " +
                "(#{user.id}) with key #{up.secret_key}")
    end

    unless @solution_file_data.nil?
      unless solution_upload_id.nil?
        Audit.log("Assn #{id}: Orphaning solution upload " +
                  "#{solution_upload_id} (#{solution_upload.secret_key})")
      end

      up = Upload.new
      up.user_id = user.id
      up.store_meta!({
        type:       "Assignment Solution File",
        user:       "#{user.name} (#{user.id})",
        course:     "#{course.name} (#{course.id})",
        date:       Time.now.strftime("%Y/%b/%d %H:%M:%S %Z")
      })
      up.store_upload!(@solution_file_data)
      up.save!

      self.solution_upload_id = up.id
      self.save!

      Audit.log("Assn #{id}: New solution file upload by #{user.name} " +
                "(#{user.id}) with key #{up.secret_key}")
    end
  end

  def tarball_path
    if tar_key.blank?
      self.tar_key = SecureRandom.hex(16)
      save!
    end

    dir = "downloads/#{tar_key}/"
    FileUtils.mkdir_p(Rails.root.join('public', dir))

    return '/' + dir + "assignment_#{id}.tar.gz"
  end

  def tarball_full_path
    Rails.root.join('public', tarball_path.sub(/^\//, ''))
  end

  def submissions_for(user)
    Submission.
      joins("JOIN teams ON submissions.team_id = teams.id JOIN team_users ON team_users.team_id = teams.id").
      where("team_users.user_id = ? and submissions.assignment_id = ?", user.id, self.id).
      order(:created_at).reverse
  end

  def best_sub_for(user)
    bs = BestSub.where(user_id: user.id, assignment_id: self.id).first
    if bs.nil?
      Submission.new(user_id: user.id, assignment_id: self.id)
    else
      bs.submission
    end
  end

  def main_submissions
    regs = course.active_registrations.sort_by {|sr| sr.user.invert_name.downcase  }
    subs = regs.map do |sreg|
      best_sub_for(sreg.user)
    end
  end

  def update_best_subs!
    course.registrations.each do |reg|
      begin
        update_best_sub_for!(reg.user)
      rescue Exception
      end
    end
  end

  def update_best_sub_for!(user)
    sub = calc_best_sub_for(user)

    if sub.nil?
      BestSub.where(user_id: user.id, assignment_id: self.id).each do |bs|
        bs.destroy
      end
      return
    end

    best = BestSub.find_or_initialize_by(user_id: user.id, assignment_id: self.id)
    best.submission_id = sub.id
    best.score = sub.score
    best.save!
  end

  def calc_best_sub_for(user)
    subs = submissions_for(user)
    if subs.empty?
      return nil
    end

    teacher_scores = subs.find_all {|ss| not ss.teacher_score.nil? }

    if teacher_scores.empty?
      subs.sort_by do |ss|
        sprintf("%06d%014d", ss.score || 0, ss.created_at.to_i)
      end.last
    else
      teacher_scores.sort_by {|ss| ss.score }.last
    end
  end

  def update_teams!
    submissions.each do |sub|
      sub.team = team_for(sub.user)
      sub.save!
    end

    update_best_subs!
  end
end

