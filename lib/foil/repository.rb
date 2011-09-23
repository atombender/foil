module Foil

  class Repository

    def initialize(name, config)
      config = config.with_indifferent_access.symbolize_keys
      config.assert_valid_keys(:authentication_url, :notification_url, :mounts, :domain)
      @name = name
      @domain = config[:domain].is_a?(Regexp) ? config[:domain] : Regexp.new(config[:domain])
      @authentication_url = config[:authentication_url]
      @notification_url = config[:notification_url]
      @mounts = {}
      config[:mounts].each do |path, mount_config|
        path = Path.new(path)
        @mounts[path] = Mount.new(mount_config)
      end
      @mounts.freeze
    end

    def get(path, context)
      path = Path.new(path)
      if path.root?
        @mounts.each do |mount_path, mount|
          if path == mount_path or path.has_prefix?(mount_path)
            return mount.get(path.descend, context)
          end
        end
      end
      nil
    end

    def match_domain?(host)
      return host =~ @domain
    end

    attr_reader :name
    attr_reader :domain
    attr_reader :authentication_url
    attr_reader :notification_url
    attr_reader :mounts

  end

end