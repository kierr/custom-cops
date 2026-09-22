# typed: strict
# frozen_string_literal: true

require_relative '../../custom_cops/comment_window'

module RuboCop
  module Cop
    module Sorbet
      # Flags gem types (Ferrum, Nokogiri, Nokolexbor, Typhoeus, Redis) in
      # sig return-type annotations within app/ domain code. Gem objects must not
      # pass through domain boundaries — wrap them in adapters or use app-owned types.
      #
      # Two justification mechanisms:
      # 1. Per-sig: RATIONALE comment within 3 lines above the sig's returns call.
      # 2. Per-enclosing-module/class: RATIONALE comment within 3 lines above the
      #    nearest enclosing module/class definition that contains the gem type
      #    keyword "NoGemTypeInDomainReturn" or "gem type" in the RATIONALE text.
      class NoGemTypeInDomainReturn < Base
        include ::RuboCop::Cop::CustomCops::CommentWindow

        MSG = 'Avoid gem types (%<gem>s) in domain return types. Use app-owned types or add # RATIONALE: <reason>.'

        GEM_NAMESPACES = %w[Ferrum Nokogiri Nokolexbor Typhoeus Redis].freeze

        EXCLUDED_PATHS = %w[/adapters/ app/lib/ lib/rubocop/ test/ spec/].freeze

        def on_new_investigation
          super
          @file_path = processed_source.file_path.to_s
        end

        def on_send(node)
          return unless node.method_name == :returns
          return unless app_domain_file?
          return if skip_file?
          return if justified?(node)

          found = Set.new
          each_gem_const(node) { |g| found << g }
          return if found.empty?

          add_offense(node.loc.selector, message: format(MSG, gem: found.sort.join(', ')))
        end

        private

        def app_domain_file?
          @file_path.include?('app/')
        end

        def skip_file?
          EXCLUDED_PATHS.any? { |pattern| @file_path.include?(pattern) }
        end

        # Walk descendant const nodes looking for gem types. Yields the gem
        # namespace name for each match. Matches both namespaced gem types
        # (Typhoeus::Response — matched on the namespace) and bare top-level
        # gem consts (Redis, ::Redis — matched on the const itself). A const
        # like Foo::Redis is NOT matched: its namespace Foo is not a gem, and
        # matching on the inner name would false-positive on unrelated code.
        def each_gem_const(node)
          node.each_descendant(:const) do |const_node|
            namespace = const_node.children.first

            if namespace.nil? || namespace.type == :cbase
              own_name = const_node.children.last.to_s
              yield own_name if GEM_NAMESPACES.include?(own_name)
            elsif namespace.type == :const
              gem_name = namespace.children.last.to_s
              yield gem_name if GEM_NAMESPACES.include?(gem_name)
            end
          end
        end

        def justified?(node)
          sig_justified?(node) || module_justified?(node)
        end

        # Per-sig: RATIONALE comment within 3 lines above the returns call.
        def sig_justified?(node)
          preceding_comments(node).any? do |comment|
            comment.text.include?('RATIONALE:')
          end
        end

        # Per-enclosing-module/class: RATIONALE comment within 3 lines above the
        # nearest enclosing module/class/casgn definition.
        def module_justified?(node)
          enclosure = find_enclosing_module(node)
          return false unless enclosure

          preceding_comments(enclosure).any? do |comment|
            text = comment.text
            text.include?('RATIONALE:') && text.match?(/NoGemTypeInDomainReturn|gem.type/i)
          end
        end

        # Walk up the AST from the returns node to find the nearest enclosing
        # module, class, or sclass (class << self) definition.
        def find_enclosing_module(node)
          current = node.parent
          while current
            case current.type
            when :module, :class, :sclass
              return current
            end
            current = current.parent
          end

          nil
        end
      end
    end
  end
end
