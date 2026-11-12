# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ExportRecipients do
  it 'extrae las direcciones del texto, sin repetirlas' do
    text = 'natalia@fine-research.com, otra@iqvia.com; natalia@fine-research.com'

    expect(described_class.extract(text)).to eq(%w[natalia@fine-research.com otra@iqvia.com])
  end

  it 'ignora info@fine-research.com (contacto del disclaimer legal de Confirmit)' do
    expect(described_class.extract('INFO@fine-research.com dcasar@fine-research.com')).to eq(%w[dcasar@fine-research.com])
  end

  it 'devuelve vacio si no hay direcciones o el texto es nil' do
    expect(described_class.extract('sin direcciones')).to eq([])
    expect(described_class.extract(nil)).to eq([])
  end
end
