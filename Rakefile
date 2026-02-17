require 'rake/testtask'

task :default => [:test]
task :build

Rake::TestTask.new do |t|
  t.libs = ["lib"]
  t.verbose = true
  t.test_files = FileList['test/**/*.rb']
    .exclude('test/functional/change_stream_streamer.rb')
    .reject { |file| file.end_with?('_lib.rb') }
end

Rake::TestTask.new(:test_unit) do |t|
  t.libs = ["lib"]
  t.verbose = true
  t.test_files = FileList['test/unit/**/*.rb'].reject do |file|
    file.end_with?('_lib.rb')
  end
end
