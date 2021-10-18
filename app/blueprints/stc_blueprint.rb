class StcBlueprint < Blueprinter::Base
  field :stcMx do |stc|
    stc[:stc_mx]
  end

  field :stcCol do |stc|
    stc[:stc_col]
  end
end
