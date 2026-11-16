# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::InternalAlertRecipients do
  it 'devuelve todas las direcciones @fine-research.com, sin repetir ni mezclar mayusculas, y nunca las del cliente' do
    result = described_class.call(
      ['cliente@iqvia.com', 'Natalia@Fine-Research.com', 'dcasar@fine-research.com', 'natalia@fine-research.com']
    )

    expect(result).to eq(['Natalia@Fine-Research.com', 'dcasar@fine-research.com'])
  end

  it 'si no hay ninguna de Fine (lista solo de clientes), usa panel@fine-research.com por default' do
    expect(described_class.call(['cliente@iqvia.com'])).to eq(['panel@fine-research.com'])
  end

  it 'sin destinatarios (nil o vacio), usa el default' do
    expect(described_class.call(nil)).to eq(['panel@fine-research.com'])
    expect(described_class.call([])).to eq(['panel@fine-research.com'])
  end
end
