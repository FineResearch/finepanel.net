require 'rails_helper'

RSpec.describe WhatsApp::PhoneNormalizer do
  describe '.normalize' do
    it 'strips non-digit characters' do
      expect(described_class.normalize('+55 (11) 99999-9999')).to eq('5511999999999')
    end

    it 'strips the Mexican mobile "1" prefix (521XXXXXXXXXX -> 52XXXXXXXXXX)' do
      expect(described_class.normalize('5215512345678')).to eq('525512345678')
    end

    it 'leaves a Mexican number without the extra 1 unchanged' do
      expect(described_class.normalize('525512345678')).to eq('525512345678')
    end

    it 'does not alter Brazilian numbers (normalize is only for display/storage/routing)' do
      expect(described_class.normalize('559187097562')).to eq('559187097562')
      expect(described_class.normalize('5591987097562')).to eq('5591987097562')
    end

    it 'returns an empty string for blank input' do
      expect(described_class.normalize(nil)).to eq('')
      expect(described_class.normalize('')).to eq('')
    end
  end

  describe '.brazil_match_variants' do
    it 'adds the missing "9" variant for a 12-digit Brazilian number' do
      expect(described_class.brazil_match_variants('559187097562'))
        .to contain_exactly('559187097562', '5591987097562')
    end

    it 'adds the without-"9" variant for a 13-digit Brazilian number' do
      expect(described_class.brazil_match_variants('5591987097562'))
        .to contain_exactly('5591987097562', '559187097562')
    end

    it 'returns a single variant for non-Brazilian numbers' do
      expect(described_class.brazil_match_variants('525512345678')).to eq(['525512345678'])
    end

    it 'returns a single variant for blank input' do
      expect(described_class.brazil_match_variants('')).to eq([''])
    end

    it 'does not duplicate a variant that is already unambiguous either way' do
      # 9 digits after country code (neither 10 nor 11) - leave as-is, no guessing.
      expect(described_class.brazil_match_variants('5511123')).to eq(['5511123'])
    end
  end
end
