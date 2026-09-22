# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.compact` on hashes containing proxy/network-routing keys where
      # nil values are meaningful. `{ proxy: nil }.compact` strips the key
      # entirely, causing the HTTP client to send requests without proxy
      # (exposing real IP). When the intent is "use nil proxy" (which errors
      # safely at the HTTP layer), compact silently changes behavior to "use no
      # proxy" (which leaks the origin IP).
      #
      # Flagged when the hash literal includes keys named after proxy-routing
      # configuration: proxy, socks, socks5, socks4, tor, vpn, tunnel. Generic
      # keys like address, host, and port are excluded because they appear in
      # many non-proxy contexts (street addresses, IMAP configs) and would
      # produce excessive false positives.
      #
      # @example
      #
      #   # bad — strips proxy: nil, sending requests without proxy
      #   { proxy: proxy_url, timeout: 30 }.compact
      #
      #   # good — no proxy-routing keys, compact is safe
      #   { name: name, email: email }.compact
      #
      #   # good — generic address/port keys are not flagged
      #   { address: host, port: 443 }.compact
      #
      class CompactStripsNilProxy < Base
        MSG = '`.compact` on a hash with proxy/network keys silently removes nil entries, ' \
              'potentially sending requests without proxy and exposing the real IP. ' \
              'Use `reject { |k, v| v.nil? && !PROXY_KEYS.include?(k) }` or build the hash explicitly.'

        # Keys whose nil-ness carries proxy-routing semantics. When these are
        # nil, the correct behavior is to fail at the HTTP layer (no proxy
        # configured = misconfiguration), not to silently fall back to direct
        # connection (no proxy = IP exposure). Generic keys (address, host,
        # port) are excluded to avoid false positives from non-network hashes.
        PROXY_KEYS = %i[proxy socks socks5 socks4 tor vpn tunnel].freeze

        # String equivalents for hash literal pair keys.
        PROXY_KEY_STRINGS = PROXY_KEYS.map(&:to_s).freeze

        def on_send(node)
          return unless node.method_name == :compact
          return unless node.receiver

          receiver = node.receiver
          return unless hash_with_proxy_keys?(receiver)

          add_offense(node)
        end

        private

        # Checks whether the receiver is a hash literal or method call whose
        # keys include at least one proxy-related key. For hash literals, we
        # inspect the pair keys directly. For method calls (e.g.,
        # `build_opts(...)`), we cannot statically determine the keys, so we
        # only flag hash literals to keep false positives low.
        def hash_with_proxy_keys?(node)
          return false unless node.hash_type?

          node.pairs.any? do |pair|
            key = pair.key
            case key.type
            when :sym
              PROXY_KEYS.include?(key.value)
            when :str
              PROXY_KEY_STRINGS.include?(key.value)
            else
              false
            end
          end
        end
      end
    end
  end
end
