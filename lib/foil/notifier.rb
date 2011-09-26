module Foil

  class Notifier
    
    def initialize(url)
      @url = url
      @mutex = Mutex.new
      @queue = []
      start
    end

    def notify(action, path, secondary_path = nil)
      if @running
        @mutex.synchronize do
          item = [Time.now, action.to_s, path.to_s]
          item << secondary_path.to_s if secondary_path
          @queue.push(item)
        end
      end
    end

    def start
      if @url
        @running = true
        @thread = Thread.start { check_queue_loop }
      end
    end

    def stop
      if @running
        @running = false
        @thread.try(:join)
      end
    end

    private

      def check_queue_loop
        while @running
          begin
            items = @mutex.synchronize {
              items = @queue
              @queue = [] if items.any?
              items
            }
            if items.any?
              post(items)
            end
            sleep(5)
          rescue Exception => e
            logger.error "Unhandled exception in notification queue processing: #{e}"
            sleep(1)
          end
        end
      end

      def post(items)
        retries_left = 5
        begin
          logger.info("Notifying #{@url} with changes: #{items.inspect}")
          response = Faraday.post @url, Yajl.dump({'changes' => items}),
            'Content-Type' => 'application/json'
          if response.status != 200
            logger.warn("Notification URL #{@url} returned #{response.status} instead of 200, ignoring")
          end
        rescue Exception => e
          retries_left -= 1
          if retries_left > 0
            logger.error("Error posting notification to #{@url} (will retry): #{e}")
            sleep(1)
            retry
          else
            logger.error("Could not post notification to #{@url}: #{e}")
          end
        end
      end

      def logger
        Application.get.logger
      end

  end

end