require 'spec_helper'

require 'app/models/survey_link'
require 'lib/batch_manager'

describe 'BatchManager' do

  let(:model) { SurveyLink }
  let(:insert_columns) do
    [
      :project_id, :resp_id, :spanel, :link, :created_at, :updated_at, :variables
    ] # all columns in this case
  end
  let(:discard_conflicts_on) { [] }
  let(:batch_size) { 2 }
  let!(:manager) do
    BatchManager.new(model, insert_columns, discard_conflicts_on, :nothing, batch_size)
  end

  describe 'the insertion process' do
    subject do
      3.times do
        current_time = Time.now
        manager.add_to_batch(
          rand(1..100), rand(1..100), 'spanel', 'link', current_time, current_time, 'variables'
        )
      end

      manager.finish
    end

    it { expect { subject }.to change(SurveyLink, :count).by(3) }

    context 'when there is a conflict with a tuple' do
      let(:batch_size) { 3 }

      subject do
        current_time = Time.now

        manager.add_to_batch(1, 2, 'spanel', 'link', current_time, current_time, 'variables')
        manager.add_to_batch(1, 3, 'spanel', 'link', current_time, current_time, 'variables')
        manager.add_to_batch(1, 2, 'spanel', 'link', current_time, current_time, 'variables')
      end

      it { expect { subject }.to raise_error(ActiveRecord::RecordNotUnique) }

      context 'when the conflicting keys are included in discard_conflicts_on' do
        let(:discard_conflicts_on) { [:project_id, :resp_id, :spanel, :link, :variables] }

        it { expect { subject }.to change(SurveyLink, :count).by(2) }
      end
    end
  end

end
