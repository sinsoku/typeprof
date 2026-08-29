# frozen_string_literal: true

module TypeProf
  module Benchmark
    # Parses the output of `typeprof --show-stats --show-errors`.
    module Metrics
      STATS_HEADER = "# TypeProf Evaluation Statistics"

      # `--show-errors` emits one line per diagnostic, e.g.
      #   # (239,27)-(239,30):undefined method: nil#[]
      DIAGNOSTIC_RE = /^# \(\d+,\d+\)-\(\d+,\d+\):/

      class ParseError < StandardError; end

      def self.parse(text)
        idx = text.rindex(STATS_HEADER)
        raise ParseError, "statistics block not found" unless idx

        m = text[idx..].match(/^# Overall:\s*(\d+)\/(\d+)/) or
          raise ParseError, "no overall stats"

        {
          overall: { typed: m[1].to_i, total: m[2].to_i },
          diagnostics: text.each_line.count { |line| DIAGNOSTIC_RE.match?(line) },
        }
      end
    end
  end
end
