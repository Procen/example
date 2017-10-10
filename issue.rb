class Issue
  include Mongoid::Document
  include Mongoid::Timestamps
  extend Enumerize

  after_create :send_mail

  validates :uid, uniqueness: true
  has_many :comments, as: :commentable

  field :uid, type: Integer
  field :title, type: String
  field :description, type: String
  field :name, type: String # username
  field :gps, type: Array

  field :status
  field :priority
  field :issue_category
  field :issue_type
  field :region
  field :report_id

  enumerize :status, in: ['Open', 'In progress', 'Solved', 'Cancelled']
  enumerize :priority, in: ['Low', 'Medium', 'High', 'Critical']
  enumerize :issue_category, in: ['Content', 'IT equipment', 'Network', 'Power/solar',
                                  'Security', 'Training', 'Other']
  enumerize :issue_type, in: ['Problem', 'Request', 'Suggestion', 'Missing/Faulty', 'Information']
  enumerize :region, in: ['Ecole Primaire', 'Centre Don Bosco', 'CME', 'Ecole Primaire',
                          'Central', 'Dadaab YEP', 'Dagahaley YEP', 'Hagadera YEP',
                          'Hilal', 'Hormud', 'Horseed', 'Ifo YEP', 'Juba', 'Mwangaza',
                          'Nasib', 'Tawakal', 'Waberi', 'Community Library',
                          'Greenlight', 'JC:HEM', 'Jolie Boarding School',
                          'Kakuma Secondary', 'Morneau Shepell', 'Napata', 'Soba Sec',
                          'Amani', 'Amitie', 'Fraternite', 'Hodari', 'Lycee de la Paix', 'Rehema',
                          ]
  def send_mail
    email_list = [
        'Justin.Waller@vodafone.com',
        'walter.saunders@vodafone.com',
        'awiti@unhcr.org',
        'albane@instantnetwork.org',
        'vf@viewworld.net'
    ]

    email_list << Report.find(self.report_id).user_email
    IssueMailer.new_request(email_list, self.id.to_s, self.name).deliver_later
  end
end
