module Foil

  class Path

    include Enumerable

    def initialize(value = nil, base = nil)
      case value
        when nil
          @components = []
        when Array
          @components = value.map { |component| component.to_s }
        when Path
          @components = value.components
          base ||= value.base
        else
          if value == '/'
            @components = ['']
          else
            @components = self.class.normalize(value.to_s).split('/')
          end
      end
      @components.freeze
      @base = base
    end

    def root?
      first == ''
    end

    def descend
      if components.length > 1
        Path.new(components[1..-1], self)
      end
    end

    def first
      @components[0]
    end

    def ==(other)
      if Path === other
        to_s == other.to_s
      else
        super
      end
    end

    def <=>(other)
      if Path === other
        components <=> other.components
      else
        super
      end
    end

    def to_s
      @components.join('/')
    end

    def length
      @components.length
    end

    def components
      @components.dup
    end

    def each(&block)
      components.each(&block)
    end

    def join(other)
      Path.new(components | Path.new(other).components, @base)
    end

    def prefix?(other)
      components[0, other.length] == other.components[0, other.length]
    end

    def parent
      components = self.components
      components.empty? ? nil : Path.new(components[0, components.length - 1])
    end

    def absolute
      if @base
        @base.join(self)
      else
        self
      end
    end

    def inspect
      "<Path #{components.inspect} (base=#{@base.inspect})>"
    end

    attr_reader :base

    class << self
      def normalize(path)
        path = path.dup
        path.gsub!(/\/+$/, '')
        path.gsub!(/\/\/+/, '/')
        path
      end
    end

  end

end