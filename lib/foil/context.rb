module Foil

  class Context

    def initialize(request, response)
      @request, @response = request, response
    end

    attr_reader :request
    attr_reader :response

  end

end