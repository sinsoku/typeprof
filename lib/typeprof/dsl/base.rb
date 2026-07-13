module TypeProf
  module Dsl
    # Convert a Ruby constant name like "Foo::Bar" into a cpath [:Foo, :Bar].
    def self.cpath_from(name)
      name.split("::").map(&:to_sym)
    end

    class Base
      def self.on(pattern)
        cpath, mid, singleton = parse_pattern(pattern)
        Registry.register(self, cpath: cpath, mid: mid, singleton: singleton)
      end

      # Structural trigger: fire when `include <name>` appears in a class body.
      def self.on_include(name)
        Registry.register_include(self, cpath: Dsl.cpath_from(name))
      end

      def install(scope)
        raise NotImplementedError, "#{self.class}#install must be implemented"
      end

      def self.parse_pattern(pattern)
        if pattern.include?("#")
          cpath_str, mid_str = pattern.split("#", 2)
          singleton = false
        elsif pattern.include?(".")
          cpath_str, mid_str = pattern.split(".", 2)
          singleton = true
        else
          raise ArgumentError, "Invalid pattern: #{pattern.inspect} (expected 'Foo#bar' or 'Foo.bar')"
        end
        cpath = cpath_str.split("::").map(&:to_sym)
        [cpath, mid_str.to_sym, singleton]
      end
      private_class_method :parse_pattern
    end
  end
end
