module Foil

  class Repository

    def initialize(name, config)
      config = config.with_indifferent_access.symbolize_keys
      config.assert_valid_keys(:authentication_url, :notification_url, :mounts, :domain, :public_read)
      @name = name
      @public_read = config[:public_read]
      @domain = config[:domain].is_a?(Regexp) ? config[:domain] : Regexp.new(config[:domain])
      @authentication_url = config[:authentication_url]
      @notification_url = config[:notification_url]
      @notifier = Notifier.new(@notification_url)
      @mounts = {}
      config[:mounts].each do |path, mount_config|
        path = Path.new(path)
        @mounts[path] = Mount.new(mount_config)
      end
      @mounts.freeze
      @auth_cache = {}
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

    def notify(action, path, secondary_path = nil)
      @notifier.notify(action, path, secondary_path)
    end

    def match_domain?(host, context)
      if host =~ @domain
        match = $~
        match.names.each do |name|
          context.variables[name] = match[name]
        end
        true
      end
    end

    def with_authentication(context, &block)
      auth_url = @authentication_url
      if auth_url and request_requires_auth?(context.request)
        authorization = context.request.env['HTTP_AUTHORIZATION'] || ''
        if authorization =~ /\bbasic ([^\s]+)/i
          identification, password = Base64.decode64($1).split(':')[0, 2]
          if identification and password
            cache_key = [identification, password, context.request.env['REMOTE_ADDR']]
            status, expiry = @auth_cache[cache_key]
            if expiry and expiry <= Time.now.to_f
              @auth_cache.delete(cache_key)
              status = nil
            end
            unless status
              auth_url = auth_url.dup
              auth_url.gsub!("{{identification}}", identification)
              auth_url.gsub!("{{password}}", password)
              status = Faraday.post(auth_url).status
              @auth_cache[cache_key] = [status, Time.now.to_f + AUTH_CACHE_EXPIRY]
            end
            case status
              when 200
                yield
                return true
              when 401, 403
                logger.info("Authentication failed with #{response.status}")
              else
                logger.error("Authentication unexpectedly replied with #{response.status}, counting as failure")
            end
          end
        else
          logger.info("Missing authorization header")
        end
        context.response['WWW-Authenticate'] = 'Basic realm="WebDAV"'
        context.response.status = 401
        false
      else
        yield
        true
      end
    end

    attr_reader :name
    attr_reader :domain
    attr_reader :authentication_url
    attr_reader :notification_url
    attr_reader :mounts

    private

      AUTH_CACHE_EXPIRY = 10 * 60

      PUBLIC_HTTP_METHODS = %w(GET HEAD).freeze

      def request_requires_auth?(request)
        !(@public_read && PUBLIC_HTTP_METHODS.include?(request.env['REQUEST_METHOD'].to_s.upcase))
      end

      def logger
        Application.get.logger
      end

  end

end