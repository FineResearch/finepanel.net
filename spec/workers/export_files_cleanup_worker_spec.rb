# frozen_string_literal: true

require 'rails_helper'
require 'fileutils'

RSpec.describe ExportFilesCleanupWorker do
  before do
    @tmp_root = Dir.mktmpdir
    dirs = [File.join(@tmp_root, 'export'), File.join(@tmp_root, 'relabel_spss'), File.join(@tmp_root, 'relabel_excel')]
    dirs.each { |d| FileUtils.mkdir_p(d) }
    stub_const("#{described_class}::SWEEP_DIRS", dirs.map { |d| Pathname.new(d) })
  end

  after { FileUtils.rm_rf(@tmp_root) }

  def touch_with_age(path, age)
    FileUtils.touch(path)
    time = age.ago.to_time
    File.utime(time, time, path)
  end

  it 'borra archivos/directorios mas viejos que MAX_AGE en cada carpeta vigilada' do
    old_file = File.join(described_class::SWEEP_DIRS[0], 'old_export.zip')
    touch_with_age(old_file, 25.hours)

    old_work_dir = File.join(described_class::SWEEP_DIRS[1], 'abc-uuid')
    FileUtils.mkdir_p(old_work_dir)
    touch_with_age(old_work_dir, 48.hours)

    described_class.new.perform

    expect(File.exist?(old_file)).to be false
    expect(File.exist?(old_work_dir)).to be false
  end

  it 'no toca archivos recientes (job en curso)' do
    recent_file = File.join(described_class::SWEEP_DIRS[0], 'recent_export.zip')
    touch_with_age(recent_file, 1.hour)

    described_class.new.perform

    expect(File.exist?(recent_file)).to be true
  end

  it 'no revienta si alguna de las carpetas vigiladas no existe' do
    FileUtils.rm_rf(described_class::SWEEP_DIRS[2])

    expect { described_class.new.perform }.not_to raise_error
  end

  it 'si falla al borrar una entrada puntual, sigue con las demas en vez de reventar todo el job' do
    old_file = File.join(described_class::SWEEP_DIRS[0], 'old_export.zip')
    touch_with_age(old_file, 25.hours)
    allow(FileUtils).to receive(:rm_rf).and_call_original
    allow(FileUtils).to receive(:rm_rf).with(Pathname.new(old_file)).and_raise(Errno::EACCES, 'denied')

    other_old_file = File.join(described_class::SWEEP_DIRS[1], 'old.sps')
    touch_with_age(other_old_file, 25.hours)

    expect { described_class.new.perform }.not_to raise_error
    expect(File.exist?(other_old_file)).to be false
  end
end
