module Foil
  
  class Webapp < Sinatra::Base

    configure do |config|
      config.set :sessions, false
      config.set :run, false
      config.set :logging, true
      config.set :show_exceptions, false
    end

    before do
      headers['Server'] = "foil/#{VERSION}"
     
      @repository = Application.get.configuration.repositories.select { |repo| 
        repo.match_domain?(request.host) }.first
      halt 404 unless @repository
      @context = Context.new(request, response)
    end
    
    get '*' do |path|
      node = @repository.get(path, @context) or halt 404
      if node.exists?
        headers['Content-Length'] = node.size.to_s
        headers['Content-Type'] = node.content_type
        headers['Last-Modified'] = node.modified_at.rfc2822
        headers['ETag'] = nil
        if_modified_since = request.env['HTTP_IF_MODIFIED_SINCE']
        if_modified_since &&= Time.parse(if_modified_since) rescue nil
        if if_modified_since and node.modified_at and node.modified_at <= if_modified_since
          304
        else
          node.to_file
        end
      else
        404
      end
    end

    head '*' do |path|
      node = @repository.get(path, @context) or halt 404
      if node.exists?
        headers['Content-Length'] = node.size.to_s
        headers['Content-Type'] = node.content_type
        headers['Last-Modified'] = node.modified_at.rfc2822
        headers['ETag'] = nil
        200
      else
        404
      end
    end

    post '*' do |path|
      halt 400 unless request.body
      node = @repository.get(path, @context) or halt 404
      halt 404 unless node.exists?
      halt 405 if node.directory?
      file = node.to_file('w')
      begin
        IO.copy_stream(request.body, file)
      ensure
        file.close
      end
      node.content_type = request.media_type
      node.content_type ||= request.env['CONTENT_TYPE']
      node.content_type ||= Rack::Mime.mime_type(path.gsub(/^.*(\.\w+)/, '\1'))
      node.save!
      201
    end

    put '*' do |path|
      halt 400 unless request.body
      node = @repository.get(path, @context) or halt 404
      halt 405 if node.directory?
      file = node.to_file('w')
      begin
        IO.copy_stream(request.body, file)
      ensure
        file.close
      end
      node.content_type = request.media_type
      node.content_type ||= request.env['CONTENT_TYPE']
      node.content_type ||= Rack::Mime.mime_type(path.gsub(/^.*(\.\w+)/, '\1'))
      node.save!
      201
    end

    delete '*' do |path|
      node = @repository.get(path, @context) or halt 404
      if node.directory?
        traverse(node, :infinity) do |node|
          node.delete!
        end
      else
        node.delete!
      end
      204
    end

    route 'MKCOL', '*' do |path|
      node = @repository.get(path, @context) or halt 404
      halt 405 if node.file? or node.directory?
      halt 415 unless request.body.read.blank?
      node.create_directory!
      200
    end

    route 'MOVE', '*' do |path|
      node = @repository.get(path, @context) or halt 404

      new_path = URI.parse(request.env['HTTP_DESTINATION']).path
      halt 400 if new_path.blank?
      new_path = Path.new(path).parent.join(new_path)

      target = @repository.get(new_path, nil)
      halt 405 if target and target.directory? != node.directory?

      if node.file?
        target.delete! if target and target.file?
        node.rename!(new_path)
        204
      else
        node.rename!(new_path)
        headers['Location'] = new_path.to_s  # TODO: URL
        201
      end
    end

    options '*' do |path|
      headers["Allow"] = %w(OPTIONS GET HEAD POST PUT MKCOL PROPFIND MOVE LOCK UNLOCK).join(", ")
      headers["DAV"] = %w(1 2).join(", ")
      200
    end

    route 'PROPFIND', '*' do |path|
      node = @repository.get(path, @context) or halt 404
      halt 404 unless node.exists?

      depth = case request.env['HTTP_DEPTH']
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

      [207, xml.target!]
    end

    # TODO: Implement unlocking
    route 'UNLOCK', '*' do |path|
      204
    end

    # TODO: Actually lock something. Something, anything!
    route 'LOCK', '*' do |path|
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
      headers["Lock-Token"] = SecureRandom.hex(16)

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
      xml.target!
    end

    def handle_unlock
      current_sandbox.assert_permitted(:manage)
      file = @root.get(@path)
      if file
        # TODO: Actually unlock something
        render_webdav(:nothing => true, :status => 204)
      else
        not_found
      end
    end

    not_found do
      'Not found'
    end

    error do
      exception = env['sinatra.error']
      [500, exception.name]
    end

    error Errno::EACCES do 403 end
    error Errno::EPERM do 403 end

    private

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
