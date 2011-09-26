module Foil
  module Adapters

    class LocalAdapter
      
      def initialize(config)
        config = config.with_indifferent_access.symbolize_keys
        config.assert_valid_keys(:root, :autocreate_root)
        @root = Path.new(config[:root])
        @autocreate_root = config[:autocreate_root]
      end

      def get(path, context)
        root = Path.new(context.expand_variables(@root.to_s))
        if @autocreate_root
          FileUtils.mkdir_p(root.to_s)
        end
        path = Path.new(path)
        actual_path = root.join(path)
        if actual_path.has_prefix?(root)
          return LocalNode.new(root, path)
        end
      end

      attr_reader :root

      class LocalNode
        
        def initialize(root, path)
          @root = root
          @path = path
          @local_path = @root.join(@path)
        end

        def children
          result = []
          if directory?
            begin
              dir = Dir.new(@local_path.to_s)
            rescue Errno::EACCES
              # Ignore
            else
              begin
                dir.each do |file_name|
                  if accept_file?(file_name)
                    result << LocalNode.new(@root, @path.join(file_name))
                  end
                end
              ensure
                dir.close
              end
            end
          end
          result
        end

        def exists?
          File.exist?(@local_path.to_s)
        end

        def file?
          File.file?(@local_path.to_s)
        end

        def directory?
          File.directory?(@local_path.to_s)
        end

        def size
          stat.size
        end

        def created_at
          stat.ctime
        end

        def modified_at
          stat.mtime
        end

        def content_type
          type = @content_type
          type ||= Rack::Mime.mime_type(@local_path.to_s.gsub(/^.*(\.\w+)/, '\1'))
          type ||= 'application/octet-stream'
        end
        attr_writer :content_type

        def rename!(new_path)
          new_local = @local_path.parent.join(new_path)
          if new_local != @local_path
            raise ArgumentError unless new_local.has_prefix?(@root)
            File.rename(@local_path.to_s, new_local.to_s)
            @local_path = new_local
            @path = new_path
          end
        end

        def to_file(mode = 'r')
          if mode =~ /[wa]/
            FileUtils.mkdir_p(@local_path.parent.to_s)
          end
          @stat = nil
          File.open(@local_path.to_s, mode)
        end

        def delete!
          if exists?
            if directory?
              Dir.rmdir(@local_path.to_s)
            else
              File.unlink(@local_path.to_s)
            end
          end
        end

        def create_directory!
          unless directory?
            Dir.mkdir(@local_path.to_s)
          end
        end

        def save!
          # Nothing to do here
        end

        attr_reader :path

        private

          def stat
            File.stat(@local_path.to_s)
          end

          def accept_file?(file_name)
            return false if file_name =~ /^(\.|\.\.)$/
            stat = File.stat(file_name) rescue nil
            return stat.nil? || (stat.file? || stat.directory?)
          end

      end

    end

  end
end