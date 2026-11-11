# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportMissingVariableAlert do
  describe '.not_alerted' do
    it 'devuelve todas las variables si el proyecto nunca se aviso' do
      expect(described_class.not_alerted('p1', %w[q5a q6])).to eq(%w[q5a q6])
    end

    it 'saca las que ya se avisaron para ese proyecto' do
      described_class.register('p1', %w[q5a])

      expect(described_class.not_alerted('p1', %w[q5a q6])).to eq(%w[q6])
    end

    it 'compara sin importar mayusculas' do
      described_class.register('p1', %w[Q5A])

      expect(described_class.not_alerted('p1', %w[q5a])).to eq([])
    end

    it 'un aviso de un proyecto no afecta a otro' do
      described_class.register('p1', %w[q5a])

      expect(described_class.not_alerted('p2', %w[q5a])).to eq(%w[q5a])
    end
  end

  describe '.register' do
    it 'es idempotente: registrar dos veces la misma variable no falla ni duplica' do
      described_class.register('p1', %w[q5a])

      expect { described_class.register('p1', %w[q5a Q5A]) }.not_to raise_error
      expect(described_class.where(project_id: 'p1').count).to eq(1)
    end
  end
end
