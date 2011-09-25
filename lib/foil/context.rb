module Foil

  class Context

    def initialize(request, response)
      @request, @response = request, response
      @variables = {}
    end

    def expand_variables(string)
      s = nil
      variables.each do |name, value|
        s ||= string.dup
        s.gsub!("{{#{name}}}", value.to_s)
      end
      s ||= string
    end

    attr_reader :request
    attr_reader :response
    attr_reader :variables

  end

end