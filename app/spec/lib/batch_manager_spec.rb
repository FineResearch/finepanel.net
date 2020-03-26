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
  let(:on_conflict_action) { :nothing }
  let(:discard_conflicts_on) { [] }
  let(:batch_size) { 2 }
  let!(:manager) do
    BatchManager.new(model, insert_columns, discard_conflicts_on, on_conflict_action, batch_size)
  end
  let(:current_time) { Time.now }

  describe 'the insertion process' do
    subject do
      3.times do
        manager.add_to_batch(
          rand(1..100), rand(1..100), 'spanel', 'link', current_time, current_time, 'variables'
        )
      end

      manager.finish
    end

    it { expect { subject }.to change(SurveyLink, :count).by(3) }

    context 'when there is a conflict with a tuple and the action is insert' do
      let(:batch_size) { 3 }

      subject do
        manager.add_to_batch(1, 2, 'spanel', 'link', current_time, current_time, 'variables')
        manager.add_to_batch(1, 3, 'spanel', 'link', current_time, current_time, 'variables')
        manager.add_to_batch(1, 2, 'spanel', 'link', current_time, current_time + 1.day, 'variables')
      end

      it { expect { subject }.to raise_error(ActiveRecord::RecordNotUnique) }
    end

    context 'when there is a conflict but discard option is set' do
      let(:discard_conflicts_on) { [:project_id, :resp_id, :spanel, :link, :variables] }

      subject do
        manager.add_to_batch(1, 2, 'spanel', 'link', current_time, current_time, 'variables')
        manager.add_to_batch(3, 4, 'spanel', 'link', current_time, current_time, 'variables')
      end

      context 'when the conflicting keys are included in discard_conflicts_on' do
        context 'when the conflict is within the batch' do
          let(:batch_size) { 3 }

          before do
            manager.add_to_batch(
              1, 2, 'spanel', 'link', current_time, current_time + 1.day, 'variables'
            )
          end

          it { expect { subject }.to change(SurveyLink, :count).by(2) }
        end

        context 'when the conflict is with an existing tuple in the db' do
          let(:batch_size) { 2 }
          let!(:existing) do
            SurveyLink.create(
              project_id: 1, resp_id: 2, spanel: 'spanel', link: 'link',
              created_at: current_time, updated_at: current_time, variables: 'variables'
            )
          end

          it { expect { subject }.to change(SurveyLink, :count).by(1) }
        end
      end
    end

    context 'when there is a conflict with a tuple and the action is update' do
      let(:discard_conflicts_on) { [:project_id, :resp_id, :spanel, :link, :variables] }
      let(:on_conflict_action) { :update }

      subject do
        manager.add_to_batch(1, 2, 'spanel', 'link', current_time, current_time, 'variables')
        manager.add_to_batch(3, 4, 'spanel', 'link', current_time, current_time, 'variables')
      end

      context 'when the conflict is within the batch' do
        let(:batch_size) { 3 }

        before do
          manager.add_to_batch(
            1, 2, 'spanel', 'link', current_time, current_time + 1.day, 'variables'
          )
        end

        it { expect { subject }.to raise_error(ActiveRecord::StatementInvalid) }
      end

      context 'when the conflict is with an existing tuple in the db' do
        let(:batch_size) { 2 }
        let!(:existing) do
          SurveyLink.create(
            project_id: 1, resp_id: 2, spanel: 'spanel', link: 'link',
            created_at: current_time, updated_at: current_time - 1.day, variables: 'variables'
          )
        end

        it { expect { subject }.to change(SurveyLink, :count).by(1) }
        it { expect { subject; existing.reload }.to change { existing.updated_at } }
      end
    end

  end

end
