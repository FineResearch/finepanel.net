# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ConfirmitExportEmailParser do
  it 'extrae Survey Name e Interview Status Filter de un mail real de Rule de Confirmit' do
    body = <<~BODY
      Attached to this email you will find the survey data export of "FP-18358N - 3418357_ATU CPNPC Early Stages Imfinzi"
      Survey ID: p833174000229
      Survey Name: "FP-18358N - 3418357_ATU CPNPC Early Stages Imfinzi"
      Active Database: Production
      Format: SPSS (sps/dat)
      Character Encoding: utf-8
      Decimal Delimiter: .
      Data file: SPSSOutput.dat
      Schema file: SPSSOutput.sps
      Interview Status Filter: All(unfiltered)
      Export completed at 9/30/2026 5:55:53 PM
      Comment: dcasar@fine-research.com

      The information contained in this email message may be privileged, confidential or exempt from disclosure under applicable law.
    BODY

    result = described_class.call(body)

    expect(result[:project_title]).to eq('FP-18358N - 3418357_ATU CPNPC Early Stages Imfinzi')
    expect(result[:interview_status_filter]).to eq('All(unfiltered)')
  end

  it 'tambien funciona si los campos vienen separados por tabs en una sola linea (tal cual se vio en un envio real)' do
    body = "Survey ID: p833174000229\t Survey Name: \"FP-18358N - Imfinzi\"\t Interview Status Filter: All(unfiltered)\t Comment: dcasar@fine-research.com"

    result = described_class.call(body)

    expect(result[:project_title]).to eq('FP-18358N - Imfinzi')
    expect(result[:interview_status_filter]).to eq('All(unfiltered)')
  end

  it 'devuelve nil para ambos campos cuando el mail no trae la metadata de Confirmit (ej. un test manual de un PM)' do
    result = described_class.call("dcasar@fine-research.com\n\nQuotas:\nS0: 1=50")

    expect(result[:project_title]).to be_nil
    expect(result[:interview_status_filter]).to be_nil
  end

  it 'no rompe con un body nil' do
    result = described_class.call(nil)

    expect(result[:project_title]).to be_nil
    expect(result[:interview_status_filter]).to be_nil
  end
end
