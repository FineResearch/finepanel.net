# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProjectExportSetting do
  let(:body) do
    <<~TEXT
      natalia.mendez@fine-research.com, priscila@iqvia.com
      Quotas:
      q0tipo: A=40; B=80
      Report:
      quotaregiao x q0tipo
    TEXT
  end

  it 'normaliza el ID del proyecto a minuscula y sin espacios' do
    setting = described_class.create!(project_id: '  P588393362171 ', body: body)

    expect(setting.project_id).to eq('p588393362171')
  end

  it 'solo acepta IDs de Confirmit (p + digitos)' do
    setting = described_class.new(project_id: 'FP-18874N', body: body)

    expect(setting).not_to be_valid
    expect(setting.errors[:project_id].join).to include('ID de Confirmit')
  end

  it 'no admite dos configuraciones del mismo proyecto' do
    described_class.create!(project_id: 'p588393362171', body: body)

    expect(described_class.new(project_id: 'P588393362171', body: body)).not_to be_valid
  end

  it 'exige texto y lo limita a un largo razonable' do
    expect(described_class.new(project_id: 'p588393362171', body: '  ')).not_to be_valid
    expect(described_class.new(project_id: 'p588393362171', body: 'a' * (described_class::MAX_BODY_LENGTH + 1))).not_to be_valid
  end

  describe '.for_project' do
    it 'encuentra la configuracion sin importar mayusculas' do
      setting = described_class.create!(project_id: 'p588393362171', body: body)

      expect(described_class.for_project('P588393362171')).to eq(setting)
    end

    it 'devuelve nil si no hay ID o no hay configuracion' do
      expect(described_class.for_project(nil)).to be_nil
      expect(described_class.for_project('')).to be_nil
      expect(described_class.for_project('p999999999')).to be_nil
    end
  end

  describe '#recipients y #preview' do
    subject(:setting) { described_class.create!(project_id: 'p588393362171', body: body) }

    it 'saca las direcciones del texto' do
      expect(setting.recipients).to eq(%w[natalia.mendez@fine-research.com priscila@iqvia.com])
    end

    it 'muestra lo que el sistema entiende: direcciones, cuotas y cruces' do
      preview = setting.preview

      expect(preview[:recipients].length).to eq(2)
      expect(preview[:quotas]).to eq([{ variable: 'q0tipo', targets: [{ precode: 'A', meta: 40 }, { precode: 'B', meta: 80 }] }])
      expect(preview[:reports]).to eq([{ variable_a: 'quotaregiao', variable_b: 'q0tipo' }])
    end
  end
end
