## update
module M
  def self.included(base)
    base.class_eval do
      def from_block = 1
    end
  end
end

class C
  include M
end

def m = C.new.from_block

## assert
module M
  def self.included: (untyped) -> untyped
end
class C
  include M
  def from_block: -> Integer
end
class Object
  def m: -> Integer
end
