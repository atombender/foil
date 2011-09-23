module Foil

  VERSION = '0.1'.freeze

  class Application
    
    def initialize(options = {})
      @@instance = self
      @configuration = Configuration.new
    end

    def configure!(config)
      @configuration.load(config)
    end

    def run!
      Foil::Webapp.run!(
        :host => @configuration.host,
        :port => @configuration.port,
        :handler => @configuration.handler)
    end
    
    class << self
      def get
        @@instance
      end
    end
    
    attr_reader :configuration
    
  end
  
end
