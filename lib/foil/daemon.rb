require "logger"
require "fileutils"
require 'optparse'

module Foil

  class DaemonError < Exception; end
  class DaemonAlreadyRunning < DaemonError; end
  class DaemonNotRunning < DaemonError; end
  class DaemonTerminationFailed < DaemonError; end
  class DaemonNotConfigured < DaemonError; end
  class DaemonStartFailed < DaemonError; end 

  # Daemon controller class that encapsulates a running daemon and a remote interface to it.
  class Daemon
  
    # Initializes the daemon controller.
    def initialize(options = {})
      @root = options[:root] || Dir.pwd
      @pid_file = options[:pid_file]
      @log_file = options[:log_file]
      @on_spawn = nil
    end

    # Specifies a block to execute to run the actual daemon. Each call overrides the previous one.  
    def on_spawn(&block)
      @on_spawn = block
    end

    # Specifies a block to execute to termiantion. Each call overrides the previous one.  
    def on_terminate(&block)
      @on_terminate = block
    end
  
    # Control the daemon through command-line arguments.
    def control(args, title = nil)
      $stderr.sync = true
      title ||= File.basename($0)
      command = args.shift
      control_with_command(command, args, title)
    end
  
    # Control the daemon through a specific command.
    def control_with_command(command, args, title = nil)
      case command
        when "start"
          $stderr << "Starting #{title}: "
          handle_errors do
            start
            $stderr << "started\n"
          end
        when "stop"
          $stderr << "Stopping #{title}: "
          options = {}
          handle_errors do
            stop({:signal => "TERM"}.merge(options))
            $stderr << "stopped\n"
          end
        when "restart"
          $stderr << "Restarting #{title}: "
          handle_errors do
            restart
            $stderr << "restarted\n"
          end
        when "status"
          if running?
            $stderr << "#{title} is running\n"
          else
            $stderr << "#{title} is not running\n"
          end
      else
        if command
          $stderr << "#{File.basename($0)}: Invalid command #{command}\n"
        else
          puts "Usage: #{File.basename($0)} [start | stop | restart | status]"
        end
      end
    end
  
    # Starts daemon.
    def start
      raise DaemonNotConfigured, "Daemon not configured" unless @on_spawn
      FileUtils.mkdir_p(File.dirname(@pid_file)) rescue nil
      pid = self.pid
      if pid
        if pid_running?(pid)
          raise DaemonAlreadyRunning, "Process is already running with pid #{pid}"
        end
      end
      File.delete(@pid_file) rescue nil
      child_pid = Process.fork
      if child_pid
        sleep(1)      
        unless running?
          pid = self.pid
          if pid == child_pid
            raise DaemonStartFailed, "Daemon started, but failed prematurely"
          else
            raise DaemonStartFailed, "Daemon failed to start for some unknown reason"
          end
        end      
        return
      end
      @logger = nil
      logger.info("Starting")
      begin
        Process.setsid
        0.upto(255) do |n|
          File.for_fd(n, "r").close rescue nil
        end
        File.umask(27)
        Dir.chdir(@root)
        $stdin = File.open("/dev/null", File::RDWR)
        $stdout = File.open("/dev/null", File::RDWR)
        $stderr = File.open("/dev/null", File::RDWR)
        @pid = Process.pid
        File.open(@pid_file, "w") do |file|
          file << Process.pid
        end
        Signal.trap("HUP") do
          logger.debug("Ignoring SIGHUP")
        end
        Signal.trap("TERM") do
          if $$ == @pid
            logger.info("Terminating (#{$$})")
            @on_terminate.call if @on_terminate
            File.delete(@pid_file) rescue nil
          else
            # Was sent to a child
          end
          exit(0)
        end
        @on_spawn.call
        exit(0)
      rescue SystemExit
        # Do nothing
      rescue Exception => e
        message = "#{e.message}\n"
        message << e.backtrace.map { |line| "\tfrom #{line}\n" }.join
        logger.error(message)
        exit(1)
      ensure
        logger.close
      end
    end
  
    # Stops daemon.
    def stop(options = {})
      stopped = false
      found = false
      pid = self.pid
      if pid
        # Send TERM to process
        begin
          Process.kill(options[:signal] || "TERM", pid)
        rescue Errno::ESRCH
          stopped = true
        rescue Exception => e
          raise DaemonTerminationFailed, "Could not stop process #{pid}: #{e.message}"
        end
        unless stopped
          # Process was signaled, now wait for it to die
          found = true
          30.times do
            begin
              if not pid_running?(pid)
                stopped = true
                break
              end
              sleep(1)
            rescue Exception => e
              raise DaemonTerminationFailed, "Could not stop process #{pid}: #{e.message}"
            end
          end
          if found and not stopped
            # Process still running after wait, force kill and wait
            begin
              Process.kill("KILL", pid)
            rescue Errno::ESRCH
              stopped = true
            end
            30.times do
              begin
                if not pid_running?(pid)
                  stopped = true
                  break
                end
                sleep(1)
              rescue Exception => e
                raise DaemonTerminationFailed, "Could not stop process #{pid}: #{e.message}"
              end
            end
            if not stopped
              raise DaemonTerminationFailed, "Timeout attempting to stop process #{pid}"
            end
          end
        end
      end
      unless found
        raise DaemonNotRunning, "Process is not running"
      end
    end
  
    # Restarts daemon.
    def restart
      if running?
        begin
          stop
        rescue DaemonNotRunning
          # Ignore
        end
      end
      start
    end
  
    # Is the daemon running?
    def running?
      !pid.nil?
    end
  
    # Returns the daemon pid.
    def pid
      pid = nil
      maybe_pid = File.read(@pid_file) rescue nil
      if maybe_pid =~ /([0-9]+)/
        maybe_pid = $1.to_i
        begin
          Process.kill(0, maybe_pid)
        rescue Errno::ESRCH
        else
          pid = maybe_pid
        end
      end
      pid
    end

    # Signals the daemon.  
    def signal(signal)
      pid = self.pid
      if pid
        Process.kill(signal, pid)
      else
        raise DaemonNotRunning, "Process is not running"
      end
    end
  
    # Returns logger.
    def logger
      return @logger ||= (Logger === @log_file ? @log_file : Logger.new(@log_file || "/dev/null"))
    end
  
    attr_reader :root
    attr_reader :pid_file
  
    private

      def pid_running?(pid)
        begin
          Process.kill(0, pid)
        rescue Errno::ESRCH
          return false
        end
        return true
      end
        
      def handle_errors(&block)
        begin
          yield
        rescue DaemonError => e
          $stderr << "#{e.message}\n"
          if e.is_a?(DaemonAlreadyRunning) or e.is_a?(DaemonNotRunning)
            exit_code = 0
          else
            exit_code = 1
          end
          exit(exit_code)
        end
      end

  end

end
