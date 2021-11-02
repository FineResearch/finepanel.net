LastParticipationPresenter = Struct.new(:participation, :participations) do
  def last_participations
    { lastParticipation: participation, participations: participations }
  end
end
