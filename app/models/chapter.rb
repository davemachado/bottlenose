class Chapter < ActiveRecord::Base
  attr_accessible :course_id, :name, :questions_due

  belongs_to :course
  has_many :lessons, :dependent => :restrict
  has_many :assignments, :dependent => :restrict

  validates :course_id, :presence => true
  validates :name, :length => { :minimum => 2 }, 
                   :uniqueness => { :scope => :course_id }
end
