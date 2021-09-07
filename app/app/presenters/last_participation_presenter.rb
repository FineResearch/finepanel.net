LastParticipationPresenter = Struct.new(:participation) do
  def last_participation
    { participations: participation }
  end
end
