class IndividualPushpet < ApplicationRecord
  UNSET = Object.new.freeze
  SPECIES = %w[goat_dragon raccoon star_axolotl].freeze
  COLORS = %w[blue pink green purple orange white].freeze
  ACCESSORIES = %w[none ruby_crown javascript_shades typescript_visor python_wizard_hat rust_armor_accent go_jetpack caretaker_crown].freeze
  EQUIPMENT_SLOTS = %w[head face chest legs back].freeze
  BACKGROUNDS = %w[petplace1 petplace2 petplace3].freeze

  before_validation :normalize_username
  before_validation :set_defaults

  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :species, inclusion: { in: SPECIES }
  validates :color, inclusion: { in: COLORS }
  validates :accessory, inclusion: { in: ACCESSORIES }
  validates :background, inclusion: { in: BACKGROUNDS }
  validates :display_name, length: { maximum: 28 }, allow_blank: true

  def self.find_by_username(username)
    where("lower(username) = ?", username.to_s.strip.downcase).first
  end

  def equip!(slot:, accessory:)
    clean_slot = slot.to_s
    clean_accessory = ACCESSORIES.include?(accessory.to_s) ? accessory.to_s : "none"
    equipment = equipped_accessories.to_h.slice(*EQUIPMENT_SLOTS)

    if clean_accessory == "none"
      equipment.delete(clean_slot)
    elsif EQUIPMENT_SLOTS.include?(clean_slot)
      equipment[clean_slot] = clean_accessory
    end

    update!(
      equipped_accessories: equipment,
      accessory: equipment.values.first || "none"
    )
  end

  def update_background!(background:)
    clean_background = BACKGROUNDS.include?(background.to_s) ? background.to_s : "petplace1"
    update!(background: clean_background)
  end

  def customize!(display_name: UNSET, species: UNSET, color: UNSET, background: UNSET)
    attributes = {}
    attributes[:display_name] = clean_display_name(display_name) unless display_name.equal?(UNSET)
    attributes[:species] = SPECIES.include?(species.to_s) ? species.to_s : self.species unless species.equal?(UNSET)
    attributes[:color] = COLORS.include?(color.to_s) ? color.to_s : self.color unless color.equal?(UNSET)
    attributes[:background] = BACKGROUNDS.include?(background.to_s) ? background.to_s : self.background unless background.equal?(UNSET)

    update!(attributes)
  end

  def as_api
    {
      username: username,
      display_name: display_name,
      species: species,
      color: color,
      accessory: accessory,
      equipped: equipped_accessories.to_h,
      background: background,
      hatched_at: hatched_at&.iso8601
    }
  end

  private

  def normalize_username
    self.username = username.to_s.strip
  end

  def set_defaults
    self.hatched_at ||= Time.current
    self.equipped_accessories ||= {}
    self.accessory = "none" if accessory.blank?
    self.background = "petplace1" if background.blank?
    self.display_name = clean_display_name(self.display_name)
  end

  def clean_display_name(value)
    value.to_s.strip.presence&.[](0, 28)
  end
end
