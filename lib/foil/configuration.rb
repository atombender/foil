module Foil

  class Configuration

    def initialize(config = {})
      load(config)
    end

    def load(config)
      config = config.with_indifferent_access.symbolize_keys
      config.assert_valid_keys(:repositories, :pid_path, :log_path, :host, :port, :handler)
      
      @host = config[:host]
      @port = config[:port]
      @handler = config[:handler]
      @pid_path = config[:pid_path]
      @log_path = config[:log_path]

      @repositories = []
      (config[:repositories] || {}).each do |name, repo_config|
        repo_config = repo_config.symbolize_keys
        @repositories << Repository.new(name, repo_config)
      end
      @repositories.freeze
    end

    attr_reader :repositories
    attr_reader :log_path
    attr_reader :pid_path
    attr_reader :host
    attr_reader :port
    attr_reader :handler

  end

end