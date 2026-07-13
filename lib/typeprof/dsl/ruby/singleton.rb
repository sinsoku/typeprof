module TypeProf
  module Dsl
    module Ruby
      # `include Singleton` makes Ruby run `klass.extend SingletonClassMethods` in
      # the `included` hook, which is what provides `Klass.instance`. Model the same:
      # extend the including class with SingletonClassMethods so those class methods
      # resolve from RBS. No method is synthesized here.
      class Singleton < TypeProf::Dsl::Base
        on_include "Singleton"

        def install(scope)
          scope.owner.extend_module("Singleton::SingletonClassMethods")
        end
      end
    end
  end
end
