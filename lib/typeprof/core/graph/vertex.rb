module TypeProf::Core
  class BasicVertex
    def initialize(types)
      @types = types
    end

    attr_reader :types

    def show
      if Fiber[:show_rec].include?(self)
        "untyped"
      else
        begin
          Fiber[:show_rec] << self
          types = []
          bot = @types.include?(Type::Bot.new)
          optional = @types.include?(Type.nil)
          bool = @types.include?(Type.true) && @types.include?(Type.false)
          types << "bool" if bool
          @types.each do |ty, _source|
            next if ty == Type.nil
            next if bool && (ty == Type.true || ty == Type.false)
            next if ty == Type::Bot.new
            types << ty.show
          end
          types = types.uniq.sort
          ret = case types.size
          when 0
            optional ? "nil" : bot ? "bot" : "untyped"
          when 1
            types.first + (optional ? "?" : "")
          else
            "(#{ types.join(" | ") })" + (optional ? "?" : "")
          end
        #ensure
          Fiber[:show_rec].delete(self)
          ret
        end
      end
    end
  end

  class Source < BasicVertex
    def initialize(*tys)
      types = {}
      tys.each do |ty|
        raise ty.inspect unless ty.is_a?(Type)
        types[ty] = true
      end
      super(types)
    end

    def on_type_added(genv, src_var, added_types)
      # TODO: need to report error?
    end

    def on_type_removed(genv, src_var, removed_types)
    end

    def new_vertex(genv, show_name, node)
      nvtx = Vertex.new(show_name, node)
      add_edge(genv, nvtx)
      nvtx
    end

    def add_edge(genv, nvtx)
      nvtx.on_type_added(genv, self, @types.keys)
    end

    def remove_edge(genv, nvtx)
      nvtx.on_type_removed(genv, self, @types.keys)
    end

    def show
      if Fiber[:show_rec].include?(self)
        "...(recursive)..."
      else
        begin
          Fiber[:show_rec] << self
          ret = @types.empty? ? "untyped" : @types.keys.map {|ty| ty.show }.sort.join(" | ")
        #ensure
          Fiber[:show_rec].delete(self)
          ret
        end
      end
    end

    def match?(genv, other)
      @types.each do |ty1, _source|
        other.types.each do |ty2, _source|
          return true if ty1.match?(genv, ty2)
        end
      end
      return false
    end

    def to_s
      "<src:#{ show }>"
    end

    alias inspect to_s
  end

  class Vertex < BasicVertex
    def initialize(show_name, origin)
      @show_name = show_name
      case origin
      when AST::Node
      when RBS::AST::Declarations::Base
      when VertexEntity
      else
        raise
      end
      @origin = origin
      @next_vtxs = Set[]
      super({})
    end

    attr_reader :show_name, :origin, :next_vtxs, :types

    def on_type_added(genv, src_var, added_types)
      new_added_types = []
      added_types.each do |ty|
        unless @types[ty]
          @types[ty] ||= Set[]
          new_added_types << ty
        end
        raise "duplicated edge" if @types[ty].include?(src_var)
        @types[ty] << src_var
      end
      unless new_added_types.empty?
        @next_vtxs.each do |nvtx|
          nvtx.on_type_added(genv, self, new_added_types)
        end
      end
    end

    def on_type_removed(genv, src_var, removed_types)
      new_removed_types = []
      removed_types.each do |ty|
        @types[ty].delete(src_var)
        if @types[ty].empty?
          @types.delete(ty)
          new_removed_types << ty
        end
      end
      unless new_removed_types.empty?
        @next_vtxs.each do |nvtx|
          nvtx.on_type_removed(genv, self, new_removed_types)
        end
      end
    end

    def new_vertex(genv, show_name, node)
      nvtx = Vertex.new(show_name, node)
      add_edge(genv, nvtx)
      nvtx
    end

    def add_edge(genv, nvtx)
      @next_vtxs << nvtx
      nvtx.on_type_added(genv, self, @types.keys) unless @types.empty?
    end

    def remove_edge(genv, nvtx)
      @next_vtxs.delete(nvtx)
      nvtx.on_type_removed(genv, self, @types.keys) unless @types.empty?
    end

    def match?(genv, other)
      @types.each do |ty1, _source|
        other.types.each do |ty2, _source|
          # XXX
          return true if ty1.base_types(genv).first.match?(genv, ty2.base_types(genv).first)
        end
      end
      return false
    end

    $new_id = 0 # TODO: Use class variable

    def to_s
      "v#{ @id ||= $new_id += 1 }"
    end

    alias inspect to_s

    def long_inspect
      "#{ to_s } (#{ @show_name } @ #{ @node.code_range })"
    end
  end
end