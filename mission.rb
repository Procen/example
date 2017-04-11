class Mission < ApplicationRecord
  validates :title, presence: true
  validates :description, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :missions_ranks, length: { minimum: Rank.count }

  validate :check_mission_length

  belongs_to :category
  belongs_to :admin
  has_many :user_missions, dependent: :destroy
  has_many :ranks, through: :missions_ranks
  has_many :missions_ranks, dependent: :destroy

  accepts_nested_attributes_for :missions_ranks

  has_attached_file :logo, styles: { medium: '300x300>', thumb: '100x100>' },
                           default_url: '/:class/:id/:filename'
  has_attached_file :image, styles: { medium: '300x300>', thumb: '100x100>' },
                            default_url: '/:class/:id/:filename'

	validates_attachment_content_type :logo, content_type: /image\/.*/
	validates_attachment_content_type :image, content_type: /image\/.*/

  scope :available, -> { where("end_date::date >= ? AND start_date::date <= ?", Date.today, Date.today) }
  scope :upcoming, -> { where("start_date::date > ?", Date.today).order(start_date: :ASC) }
  scope :finished, -> { where("end_date::date < ?", Date.today).order(start_date: :ASC) }

  # scope :to_review, -> {joins(:user_missions).merge(UserMission.pending)}
  scope :to_review, -> {joins(:user_missions).includes(:missions_ranks).where("user_missions.state = ?", :pending).uniq}

  scope :favorites, -> {  where(is_favorite: true)  }

  EXCEPT_OPTIONS =
    [
      :created_at, :updated_at, :category_id,
      :logo_file_name, :logo_content_type,
      :logo_file_size, :logo_updated_at,
      :image_file_name, :image_content_type,
      :image_file_size, :image_updated_at
    ]

  MY_OPTIONS =
    {
      methods: [
        :mission_logo_path, :mission_image_path, :review_count, :viewers_count,
        :posts_count, :approved_count, :rejected_count, :cost, :photo_links, :status,
        :missions_ranks_attributes, :has_more_photos
      ]
    }

  CREATE_OPTIONS =
    {
      except: EXCEPT_OPTIONS + [:is_favorite, :hash_tags, :other_requirements],
      methods: [:mission_logo_path,  :mission_image_path]
    }

  def as_json(options = {})
    options[:methods] = [:company_name, :mission_logo_path, :mission_image_path] if options[:methods].blank?
    options[:except] = options[:except].to_a + EXCEPT_OPTIONS
    super(options)
  end

  def upcoming?
    start_date.to_date > Date.today
  end

  def available?
    end_date.to_date >= Date.today && start_date.to_date <= Date.today
  end

  def finished?
    end_date.to_date < Date.today
  end

  def self.to_csv(missions)
    headers = %w(
      Title Description StartDate EndDate CategoryId AdminId IsFavorite HashTags OtherRequirements
      MissionLogoPath MissionImagePath ReviewCount ViewersCount PostsCount ApprovedCount
      RejectedCount Cost CreatedAt MissionsRanksAttributes
    )

    dir_path = "#{Rails.public_path}/exports"
    FileUtils.mkdir_p(dir_path) unless File.directory?(dir_path)
    FileUtils.rm_rf(Dir.glob("#{dir_path}/*.csv"))
    file_path = "#{dir_path}/missions_export#{Time.now.strftime('%d_%m_%Y')}.csv"

    CSV.open(file_path, 'wb') do |csv|
        csv << headers
        missions.each do |m|
            values = [
                m.title, m.description, m.start_date, m.end_date, m.category_id, m.admin_id,
                m.is_favorite, m.hash_tags, m.other_requirements, m.mission_logo_path,
                m.mission_image_path, m.review_count, m.viewers_count, m.posts_count,
                m.approved_count, m.rejected_count, m.cost, m.created_at,
                m.missions_ranks_attributes
            ]
            csv << values
        end
    end
    file_path
  end

  def mission_logo_path
    logo.url(:medium) if logo?
  end

  def mission_image_path
    image.url(:original) if image?
  end

  def review_count
    user_missions.pending.count
  end

  def posts_count
    user_missions.count
  end

  def approved_count
    user_missions.approved.count
  end

  def rejected_count
    user_missions.user_deleted.count
  end

  def cost
    user_ids = user_missions.approved.pluck(:user_id)
    group_users = User.find(user_ids).group_by(&:rank_id)
    ranks = Rank.all.group_by(&:id)
    group_users.map { |id, users| users.count * ranks[id].first.fee }.sum
  end

  def viewers_count
    user_missions.map(&:user).sum(&:instagram_followers)
  end

  def missions_ranks_attributes
    all_ranks = Rank.all.group_by(&:id)
    missions_ranks.map do |mission_rank|
      {
        mission_rank_id: mission_rank.id,
        rank_id: mission_rank.rank_id,
        mission_id: mission_rank.mission_id,
        fee: mission_rank.fee
      }
    end
  end

  def self.print_mission_report(mission_id)
    mission = Mission.where(id: mission_id).includes(:missions_ranks, :admin).first
    advertiser = mission.admin
    ranks = Rank.all
    mission_ranks = mission.missions_ranks
    rank_approved = {}
    Rank.all.each { |rank| rank_approved[rank.name] = 0 }
    user_missions = UserMission.where(mission_id: mission_id, state: :approved).includes(user: :rank)
    user_missions.each { |item| rank_approved[item.user.rank.name] += 1 }
    users = User.where(id: user_missions.map(&:user_id))
    ranks_ids = users.map(&:rank_id)

    cost = ranks.sum do |rank|
      ranks_ids.count(rank.id) * mission_ranks.find { |item| item.rank_id == rank.id }.try(:fee).to_i
    end

    estimated_viewers = users.sum(&:instagram_followers)
    {
      mission_id: mission_id,
      advertiser_name: advertiser.name,
      advertiser_email: advertiser.email,
      title: mission.title,
      approved_count: user_missions.size,
      rank_approved: rank_approved,
      estimated_viewers: estimated_viewers,
      fees: cost,
      cost: cost
    }
  end

private

  def check_mission_length
    setting = Setting.first
    if (start_date.to_date..end_date.to_date).to_a.count > setting.mission_length
      message = "Your date range available mission must
              be within #{setting.mission_length} days"
      errors.add(:mission_length, message)
      return false
    end
    true
  end


  def has_more_photos
    user_missions.approved.count > 10
  end


  def company_name
    admin.name if admin.present?
  end


  def photo_links
    user_missions.approved.limit(10).map do |user_mission|
      {
        id: user_mission.id,
        thumb_mission_photo_path:
          user_mission.mission_photo? ? user_mission.mission_photo.url(:thumb) : nil,
        original_mission_photo_path:
          user_mission.mission_photo? ? user_mission.mission_photo.url(:original) : nil
      }
    end.compact
  end

  def status
    if available?
      'available'
    elsif upcoming?
      'upcoming'
    else
      'finished'
    end
  end

end
