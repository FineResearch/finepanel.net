class WhatsappMessage < ApplicationRecord
  SOURCES = %w[webhook system agent template].freeze
  DIRECTIONS = %w[inbound outbound].freeze

  belongs_to :whatsapp_conversation
  belongs_to :internal_user, optional: true

  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :message_body, presence: true, unless: :template_message?
  validates :template_name, presence: true, if: :template_message?
  validates :template_language, presence: true, if: :template_message?

  before_validation :normalize_fields

  scope :inbound, -> { where(direction: 'inbound') }
  scope :outbound, -> { where(direction: 'outbound') }
  scope :chronological, -> { order(created_at: :asc) }
  scope :from_agents, -> { where(source: 'agent') }
  scope :templates, -> { where(source: 'template') }

  def inbound?
    direction == 'inbound'
  end

  def outbound?
    direction == 'outbound'
  end

  def template_message?
    source == 'template'
  end

  def agent_message?
    source == 'agent'
  end

  private

  def normalize_fields
    self.direction = direction.to_s.strip
    self.source = source.to_s.strip
    self.message_body = message_body.to_s.strip if message_body.present?
    self.template_name = template_name.to_s.strip if template_name.present?
    self.template_language = template_language.to_s.strip if template_language.present?
  end
end
