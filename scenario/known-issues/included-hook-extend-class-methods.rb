## update
module M
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def hello = "hi"
  end
end

class C
  include M
end

def m = C.hello

## assert
module M
  def self.included: (untyped) -> untyped
  module ClassMethods
    def hello: -> String
  end
end
class C
  include M
end
class Object
  def m: -> String
end
