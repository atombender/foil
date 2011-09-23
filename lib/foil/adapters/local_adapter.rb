module Foil
  module Adapters

    class LocalAdapter
      
      def initialize(config)
        config = config.with_indifferent_access.symbolize_keys
        config.assert_valid_keys(:root)
        @root = Path.new(config[:root])
      end

      def get(path, context)
        path = Path.new(path)
        actual_path = @root.join(path)
        if actual_path.prefix?(@root)
          return LocalNode.new(self, path)
        end
      end

      attr_reader :root

      class LocalNode
        def initialize(adapter, path)
          @adapter = adapter
          @path = path
          @local_path = @adapter.root.join(@path)
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
                    result << LocalNode.new(@adapter, @path.join(file_name))
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
            raise ArgumentError unless new_local.prefix?(@adapter.root)
            File.rename(@local_path.to_s, new_local.to_s)
            @local_path = new_local
          end
        end

        def to_file(mode = 'r')
          if mode =~ /w/
            FileUtils.mkdir_p(@local_path.parent.to_s)
          end
          @stat = nil
          File.open(@local_path.to_s, mode)
        end

        def delete!
          if directory?
            Dir.rmdir(@local_path.to_s)
          else
            File.unlink(@local_path.to_s)
          end
        end

        def create_directory!
          Dir.mkdir(@local_path.to_s)
        end

        def save!
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