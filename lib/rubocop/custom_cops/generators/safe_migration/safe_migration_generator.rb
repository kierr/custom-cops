# typed: strong
# frozen_string_literal: true

# The generator requires Rails, which may not be available when the gem is
# loaded outside a Rails application (e.g., in lint-only CI or standalone
# rubocop runs). Guard the entire definition so the gem loads cleanly
# without Rails; the generator is only meaningful inside a Rails app
# where `rails generate` is available.
if defined?(Rails::Generators)
  require 'rails/generators'

  module SafeMigration
    class SafeMigrationGenerator < Rails::Generators::NamedBase
      extend T::Sig
      source_root File.expand_path('templates', __dir__)

      class_option :type, type: :string, required: true, desc: 'Type: add_index, backfill_column, not_null'
      class_option :table, type: :string, desc: 'Target table name'
      class_option :column, type: :string, desc: 'Target column name'
      class_option :unique, type: :boolean, default: false, desc: 'Unique index (for add_index)'
      class_option :value, type: :string, desc: 'SQL literal used in backfill (for backfill_column)'

      sig { void }
      def create_migration_file
        # RATIONALE: Thor options hash — Rails generator options are heterogeneous; cast to extract :type. Would need typed generator options to reconsider.
        type = T.cast(T.cast(options, T::Hash[Symbol, T.untyped])[:type], String)
        case type
        when 'add_index'
          template 'add_index.rb.tt', migration_path
        when 'backfill_column'
          template 'backfill_column.rb.tt', migration_path
        when 'not_null'
          # Generate two-step NOT NULL flow
          template 'not_null_add.rb.tt', migration_path(suffix: '_step1_add_check')
          template 'not_null_validate.rb.tt', migration_path(suffix: '_step2_validate_and_enforce')
        else
          raise ArgumentError, "Unknown type: #{type}"
        end
      end

      private

      sig { params(suffix: T.nilable(String)).returns(String) }
      def migration_path(suffix: nil)
        timestamp = T.cast(T.cast(Time.current, ActiveSupport::TimeWithZone).utc, Time).strftime('%Y%m%d%H%M%S')
        name = suffix ? "#{file_name}#{suffix}" : file_name
        File.join('db/migrate', "#{timestamp}_#{name}.rb")
      end
    end
  end
end
