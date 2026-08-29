## update
class Foo
  attr_reader :a
  attr_accessor :b
end
foo = Foo.new
foo.a(k: 1)
foo.b(k: 1)

## assert
class Foo
  def a: -> untyped
  def b: -> untyped
  def b=: (untyped) -> untyped
end

## diagnostics
(6,4)-(6,5): wrong number of arguments (1 for 0)
(7,4)-(7,5): wrong number of arguments (1 for 0)
