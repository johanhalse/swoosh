# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# Two suites, deliberately in separate processes:
#
#   test:gem   - the gem on its own, with Rails absent from the process, which
#                is what keeps Sinatra/Hanami/plain Ruby usage honest.
#   test:rails - the same gem driven through the dummy application in test/dummy.
namespace :test do
  Rake::TestTask.new(:gem) do |t|
    t.libs << "test" << "lib"
    t.test_files = FileList["test/*_test.rb"]
    t.warning = false
  end

  Rake::TestTask.new(:rails) do |t|
    t.libs << "test" << "lib"
    t.test_files = FileList["test/rails/*_test.rb"]
    t.warning = false
  end
end

desc "Run the gem suite and the Rails suite"
task test: ["test:gem", "test:rails"]

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[test rubocop]
