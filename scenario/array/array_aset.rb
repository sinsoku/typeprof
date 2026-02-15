## update
def foo(ary)
  ary[0] = "str"
  bar(ary)
  nil
end

def bar(ary)
  ary[1] = 1.0
  nil
end

ary = [1, 2, 3]
foo(ary)

## assert
class Object
  def foo: ([Integer, Integer, Integer]) -> nil
  def bar: ([Integer | String, Integer, Integer]) -> nil
end
