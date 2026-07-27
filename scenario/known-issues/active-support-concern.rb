## update: concern.rb
module ActiveSupport
  module Concern
    class MultipleIncludedBlocks < StandardError
      def initialize
        super "Cannot define multiple 'included' blocks for a Concern"
      end
    end

    def self.extended(base)
      base.instance_variable_set(:@_dependencies, [])
    end

    def append_features(base)
      if base.instance_variable_defined?(:@_dependencies)
        base.instance_variable_get(:@_dependencies) << self
        false
      else
        return false if base < self
        @_dependencies.each { |dep| base.include(dep) }
        super
        base.extend const_get(:ClassMethods) if const_defined?(:ClassMethods)
        base.class_eval(&@_included_block) if instance_variable_defined?(:@_included_block)
      end
    end

    def included(base = nil, &block)
      if base.nil?
        if instance_variable_defined?(:@_included_block)
          if @_included_block.source_location != block.source_location
            raise MultipleIncludedBlocks
          end
        else
          @_included_block = block
        end
      else
        super
      end
    end

    def class_methods(&class_methods_module_definition)
      mod = const_defined?(:ClassMethods, false) ?
        const_get(:ClassMethods) :
        const_set(:ClassMethods, Module.new)

      mod.module_eval(&class_methods_module_definition)
    end
  end
end

## update: test.rb
module Greetable
  extend ActiveSupport::Concern

  module ClassMethods
    def cm = "cm"
  end

  def im = 1
end

class C
  include Greetable
end

def m1 = C.cm
def m2 = C.new.im

## assert: test.rb
module Greetable
  module ClassMethods
    def cm: -> String
  end
  def im: -> Integer
end
class C
  include Greetable
end
class Object
  def m1: -> String
  def m2: -> Integer
end

## update: test.rb
module Greetable
  extend ActiveSupport::Concern

  class_methods do
    def cm = "cm"
  end
end

class C
  include Greetable
end

def m1 = C.cm

## assert: test.rb
module Greetable
  module ClassMethods
    def cm: -> String
  end
end
class C
  include Greetable
end
class Object
  def m1: -> String
end

## update: test.rb
module Inner
  extend ActiveSupport::Concern

  module ClassMethods
    def inner_cm = "inner"
  end
end

module Outer
  extend ActiveSupport::Concern
  include Inner

  module ClassMethods
    def outer_cm = "outer"
  end
end

class C
  include Outer
end

def m1 = C.outer_cm
def m2 = C.inner_cm

## assert: test.rb
module Inner
  module ClassMethods
    def inner_cm: -> String
  end
end
module Outer
  module ClassMethods
    def outer_cm: -> String
  end
end
class C
  include Outer
end
class Object
  def m1: -> String
  def m2: -> String
end
