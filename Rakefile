# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :rbs do
  desc "Install RBS collection"
  task :collection do
    sh "bundle exec rbs collection install --frozen"
  end
end

desc "Run Steep type checker"
task steep: "rbs:collection" do
  sh "bundle exec steep check"
end

task default: %i[spec rubocop steep]
