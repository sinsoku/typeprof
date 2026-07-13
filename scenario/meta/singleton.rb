## update: test.rbs
module Singleton
  module SingletonClassMethods
    def instance: () -> instance
  end
end

## update: test.rb
class Config
  include Singleton
end

def m = Config.instance

## assert: test.rb
class Config
  include Singleton
end
class Object
  def m: -> Config
end

## update: test.rb
class Config
end

def m = Config.instance

## assert: test.rb
class Config
end
class Object
  def m: -> untyped
end

## update: test.rb
class Config
  include Singleton
end

def m = Config.instance

## update: test1.rb
class Config
  include Singleton
end

## assert: test.rb
class Config
  include Singleton
end
class Object
  def m: -> Config
end

## update: test1.rb
class Config
end

## assert: test.rb
class Config
  include Singleton
end
class Object
  def m: -> Config
end
