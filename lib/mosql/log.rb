module MoSQL
  module Logging
    # We use a Hash to store limiters by name so you can have
    # different limits for different types of logs.
    @limiters = {}
    @limiters_mutex = Mutex.new

    # Track collections that have been logged in the current hour
    @hourly_collections = Set.new
    @current_hour = Time.now.hour
    @hourly_collections_mutex = Mutex.new

    def self.limiters_mutex
      @limiters_mutex
    end

    def self.limiters
      @limiters
    end

    def self.hourly_collections_mutex
      @hourly_collections_mutex
    end

    def self.hourly_collections
      @hourly_collections
    end

    def self.current_hour
      @current_hour
    end

    def self.current_hour=(hour)
      @current_hour = hour
    end

    def self.reset_hourly_collections_if_needed
      @hourly_collections_mutex.synchronize do
        if Time.now.hour != @current_hour
          @current_hour = Time.now.hour
          @hourly_collections.clear
        end
      end
    end

    class HourlyLimiter
      attr_reader :count
      def initialize(max_per_hour: 60)
        @max_per_hour = max_per_hour
        @current_hour = Time.now.hour
        @count = 0
        @mutex = Mutex.new
      end

      def allow?
        @mutex.synchronize do
            # Reset if the hour has changed
            if Time.now.hour != @current_hour
              @current_hour = Time.now.hour
              @count = 0
            end

            @count += 1
            @count <= @max_per_hour
          end
      end
    end

    def log
      @@logger ||= Logger.new($stderr, progname: "Stripe::MoSQL")
    end

    # New helper method for sampled/limited logging
    def log_sampled(key, max_per_hour: 60)
      limiter = MoSQL::Logging.limiters_mutex.synchronize do
        MoSQL::Logging.limiters[key] ||= HourlyLimiter.new(max_per_hour: max_per_hour)
      end

      if limiter.allow?
        # Track this collection for hourly statistics
        collection_stats = nil
        if key.to_s.start_with?('op_stream_')
          collection_name = key.to_s.sub('op_stream_', '')
          MoSQL::Logging.reset_hourly_collections_if_needed
          MoSQL::Logging.hourly_collections_mutex.synchronize do
            MoSQL::Logging.hourly_collections.add(collection_name)
            collection_stats = {
              collections_logged: MoSQL::Logging.hourly_collections.size,
              total_collections: MoSQL::Logging.hourly_collections.to_a
            }
          end
        end

        yield(log, limiter.count, collection_stats)
      end
    end

    # Helper to get current hourly collection statistics
    def get_hourly_collection_stats
      MoSQL::Logging.reset_hourly_collections_if_needed
      MoSQL::Logging.hourly_collections_mutex.synchronize do
        {
          collections_logged: MoSQL::Logging.hourly_collections.size,
          total_collections: MoSQL::Logging.hourly_collections.to_a
        }
      end
    end
  end
end
