class License < ActiveRecord::Base
  validates :data, presence: true
  validate :valid_license
  validate :active_user_count, unless: :persisted?

  before_validation :reset_license, if: :data_changed?

  after_create :reset_current
  after_destroy :reset_current

  scope :previous, -> { order(created_at: :desc).offset(1) }

  class << self
    def current
      return @current if @current

      license = self.last
      return unless license && license.valid?

      @current = license
    end

    def reset_current
      @current = nil
    end

    def block_changes?
      !current || current.block_changes?
    end
  end

  def data_filename
    company_name = self.licensee["Company"] || self.licensee.values.first
    clean_company_name = company_name.gsub(/[^A-Za-z0-9]/, "")
    "#{clean_company_name}.gitlab-license"
  end

  def data_file
    return nil unless self.data

    Tempfile.new(self.data_filename) { |f| f.write(self.data) }
  end

  def data_file=(file)
    self.data = file.read
  end

  def license
    return nil unless self.data

    @license ||= Gitlab::License.import(self.data)
  end

  def license?
    self.license && self.license.valid?
  end

  def method_missing(method_name, *arguments, &block)
    if License.column_names.include?(method_name.to_s)
      super
    elsif license && license.respond_to?(method_name)
      license.send(method_name, *arguments, &block)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    if License.column_names.include?(method_name.to_s)
      super
    elsif license && license.respond_to?(method_name)
      true
    else
      super
    end
    (license && license.respond_to?(method_name)) || super
  end

  def active_user_restriction_exceeded?
    return false unless self.restricted?(:active_user_count)

    User.active.count > self.restrictions[:active_user_count]
  end

  private

  def reset_current
    self.class.reset_current
  end

  def reset_license
    @license = nil
  end

  def valid_license
    return if license?

    # TODO: Clearer message
    self.errors.add(:license, "is invalid.")
  end

  def active_user_count
    return unless self.license? && self.restricted?(:active_user_count)

    restricted_user_count = @license.restrictions[:active_user_count]
    active_user_count     = User.active.count

    return if active_user_count <= restricted_user_count

    self.errors.add(:base, "This license allows #{restricted_user_count} active users. This GitLab installation currently has #{active_user_count}, i.e. #{active_user_count - restricted_user_count} too many.")
  end
end
