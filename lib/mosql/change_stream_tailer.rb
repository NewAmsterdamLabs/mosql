module MoSQL
  class ChangeStreamTailer

    include MoSQL::Logging

    attr_reader :last_saved, :last_read

    # How often to save position to database
    DEFAULT_SAVE_FREQUENCY = 60.0
    DEFAULT_WATCH_INTERVAL = 10.0
    DEFAULT_BATCH_SIZE = 1000
    MAX_RETRY = 5

    def initialize(mongo_db, table, opts)
      @mongo_db = mongo_db
      @table = table
      # This number seems high
      @conn_opts = {:op_timeout => 86400}
      @last_saved = {}
      @batch_size = opts[:batch_size] || DEFAULT_BATCH_SIZE
      @last_read = {}
      @save_frequency = opts[:save_frequency] || DEFAULT_SAVE_FREQUENCY
      @stop = false
      @streaming = false
      @cursor = nil
      @retry_count = 0
      @watch_interval = opts[:watch_interval] || DEFAULT_WATCH_INTERVAL
      @service = opts[:service] || "mosql"
    end

    def watch(resume_after)
      resume_after ||= read_position
      batch_size ||= 1000
      log.info("Opening change stream on #{@mongo_db.database.name} with token #{resume_after.inspect}")
      begin
        opts = {
          :batch_size => batch_size,
          :full_document => nil, # TODO switch to updateLookup or whenAvailable
          :comment => "#{@service} changestream",
          #:max_await_time_ms: 1000,
        }
        if resume_after.is_a?(String) && resume_after.length > 0
          log.info("Attempting to resume stream using token: #{resume_after}")
          opts = opts.merge({:resume_after => BSON::Document.new(:_data => resume_after) })
        elsif resume_after.is_a?(Integer)
          ts = Time.at(resume_after).utc
          log.info("Attempting to resume stream using timestamp: #{ts}")
          opts = opts.merge( { :start_at_operation_time => BSON::Timestamp.new(ts.to_i, 1) } )
        else
          log.info("No resume token, starting change stream from now")
        end
        @stream = @mongo_db.watch([], opts)
        @cursor = @stream.to_enum
        log.info("Streaming using enum: #{@cursor} - #{@stream.class}")
        @cursor
      rescue Exception => e
        # changestream to enum throws exception several times.
        log.warn("Failed starting change stream. Retrying after failure: #{e.message}")
        retry if (@retry_count += 1) < MAX_RETRY
      end
    end

    def stream(&blk)
      @streaming = true
      state = Mongoriver::TailerStreamState.new(@batch_size)
      log.debug("Streaming with batch size #{@batch_size} - ")
      while !@stop && !state.break? && !@cursor.nil? && cursor_has_more?
        log.debug("Trying to get next record")
        record = @cursor.try_next
        resume_token = @stream.resume_token
        state.increment
        unless record.nil?
          blk.call(record, resume_token)
        end
        @last_read = state_for(record, resume_token)
        log.debug("Saving state #{@last_read}")
        maybe_save_state
      end
      @streaming = false
      cursor_has_more?
    end

    def cursor_has_more?
      begin
        @cursor.peek
        true
      rescue StopIteration
        false
      end
    end

    def self.create_table(db, table_name)
      unless db.table_exists?(table_name)
        db.create_table(table_name) do
          column :service, 'TEXT'
          column :timestamp, 'INTEGER'
          column :resume_token, 'BYTEA'
          primary_key [:service]
        end
      end

      db[table_name.to_sym]
    end

    public
    def stop
      @stop = true
      #@stream.close unless @stream.closed? # cannot call this in a trap context
    end

    def get_resume_token
      return nil unless @stream
      @stream.resume_token
    end

    # state to save to the database for this record
    def state_for(record, resume_token)
      {
        'time' => cluster_time(record),
        'position' => resume_token['_data']
      }
    end

    # Return a position for a record object
    #
    # @return [BSON::Binary]
    def resume_token(record)
      return nil unless record
      record['_id']['_data']
    end

    # Return a time for a record object
    # @return Time
    def cluster_time(record)
      return nil unless record
      Time.at(record["clusterTime"].seconds)
    end

    def read_state
      row = @table.where(:service => @service).first
      return nil unless row
      result = {}
      result['time'] = Time.at(row.fetch(:timestamp))
      result['position'] = from_blob(row[:position])
      result
    end

    def write_state(state)
      data = {
        :service => @service,
        :timestamp => state['time'].to_i,
        :position => to_blob(state['position'])
      }

      unless @did_insert
        begin
          @table.insert(data)
        rescue Sequel::DatabaseError => e
          raise unless MoSQL::SQLAdapter.duplicate_key_error?(e)
        end
        @did_insert = true
      end

      @table.where(:service => @service).update(data)
    end

    def save_state(state=nil)
      if state.nil?
        state = last_read
      end
      return unless state['position']
      write_state(state)
      @last_saved = state
      log.info("Saved state: #{last_saved}")
    end

    def maybe_save_state
      return unless last_read['time']
      if last_saved['time'].nil? || last_read['time'] - last_saved['time'] > @save_frequency
        save_state
      end
    end

    private
    def to_blob(position)
      Sequel::SQL::Blob.new(position)
    end

    def from_blob(blob)
      blob
    end

  end
end
