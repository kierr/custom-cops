# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Flags use of `$ERROR_INFO` or `$!` inside rescue blocks that do not
      # bind the exception to a local variable. The global variables are fragile
      # (cleared by subsequent exceptions, require `require 'english'` for
      # `$ERROR_INFO`), untypeable by Sorbet, and obscure intent. Bind the
      # exception explicitly with `rescue StandardError => e` instead.
      #
      # Also flags the globals even when a binding exists — mixing `$ERROR_INFO`
      # with a bound variable is still a lint smell. Autocorrect replaces the
      # global with the existing binding name.
      #
      # @example
      #
      #   # bad — unbound rescue reads global
      #   rescue StandardError
      #     LOGGER.debug('timeout', error: $ERROR_INFO.message)
      #
      #   # bad — reads $!
      #   rescue StandardError
      #     report($!)
      #
      #   # good — bound to local variable
      #   rescue StandardError => e
      #     LOGGER.debug('timeout', error: e.message)
      #
      class RescueUsesErrorInfoGlobal < Base
        extend AutoCorrector

        MSG = 'Bind the exception with `=> e` instead of using `$ERROR_INFO` or `$!` in rescue blocks.'

        # Global variables that alias the current exception inside rescue.
        ERROR_GLOBALS = %i[$ERROR_INFO $!].freeze

        # Preferred variable name for the exception binding when autocorrecting.
        DEFAULT_VAR = :e

        def on_gvar(node)
          return unless ERROR_GLOBALS.include?(node.name)

          resbody = node.each_ancestor(:resbody).first
          return unless resbody

          add_offense(node) do |corrector|
            autocorrect(corrector, node, resbody)
          end
        end

        private

        def autocorrect(corrector, gvar_node, resbody)
          binding_node = resbody.children[1]
          var_name =
            if binding_node
              binding_node.children.first
            else
              DEFAULT_VAR
            end

          # Add `=> var_name` to the rescue clause if no binding exists.
          add_rescue_binding(corrector, resbody, var_name) unless binding_node

          # Replace the global variable reference with the local variable.
          corrector.replace(gvar_node, var_name.to_s)
        end

        def add_rescue_binding(corrector, resbody, var_name)
          exception_list = resbody.children[0]
          if exception_list
            # `rescue StandardError` — insert after the exception list.
            # exception_list is an array node wrapping the exception types.
            # The last child's source range is the insertion point.
            last_type = if exception_list.array_type?
                          exception_list.children.last
                        else
                          exception_list
                        end
            return unless last_type

            corrector.insert_after(last_type, " => #{var_name}")
          else
            # Bare `rescue` — insert after the keyword itself.
            corrector.insert_after(resbody.loc.keyword, " => #{var_name}")
          end
        end
      end
    end
  end
end
