# frozen_string_literal: true

class SurveysController < ApplicationController
  before_action :verify_permissions!

  def list_all_projects
    @projects = SurveyLink.pluck(:project_id).uniq
    render 'list_all_projects'
  end

  private

  def verify_permissions!
    return redirect_to root_path unless current_user.admin?
  end
end
