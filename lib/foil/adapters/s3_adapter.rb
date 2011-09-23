require 's3'

module Foil

  class S3Adapter
    
    def initialize(config)
      config = config.with_indifferent_access.symbolize_keys
    end

  end

end