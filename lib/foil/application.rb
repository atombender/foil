module Foil

  VERSION = '0.1'.freeze

  class Application
    
    def initialize(options = {})
      @@instance = self
      @configuration = Configuration.new
    end

    def configure!(config)
      @configuration.load(config)
      log_file = File.open(@configuration.log_path, File::WRONLY | File::APPEND)
      log_file.sync = true
      @logger = Logger.new(log_file)
      class << @logger
        def format_message(severity, timestamp, progname, msg)
          "[#{timestamp}] #{msg}\n"
        end
      end
    end
    
    class << self
      def get
        @@instance
      end
    end
    
    attr_reader :configuration
    attr_reader :logger
    
  end
  
end
