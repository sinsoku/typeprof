## update
class Base
  module Helpers
    def helper = 1
  end

  def self.inherited(sub)
    super
    sub.extend(Helpers)
  end
end

class Child < Base
end

def m = Child.helper

## assert
class Base
  module Helpers
    def helper: -> Integer
  end
  def self.inherited: (untyped) -> untyped
end
class Child < Base
end
class Object
  def m: -> Integer
end
