class RegRequest < ActiveRecord::Base
  validates_presence_of :course_id, :user_id

  belongs_to :course
  belongs_to :user

  delegate :name, :email, to: :user

  def registered?
    course.users.any? {|uu| uu.id == user_id }
  end
end
