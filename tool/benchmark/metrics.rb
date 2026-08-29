module TypeProf
  module Benchmark
    # Parses the output of `typeprof --show-stats --show-errors`.
    module Metrics
      # `--show-errors` emits one line per diagnostic, e.g.
      #   # (239,27)-(239,30):undefined method: nil#[]
      DIAGNOSTIC_RE = /^# \(\d+,\d+\)-\(\d+,\d+\):/

      def self.parse(text)
        m = text.match(/^# Overall:\s*(\d+)\/(\d+)/) or raise "no statistics in the output"

        {
          overall: { typed: m[1].to_i, total: m[2].to_i },
          diagnostics: text.each_line.count {|line| DIAGNOSTIC_RE.match?(line) },
        }
      end
    end
  end
end
