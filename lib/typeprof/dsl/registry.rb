module TypeProf
  module Dsl
    class Registry
      @entries = {}
      @include_entries = {}

      class << self
        def register(plugin_class, cpath:, mid:, singleton:)
          key = [cpath, mid, singleton]
          @entries[key] ||= []
          @entries[key] << plugin_class unless @entries[key].include?(plugin_class)
        end

        def register_include(plugin_class, cpath:)
          @include_entries[cpath] ||= []
          @include_entries[cpath] << plugin_class unless @include_entries[cpath].include?(plugin_class)
        end

        # Fire on_include plugins registered for `included_cpath`. Plugins inject
        # relations via scope.owner (e.g. extend_module); returns the injected
        # relations, or nil if no plugin matched. `origin` is the include def that
        # triggered the firing and makes the injected relations unique to it.
        def fire_include(genv, owner_mod, included_cpath, origin)
          plugin_classes = @include_entries[included_cpath]
          return unless plugin_classes
          scope = IncludeScope.new(genv, owner_mod, origin)
          plugin_classes.each {|plugin_class| plugin_class.new.install(scope) }
          scope.owner.injected
        end

        def apply(genv)
          @entries.each do |(cpath, mid, singleton), plugin_classes|
            me = genv.resolve_method(cpath, singleton, mid)
            if me.builtin
              warn "[TypeProf DSL] Cannot register plugin for #{cpath.join('::')}#{singleton ? '.' : '#'}#{mid} (already has builtin)"
              next
            end
            plugins = plugin_classes.map(&:new)
            me.builtin = build_handler(genv, plugins)
          end
        end

        private

        def build_handler(genv, plugins)
          ->(changes, node, ty, a_args, _ret) do
            scope = Scope.new(genv, changes, node, ty, a_args)
            plugins.each { |plugin| plugin.install(scope) }
            # Return false so MethodCallBox also runs normal RBS resolution;
            # plugins only add side effects, not the receiver's return type.
            false
          end
        end
      end
    end
  end
end
