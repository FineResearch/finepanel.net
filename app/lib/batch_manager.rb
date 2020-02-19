class BatchManager

  DEFAULT_BATCH_SIZE = 5000

  attr_accessor :values

  def initialize(model, insert_columns, discard_conflicts_on = [],
                 on_conflict_action = :nothing, batch_size = DEFAULT_BATCH_SIZE)

    @values = []
    @model = model
    @batch_size = batch_size
    @discard_conflicts_on = discard_conflicts_on
    @insert_columns = insert_columns
    @on_conflict_action = on_conflict_action
  end

  def add_to_batch(*tuple)
    @values << "(#{prepare_for_insert(tuple)})"

    flush if can_execute_batch?
  end

  def flush
    logger.info("Starting flushing batch with #{@values.size} tuples")

    @model.connection.execute(sql)

    @values = []

    logger.info("Flushing tuples finished")
  end

  def finish
    flush
  end

  private

  def sql
    sql = "INSERT INTO #{@model.table_name} (#{@insert_columns.join(', ')}) VALUES #{@values.join(',')}"

    if @discard_conflicts_on.any?
      sql += " ON CONFLICT (#{@discard_conflicts_on.join(', ')}) #{on_conflict_action}"
    end

    sql
  end

  def on_conflict_action
    if @on_conflict_action == :nothing
      'DO NOTHING'
    elsif @on_conflict_action == :update
      update_sql = @insert_columns.map do |column|
        "#{column} = EXCLUDED.#{column}"
      end

      "DO UPDATE SET #{update_sql.join(', ') }"
    end
  end

  def can_execute_batch?
    @values.size == @batch_size
  end

  def prepare_for_insert(values)
    values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(',')
  end

  def logger
    @logger ||= Logger.new("log/sync_survey_links_#{Rails.env}.log", 'monthly')
  end
end
