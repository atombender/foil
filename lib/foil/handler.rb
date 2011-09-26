module Foil

  class Halt < Exception
    def initialize(status)
      super(status.to_s)
      @status = status
    end
    attr_reader :status
  end

  class Handler

    # Class-level Rack call interface.
    def self.call(env)
      new.call(env)
    end

    # Rack call interface.
    def call(env)
      @request = Rack::Request.new(env)
      @response = Rack::Response.new
      begin
        begin
          @response['Server'] = "foil/#{VERSION}"

          # We don't support partial puts yet
          halt 507 if @request.env['HTTP_CONTENT_RANGE']

          @response['MS-Author-Via'] = 'Dav'  # MS-Office compatibility

          @context = Context.new(@request, @response)
          @context.variables['host'] = @request.host
          @context.variables['remote_addr'] = @request.env['REMOTE_ADDR']
          Application.get.configuration.repositories.each do |repo|
            if repo.match_domain?(@request.host, @context)
              @repository = repo
              break
            end
          end
          halt 404 unless @repository

          method_name = "handle_#{env['REQUEST_METHOD'].downcase.underscore}"
          if respond_to?(method_name)
            send(method_name, Rack::Utils.unescape(env['REQUEST_URI']))
          else
            @response.status = 404
          end
        rescue Halt => e
          @response.status = e.status
        end
      rescue Exception => e
        logger.error("Exception #{e.class}: #{e.message}")
        @response.status = 500
      end

      logger.info("#{Time.now.xmlschema} #{env['REQUEST_METHOD']} #{env['REQUEST_URI']} #{response.status}")

      @response.finish
      @response.to_a
    end

    protected

      attr_reader :request
      attr_reader :response

      def halt(status)
        raise Halt, status
      end

      def handle_options(path)
        @response["Allow"] = %w(OPTIONS GET HEAD POST PUT MKCOL PROPFIND MOVE LOCK UNLOCK).join(", ")
        @response["DAV"] = %w(1 2).join(", ")
      end

      def handle_put(path)
        node = @repository.get(path, @context)
        halt 404 unless node
        halt 405 if node.directory?

        overwriting = node.exists?
        file = node.to_file('w')
        begin
          request.body.each do |part|
            file.write part
          end
        ensure
          file.close
        end
        node.content_type = request.media_type
        node.content_type ||= request.env['CONTENT_TYPE']
        node.content_type ||= Rack::Mime.mime_type(path.gsub(/^.*(\.\w+)/, '\1'))
        node.save!

        @response.status = 201
        @repository.notify(overwriting ? :modify : :create, node.path)
      end

      def handle_propfind(path)
        node = @repository.get(path, @context) or halt 404
        halt 404 unless node.exists?

        depth = case @request.env['HTTP_DEPTH']
          when '0' then 0
          when '1' then 1
          when 'infinity' then :infinity
        end
        depth ||= :infinity
        nodes = traverse(node, depth)

        xml = Builder::XmlMarkup.new
        xml.instruct!
        xml.multistatus("xmlns" => "DAV:") do
          nodes.each do |node|
            xml.response do
              xml.href node.path.absolute.to_s
              xml.propstat do
                xml.prop do          
                  xml.creationdate node.created_at ? node.created_at.xmlschema : Time.now.xmlschema
                  xml.getlastmodified node.modified_at.rfc2822 if node.modified_at
                  xml.getcontentlength node.size if node.size
                  xml.getcontenttype node.content_type if node.content_type
                  xml.getetag node.created_at.to_i.to_s if node.created_at
                  xml.resourcetype do
                    if node.directory?
                      xml.collection
                    end
                  end
                  xml.lockdiscovery
                end
                xml.status "HTTP/1.1 200 OK"
              end
            end
          end
        end

        @response.status = 207
        @response.body << xml.target!
      end

      def handle_delete(path)
        node = @repository.get(path, @context) or halt 404
        halt 404 unless node.exists?
        if node.directory?
          traverse(node, :infinity) do |node|
            node.delete!
            @repository.notify(:delete, node.path)
          end
        else
          node.delete!
          @repository.notify(:delete, node.path)
        end
        @response.status = 204
      end

      def handle_get(path)
        node = @repository.get(path, @context) or halt 404
        halt 404 unless node.exists?
        response['Content-Length'] = node.size.to_s
        response['Content-Type'] = node.content_type
        response['Last-Modified'] = node.modified_at.rfc2822
        response['ETag'] = nil
        if_modified_since = request.env['HTTP_IF_MODIFIED_SINCE']
        if_modified_since &&= Time.parse(if_modified_since) rescue nil
        if if_modified_since and node.modified_at and node.modified_at <= if_modified_since
          response.status = 304
        else
          response.body = node.to_file
          response.status = 200
        end
      end

      def handle_head(path)
        node = @repository.get(path, @context) or halt 404
        halt 404 unless node.exists?
        response['Content-Length'] = node.size.to_s
        response['Content-Type'] = node.content_type
        response['Last-Modified'] = node.modified_at.rfc2822
        response['ETag'] = nil
        @response.status = 200
      end

      # TODO: Implement locking
      def handle_lock(path)
        node = @repository.get(path, @context) or halt 404
        halt 404 unless node.exists?

        input = Nokogiri::XML(request.body.read) rescue nil
        if input
          ns = {"D" => "DAV:"}
          input.xpath("//D:lockscope/*", ns).each do |element|
            @scope = element.name.to_sym
          end
          input.xpath("//D:locktype/*", ns).each do |element|
            @type = element.name.to_sym
          end
          input.xpath("//D:owner/D:href/text()", ns).each do |node|
            @owner = node.to_s
          end
        end
        @scope ||= :exclusive
        @type ||= :write
        @owner ||= @path.to_s
        response["Lock-Token"] = SecureRandom.hex(16)

        xml = Builder::XmlMarkup.new
        xml.instruct!
        xml.D(:prop, {"xmlns:D" => "DAV:"}) do
          xml.D :lockdiscovery do
            xml.D :activelock do
              xml.D :lockscope do
                xml.D @scope
              end
              xml.D :locktype do
                xml.D @type
              end
              xml.D :depth, "infinity"
              xml.D :locktoken do
                xml.D :href, @token
              end        
              xml.D :owner do
                xml.D :href, @owner
              end
              xml.D :lockroot do
                xml.D :href, @path
              end
            end
          end
        end
        response.body << xml.target!
      end

      # TODO: Implement locking
      def handle_unlock(path)
        response.status = 204
      end

      def handle_mkcol(path)
        node = @repository.get(path, @context) or halt 404
        halt 405 if node.file?
        halt 415 unless request.body.read.blank?
        node.create_directory!
        @repository.notify(:make_collection, node.path)
      end

      def handle_move(path)
        node = @repository.get(path, @context) or halt 404
        halt 404 unless node.exists?

        destination_url = request.env['HTTP_DESTINATION']
        halt 400 if destination_url.blank?
        new_path = URI.decode(URI.parse(destination_url).path)
        new_path = Path.new(new_path)

        puts "move: #{path.to_s}"
        puts "  to: #{new_path.to_s}"

        target = @repository.get(new_path, @context)
        halt 405 if target and target.directory? != node.directory?

        target_parent = @repository.get(new_path.parent, @context)
        halt 404 if node.file? and not target_parent.exists?

        old_path = node.path
        if node.file?
          target.delete! if target and target.file?
          node.rename!(new_path)
          response.status = 204
        else
          node.rename!(new_path)
          headers['Location'] = new_path.to_s  # TODO: URL
          response.status = 201
        end

        @repository.notify(:rename, old_path, node.path)
      end

    private

      def logger
        @logger ||= Application.get.logger
      end

      def traverse(node, depth, results = [], &block)
        if node
          if node.directory? and depth != 0
            if depth == :infinity
              child_depth = depth
            else
              child_depth = 0
            end
            node.children.each do |child|
              traverse(child, child_depth, results, &block)
            end
          end
          yield node if block
          results << node
        end
        results
      end

  end

end