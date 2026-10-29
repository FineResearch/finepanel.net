# frozen_string_literal: true

# Serves the static shell only -- same pattern as
# Internal::FinePanelSetup::SetupController#index. All real functionality
# (upload, status, results) talks directly to the separate Automated
# Transcripts API (its own repo/AWS infra, see FineResearch/automated-transcripts)
# from the browser; this app's only involvement is the shared login
# (see Internal::AuthController#whoami).
class Internal::AutomatedTranscripts::SetupController < ApplicationController
  def index
    render file: Rails.root.join('public', 'automated-transcripts', 'index.html'), layout: false
  end
end
