module MoSQL
  class BaseStreamer
    include MoSQL::Logging

    attr_reader :options

    def initialize(options, mongo, sql, schema)
      @options = options
      @mongo = mongo
      @sql = sql
      @schema = schema
      @done    = false
    end

    def stop
      @done = true
    end

    def unsafe_handle_exceptions(ns, obj)
      begin
        yield
      rescue Sequel::DatabaseError => e
        wrapped = e.wrapped_exception
        if wrapped.result && options[:unsafe]
          log.warn("Ignoring row (#{obj.inspect}): #{e}")
        else
          log.error("Error processing #{obj.inspect} for #{ns}.")
          raise e
        end
      rescue TypeError, Exception => e
        log.warn("Ignoring row (#{obj.inspect}): #{e.class} #{e}")
      end
    end

    def bulk_upsert(table, ns, items)
      begin
        @schema.copy_data(table.db, ns, items)
      rescue Sequel::DatabaseError => e
        log.debug("Bulk insert error (#{e}), attempting individual upserts...")
        cols = @schema.all_columns(@schema.find_ns(ns))
        items.each do |it|
          h = {}
          cols.zip(it).each { |k,v| h[k] = v }
          unsafe_handle_exceptions(ns, h) do
            @sql.upsert!(table, @schema.primary_sql_key_for_ns(ns), h)
          end
        end
      end
    end

    def with_retries(tries=10)
      tries.times do |try|
        begin
          yield
          # TODO find replacement for Mongo::ConnectionError, Mongo::ConnectionFailure,
        rescue Mongo::Error::OperationFailure => e
          # Duplicate key error
          raise if e.kind_of?(Mongo::Error::OperationFailure) && [11000, 11001].include?(e.error_code)
          # Cursor timeout
          raise if e.kind_of?(Mongo::Error::OperationFailure) && e.message =~ /^Query response returned CURSOR_NOT_FOUND/
          delay = 0.5 * (1.5 ** try)
          log.warn("Mongo exception: #{e}, sleeping #{delay}s...")
          sleep(delay)
        end
      end
    end

    def track_time
      start = Time.now
      yield
      Time.now - start
    end

    def collection_for_ns(ns)
      dbname, collection = ns.split(".", 2)
      @mongo.use(dbname)[collection]
    end

    def sync_object(ns, selector)
      obj = collection_for_ns(ns).find(selector).limit(1).first
      if obj
        log.debug("updating document: #{ns} #{selector.inspect} -> #{obj.inspect}")
        unsafe_handle_exceptions(ns, obj) do
          @sql.upsert_ns(ns, obj)
        end
      else
        log.debug("document not found: #{ns} #{selector.inspect} -> deleting")
        @sql.delete_ns(ns, selector)
      end
    end

    def handle_op(op)
      raise NotImplementedError, "This is an abstract method. Subclasses must implement it."
    end

  end
end