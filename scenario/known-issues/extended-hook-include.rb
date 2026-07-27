## update
module M
  def self.extended(base)
    base.include(InstanceMethods)
  end

  module InstanceMethods
    def run = 1
  end
end

class C
  extend M
end

def m = C.new.run

## assert
module M
  def self.extended: (untyped) -> untyped
  module InstanceMethods
    def run: -> Integer
  end
end
class C
  extend M
end
class Object
  def m: -> Integer
end
