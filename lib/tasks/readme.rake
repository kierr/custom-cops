# frozen_string_literal: true

require 'yaml'

# Regenerates the Departments table and Cops by Department tables in
# README.md from config/default.yml, so cop additions, removals, or
# description changes cannot leave the README stale. Run via the lefthook
# pre-commit hook, `bundle exec rake readme`, or checked in CI with
# `bundle exec rake readme:check`.
module ReadmeGenerator
  ROOT = File.expand_path('../..', __dir__)
  CONFIG_PATH = File.join(ROOT, 'config/default.yml')
  README_PATH = File.join(ROOT, 'README.md')

  DEPARTMENTS_START = '<!-- departments:start -->'
  DEPARTMENTS_END = '<!-- departments:end -->'
  COPS_START = '<!-- cops:start -->'
  COPS_END = '<!-- cops:end -->'

  FOCUS = {
    'Karafka' => 'Consumer and producer safety',
    'Lint' => 'Code-quality and correctness',
    'Logging' => 'Structured logging conventions',
    'MigrationSafety' => 'Safe Postgres migrations',
    'Performance' => 'Performance anti-patterns',
    'Rails' => 'Rails conventions and safety',
    'Secrets' => 'Secret/credential handling',
    'Security' => 'Security anti-patterns',
    'Service' => 'Service object conventions',
    'Sorbet' => 'Type-system consistency',
    'Style' => 'Code style and readability',
    'Test' => 'Test structure and conventions',
    'Time' => 'Time handling',
    'Zeitwerk' => 'Autoloading consistency'
  }.freeze

  MIGRATION_NOTE = 'A `SafeMigrationGenerator` is also included for ' \
                   'generating migration files that comply with these cops.'

  module_function

  def cop_entries(config)
    config.filter_map do |key, value|
      next unless key.include?('/') && value.is_a?(Hash) && value['Description']

      [key.split('/', 2).first, [key, value['Description'].to_s]]
    end
  end

  # Returns { department => [[full_name, description]] }, departments sorted
  # by cop count descending then name, cops sorted by name.
  def grouped_cops
    grouped = Hash.new { |hash, key| hash[key] = [] }
    cop_entries(YAML.load_file(CONFIG_PATH)).each do |department, entry|
      grouped[department] << entry
    end
    grouped.each_value(&:sort!)
    grouped.sort_by { |department, cops| [-cops.size, department] }.to_h
  end

  def anchor(department)
    "##{department.downcase}"
  end

  def focus_for(department)
    FOCUS.fetch(department) do
      raise "Add a focus blurb for #{department} to FOCUS in lib/tasks/readme.rake"
    end
  end

  def departments_section(grouped)
    lines = ['| Department | Cops | Focus |', '|---|---|---|']
    grouped.each do |department, cops|
      lines << "| [#{department}](#{anchor(department)}) | #{cops.size} | #{focus_for(department)} |"
    end
    lines.join("\n")
  end

  def cops_table(cops)
    rows = cops.map { |name, description| "| #{name} | #{description.gsub('|', '\\|')} |" }
    (['| Cop | Description |', '|---|---|---|'] + rows).join("\n")
  end

  def cops_section(grouped)
    grouped.map do |department, cops|
      body = cops_table(cops)
      if department == 'Lint'
        body = "<details><summary>#{cops.size} cops (click to expand)</summary>\n\n#{body}\n\n</details>"
      end
      section = "### #{department}\n\n#{body}"
      section += "\n\n#{MIGRATION_NOTE}" if department == 'MigrationSafety'
      section
    end.join("\n\n")
  end

  def replace_between(text, start_marker, end_marker, replacement)
    pattern = /(#{Regexp.escape(start_marker)}\n).*?(\n#{Regexp.escape(end_marker)})/m
    raise "Marker pair #{start_marker} / #{end_marker} not found in README.md" unless text.match?(pattern)

    text.sub(pattern, "\\1#{replacement}\\2")
  end

  def generate
    grouped = grouped_cops
    text = File.read(README_PATH)
    text = replace_between(text, DEPARTMENTS_START, DEPARTMENTS_END, departments_section(grouped))
    text = replace_between(text, COPS_START, COPS_END, cops_section(grouped))
    total = grouped.sum { |_, cops| cops.size }
    text.sub(/A RuboCop extension with \d+ cops/, "A RuboCop extension with #{total} cops")
  end

  def write
    File.write(README_PATH, generate)
  end
end

namespace :readme do
  desc 'Regenerate README cop tables from config/default.yml'
  task :generate do
    ReadmeGenerator.write
    puts 'README.md regenerated.'
  end

  desc 'Fail if README cop tables are stale (used in CI)'
  task :check do
    current = File.read(ReadmeGenerator::README_PATH)
    if current != ReadmeGenerator.generate
      abort 'README.md is stale — run `bundle exec rake readme:generate` and commit the result.'
    end
    puts 'README.md is up to date.'
  end
end

desc 'Regenerate README cop tables from config/default.yml'
task readme: 'readme:generate'
