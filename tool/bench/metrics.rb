# frozen_string_literal: true

module TypeProf
  module Bench
    # Parses the output of `typeprof --show-stats --show-errors`.
    #
    # Only raw counts are extracted. Derived values such as coverage ratios are
    # left to the consumer, so that stored data can be reinterpreted later if the
    # way we compute them changes.
    module Metrics
      STATS_HEADER = "# TypeProf Evaluation Statistics"

      # Slot categories and their labels in the statistics block.
      # Keep in sync with `slot_categories` in lib/typeprof/core/service.rb.
      SLOT_LABELS = {
        param: "Parameter slots",
        ret: "Return slots",
        blk_param: "Block parameter slots",
        blk_ret: "Block return slots",
        const: "Constants",
        ivar: "Instance variables",
        cvar: "Class variables",
        gvar: "Global variables",
      }.freeze

      # `--show-errors` emits one line per diagnostic, e.g.
      #   # (239,27)-(239,30):undefined method: nil#[]
      DIAGNOSTIC_RE = /^# \(\d+,\d+\)-\(\d+,\d+\):/

      class ParseError < StandardError; end

      class << self
        # Returns a Hash of raw counts. Raises ParseError if the statistics
        # block is missing, which means the run did not complete.
        def parse(text)
          idx = text.rindex(STATS_HEADER)
          raise ParseError, "statistics block not found" unless idx

          block = text[idx..]

          {
            methods: parse_methods(block),
            slots: parse_slots(block),
            overall: parse_overall(block),
            diagnostics: text.each_line.count { |line| DIAGNOSTIC_RE.match?(line) },
          }
        end

        private

        def parse_methods(block)
          {
            total: capture_int(block, /^# Total methods:\s*(\d+)/),
            fully_typed: capture_int(block, /^#\s+Fully typed:\s*(\d+)/),
            partially_typed: capture_int(block, /^#\s+Partially typed:\s*(\d+)/),
            fully_untyped: capture_int(block, /^#\s+Fully untyped:\s*(\d+)/),
          }
        end

        def parse_slots(block)
          SLOT_LABELS.to_h do |category, label|
            re = /^# #{Regexp.escape(label)}: \d+\n#\s+Typed:\s+(\d+).*\n#\s+Untyped:\s+(\d+)/
            m = block.match(re) or raise ParseError, "no stats for #{label.inspect}"
            [category, { typed: m[1].to_i, untyped: m[2].to_i }]
          end
        end

        def parse_overall(block)
          m = block.match(/^# Overall:\s*(\d+)\/(\d+)/) or raise ParseError, "no overall stats"
          { typed: m[1].to_i, total: m[2].to_i }
        end

        def capture_int(block, re)
          m = block.match(re) or raise ParseError, "no match for #{re.inspect}"
          m[1].to_i
        end
      end
    end
  end
end
