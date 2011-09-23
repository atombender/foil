begin
  require 's3'
rescue LoadError
end

if defined?(S3)
  module S3
    class Bucket
      def list_bucket(options = {})
        response = bucket_request(:get, :params => options)
        objects_attributes = parse_list_bucket_result(response.body)

        # If there are more than 1000 objects S3 truncates listing
        # and we need to request another listing for the remaining objects.
        unless options[:max_keys]
          while parse_is_truncated(response.body)
            marker = objects_attributes.last[:key]
            response = bucket_request(:get, :params => options.merge(:marker => marker))
            objects_attributes += parse_list_bucket_result(response.body)
          end
        end

        objects_attributes.map { |object_attributes| Object.send(:new, self, object_attributes) }
      end
    end
  end
end

module Foil
  module Adapters

    class S3Adapter
      
      def initialize(config)
        config = config.with_indifferent_access.symbolize_keys
        config.assert_valid_keys(:root, :access_key_id, :secret_access_key, :bucket)
        @root = Path.new(config[:root] || '/')
        @service ||= ::S3::Service.new(
          :access_key_id => config[:access_key_id],
          :secret_access_key => config[:secret_access_key])
        @bucket = @service.buckets.find(config[:bucket])
      end

      def get(path, context)
        path = Path.new(path)
        actual_path = @root.join(path)
        if actual_path.has_prefix?(@root)
          objects = bucket.objects.find_all(:max_keys => 2, :prefix => actual_path.to_s[1..-1])
          if objects.any? { |o| 
            other_path = @root.join(o.key)
            other_path.length > actual_path.length && other_path.has_prefix?(actual_path)
          }
            return S3FolderNode.new(self, path, objects[0])
          else
            return S3Node.new(self, path, objects[0])
          end
        end
      end

      attr_reader :root
      attr_reader :service
      attr_reader :bucket

      class S3Node

        def initialize(adapter, path, object = nil)
          @adapter = adapter
          @path = path
          @s3_path = @adapter.root.join(@path)
          @object = object
        end

        def children
          []
        end

        def exists?
          s3_object.exists?
        end

        def file?
          exists?
        end

        def directory?
          false
        end

        def size
          s3_object.size.try(:to_i)
        end

        def created_at
          Time.now
        end

        def modified_at
          Time.now
        end

        def etag
          s3_object.etag
        end

        def content_type
          type = @content_type
          type ||= s3_object.content_type
          type ||= Rack::Mime.mime_type(@s3_path.to_s.gsub(/^.*(\.\w+)/, '\1'))
          type ||= 'application/octet-stream'
        end
        attr_writer :content_type

        def rename!(new_path)
        end

        def to_file(mode = 'r')
          case mode
            when 'r'
              io = StringIO.new
              io << s3_object.content
              io.seek(0)
              io
            when 'w'
              if exists?
                object = s3_object
              else
                object = @object = bucket.objects.build(@s3_path.to_s[1..-1])
              end
              S3OutputStream.new(object)
          end
        end

        def delete!
          s3_object.destroy
        end

        def create_directory!
          dummy_key = @s3_path.join('.folder').to_s[1..-1]
          begin
            dummy_object = bucket.objects.find(dummy_key)
          rescue S3::Error::NoSuchKey
            dummy_object = bucket.objects.build(dummy_key)
            dummy_object.content = ''
            dummy_object.save
          end
        end

        def save!
          s3_object.save
        end

        attr_reader :path

        protected

          def s3_object
            @object ||= bucket.object(@s3_path.to_s[1..-1])
          end

          def bucket
            @adapter.bucket
          end

      end

      class S3FolderNode < S3Node

        def children
          result = []
          objects = []
          marker = nil
          prefix = @s3_path.to_s[1..-1]
          loop do
            # FIXME: The s3 gem does not support delimiter-based traversal, so this
            #   is going to blow up with large buckets
            objs = bucket.objects.find_all(
              :marker => marker, 
              :max_keys => 1000, 
              :prefix => prefix)
            break if objs.empty?
            objects.concat(objs)
            marker = objs.last.key
          end
          added = Set.new
          objects.each do |object|
            full_path = @s3_path.join(object.key).without_prefix(@s3_path)
            if full_path.first
              path = @s3_path.join(full_path.first)
              if added.add?(path.to_s)
                if objects.any? { |o| 
                  other_path = @s3_path.join(o.key)
                  other_path.length > path.length && other_path.has_prefix?(path)
                }
                  result << S3FolderNode.new(@adapter, path, object)
                else
                  result << S3Node.new(@adapter, path, object)
                end
              end
            end
          end
          result
        end

        def exists?
          s3_object.size
        end

        def file?
          false
        end

        def directory?
          exists?
        end

        def size
          0
        end

        def created_at
          Time.now
        end

        def modified_at
          Time.now
        end

        def etag
          nil
        end

        def content_type
          @content_type
        end

        def rename!(new_path)
        end

        def to_file(mode = 'r')
          raise ArgumentError
        end

      end

      private

        class S3OutputStream < StringIO

          def initialize(object)
            super('')
            @object = object
          end

          def close
            flush
            super
          end

          def flush
            super
            value = string.dup
            @object.content = value
            @object.save
            @object.retrieve
          end

        end

    end

  end
end