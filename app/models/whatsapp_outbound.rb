class WhatsappOutbound < ApplicationRecord
  belongs_to :user, optional: true
end
