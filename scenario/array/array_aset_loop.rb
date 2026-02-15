## update
def foo(ary)
  while ary[0]
    ary[0] = "str"
  end
  nil
end

foo([1])

## assert
class Object
  def foo: ([Integer]) -> nil
end
