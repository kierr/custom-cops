# typed: strict
# frozen_string_literal: true

module RuboCop
  module CustomCops
    # Injection target for RuboCop to load our default config
    module Inject
      def self.defaults!
        path = File.join(__dir__, '..', '..', '..', 'config', 'default.yml')
        hash = YAML.safe_load_file(path, permitted_classes: [Symbol])
        config = RuboCop::Config.new(hash, path)
        RuboCop::ConfigLoader.instance_variable_get(:@configuration_from_defaults)&.each do |key, value|
          config[key] = value unless config.key?(key)
        end
        RuboCop::ConfigLoader.instance_variable_set(:@configuration_from_defaults, config)
      end
    end
  end
end
