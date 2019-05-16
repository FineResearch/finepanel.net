# frozen_string_literal: true

module ApplicationHelper
  def resource_error_messages(resource)
    if resource.errors.any?
      render 'resource_messages', messages: resource.errors.full_messages
    end
  end
end
