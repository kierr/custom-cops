# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Flags chained iteration/query methods on `ActiveRecord::Result` from
      # `connection.execute`, `insert_all`, and `upsert_all` without calling
      # `.to_a` first. In Rails 8.1, `ActiveRecord::Result` no longer exposes
      # `.map`, `.size`, `.pluck`, `.count`, `.empty?`, `.length`, `.first`,
      # `.last` directly — they must be preceded by `.to_a`.
      #
      # The walker traverses the receiver chain from the dangerous method inward
      # toward the result-producing method. If `.to_a` appears anywhere in the
      # chain between them, the call is safe.
      #
      # @example
      #   # bad
      #   connection.execute(sql).map { |r| r['id'] }
      #   connection.execute(sql).size
      #
      #   # good
      #   connection.execute(sql).to_a.map { |r| r['id'] }
      #   connection.execute(sql).to_a.size
      class ResultToArrayFirst < Base
        MSG = 'Call `.to_a` on `ActiveRecord::Result` before chaining iteration/query methods. Rails 8.1 removed `.map`/`.size`/etc from Result.'

        DANGEROUS_METHODS = %i[map size pluck count empty? length first last].freeze
        RESULT_METHODS = %i[execute insert_all upsert_all].freeze

        def on_send(node)
          return unless DANGEROUS_METHODS.include?(node.method_name)

          found_to_a = false
          found_result = false
          receiver = node.receiver

          iterations_recv = 0
          while receiver&.send_type?
            iterations_recv += 1
            break if iterations_recv > 1_000

            found_to_a = true if receiver.method_name == :to_a
            found_result = true if RESULT_METHODS.include?(receiver.method_name)
            break if found_result

            receiver = receiver.receiver
          end

          return unless found_result
          return if found_to_a

          add_offense(node.loc.selector, message: MSG)
        end
      end
    end
  end
end
