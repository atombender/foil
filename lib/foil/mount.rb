module Foil

  class Mount
    
    def initialize(config)
      config = config.with_indifferent_access
      type = config[:type]
      unless type
        raise ArgumentError, "Missing mount type"
      end
      @headers = (config[:headers] || {}).dup.freeze
      @adapter = "Foil::Adapters::#{type.classify}Adapter".classify.constantize.new(config[type] || {})
    end

    def get(path, context)
      node = @adapter.get(Path.new(path), context)
      if node and context
        @headers.each do |header, value|
          context.response.headers[header] = value.try(:to_s)
        end
      end
      node
    end

    attr_reader :adapter

  end

end