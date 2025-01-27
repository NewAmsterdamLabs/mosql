module MoSQL
  class ChangeStreamStreamer < MoSQL::BaseStreamer

    def initialize(opts, mongo, sql, schema)
      super(opts, mongo, sql, schema)
    end

    def handle_op(change_doc)
      log.debug("Handling op: #{change_doc.inspect}")

      # for now rebuild ns to be <db>.<collection> to avoid redoing all the mosql code
      dbname = change_doc["ns"]["db"]
      collection_name = change_doc["ns"]["coll"]
      ns = "#{dbname}.#{collection_name}"

      # don't do anything if there is no mapping for this collection
      unless @schema.find_ns(ns)
        log.debug("Skipping op for unknown ns #{ns}...")
        return
      end

      op_type = change_doc["operationType"]
      case op_type
      when "insert"
        on_insert(ns, change_doc)
      when "update"
        on_update(ns, change_doc)
      when "delete"
        on_delete(ns, change_doc)
      when "replace"
        on_replace(ns, change_doc)
      when "rename"
        on_rename(ns, change_doc)
      when "drop"
        log.debug("Dropped collection #{ns}")
      when "dropDatabase"
        log.warn("database #{dbname} has been dropped. This is not going to end well")
      when "invalidate"
        log.warn("stream is not valid anymore. database #{dbname} may have been dropped!")
      else
        log.debug("Unsupported event #{op_type}: #{change_doc.inspect}")
      end
    end

    def on_insert(ns, change_doc)
      if ns == 'system.indexes'
        log.info("Skipping index update: #{change_doc.inspect}")
      else
        doc = change_doc['fullDocument']
        unsafe_handle_exceptions(ns, doc)  do
          @sql.upsert_ns(ns, doc)
        end
      end
    end

    def on_update(ns, change_doc)
      doc_key = change_doc['documentKey']
      sync_object(ns, doc_key)
    end

    # TODO: implement this in a way that doesn't require a full resync
    def on_update_optimized(ns, change_doc)
      doc_key = change_doc['documentKey']
      doc = change_doc['updateDescription']['updatedFields']
      doc = doc.merge!(doc_key)
      # add as nil fields that were removed so that they are set to null
      change_doc['updateDescription']['removedFields']&.each do |field|
        doc[field] = nil
      end
      if Array(change_doc['updateDescription']['truncatedArrays']).length > 0
        log.warn("Truncated arrays detected in update for #{change_doc.inspect}. This is not supported.")
      end
      unsafe_handle_exceptions(ns, doc) do
        @sql.upsert_ns(ns, doc)
      end
    end

    def on_delete(ns, change_doc)
      if options[:ignore_delete]
        log.debug("Ignoring delete op on #{ns} as instructed.")
      else
        key = change_doc['documentKey']
        @sql.delete_ns(ns, key)
      end
    end

    def on_replace(ns, change_doc)
      on_delete(ns, change_doc)
      on_insert(ns, change_doc)
    end

    def on_rename(ns, change_doc)
      # a collection is renamed
      new_db = change_doc['to']['db']
      new_collection_name = change_doc['to']['coll']
      new_ns = "#{new_db}.#{new_collection_name}"
      log.info("Renaming collection #{ns} to #{new_ns}")
    end

  end
end
