
require File.join(File.dirname(__FILE__), '_lib.rb')
require 'mosql/cli'

class MoSQL::Test::Functional::ChangeStreamStreamerTest < MoSQL::Test::Functional
  def build_streamer
    MoSQL::ChangeStreamStreamer.new({},
                                    mongo,
                        @adapter,
                        @map)
  end

  describe 'with a basic schema' do
    TEST_MAP = <<EOF
---
mosql_test:
  collection:
    :meta:
      :table: sqltable
    :columns:
      - _id: TEXT
      - var: INTEGER
      - arry: INTEGER ARRAY
  renameid:
    :meta:
      :table: sqltable2
    :columns:
      - id:
        :source: _id
        :type: TEXT
      - goats: INTEGER
  dotted_test:
    :meta:
      :table: dotted_table
    :columns:
      - _id: TEXT
      - sku_id:
        :source: sku._id
        :type: TEXT
      - sku_name:
        :source: sku.name
        :type: TEXT

composite_key_test:
  collection:
    :meta:
      :table: composite_table
      :composite_key:
        - store
        - time
    :columns:
      - store:
        :source: _id.s
        :type: TEXT
      - time:
        :source: _id.t
        :type: TIMESTAMP
      - var: TEXT
EOF

    before do
      @map = MoSQL::Schema.new(YAML.load(TEST_MAP, permitted_classes: [BSON::ObjectId, Symbol]))
      @adapter = MoSQL::SQLAdapter.new(@map, sql_test_uri)

      @sequel.drop_table?(:sqltable)
      @sequel.drop_table?(:sqltable2)
      @sequel.drop_table?(:dotted_table)
      @sequel.drop_table?(:composite_table)
      @map.create_schema(@sequel)

      @streamer = build_streamer
    end

    it 'handle "delete"' do
      o = { '_id' => BSON::ObjectId.new, 'var' => 17 }
      @adapter.upsert_ns('mosql_test.collection', o)

      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"delete",
          "ns" => {"db"=>"mosql_test", "coll"=>"collection"},
          "documentKey"=>{"_id"=> o['_id']}
        }))
      assert_equal(0, sequel[:sqltable].where(:_id => o['_id'].to_s).count)
    end

    it 'handle "update" with all fields and no removed fields' do
      o = { '_id' => BSON::ObjectId.new, 'var' => 17, 'arry' => [1, 2, 3] }
      @adapter.upsert_ns('mosql_test.collection', o)
      assert_equal(17, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_equal([1,2,3], sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])

      # updates are a hack where we read the object mongo so make sure the new object exists in mongo
      mongo.use('mosql_test')['collection'].insert_one(o.merge('var' => 100, 'arry': [3,2,1]),
                                                       :w => 1)

      @streamer.handle_op(BSON::Document.new(
        {
           "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
           "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
           "_id"=>{"_data"=>"TOKEN"},
           "operationType"=>"update",
           "ns" => {"db"=>"mosql_test", "coll"=>"collection"},
           "documentKey"=>{"_id"=> o['_id']},
           "updateDescription" => {
             "updatedFields"  => { 'var' => 100 , 'arry': [3,2,1]},
             "removedFields" => [],
             "truncatedArrays" => []
           }
        }))
      assert_equal(100, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_equal([3,2,1], sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])
    end

    it 'handle "update" with partial fields and removed fields' do
      o = { '_id' => BSON::ObjectId.new, 'var' => 17, 'arry' => [1, 2, 3] }
      @adapter.upsert_ns('mosql_test.collection', o)
      assert_equal(17, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_equal([1,2,3], sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])

      # updates are a hack where we read the object mongo so make sure the new object exists in mongo
      mongo.use('mosql_test')['collection'].insert_one(o.merge('var' => 100, 'arry' => nil),
                                                       :w => 1)

      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"update",
          "ns" => {"db"=>"mosql_test", "coll"=>"collection"},
          "documentKey"=>{"_id"=> o['_id']},
          "updateDescription" => {
            "updatedFields"  => { 'var' => 100 },
            "removedFields" => ['arry'],
            "truncatedArrays" => []
          }
        }))
      assert_equal(100, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_nil(sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])
    end

    it 'handle "replace"' do
      o = { '_id' => BSON::ObjectId.new, 'var' => 17, 'arry' => [1, 2, 3] }
      @adapter.upsert_ns('mosql_test.collection', o)
      assert_equal(17, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])

      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"replace",
          "ns" => {"db"=>"mosql_test", "coll"=>"collection"},
          "documentKey"=>{"_id"=> o['_id']},
          "fullDocument" => {
            "_id"=> o['_id'],
            'var' => 100,
          }
        }))
      assert_equal(100, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_nil(sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])
    end

    it 'handle "insert" existing record' do
      o = { '_id' => BSON::ObjectId.new, 'var' => 17 }
      @adapter.upsert_ns('mosql_test.collection', o)
      assert_equal(17, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])

      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"insert",
          "ns" => {"db"=>"mosql_test", "coll"=>"collection"},
          "documentKey"=>{"_id"=> o['_id']},
          "fullDocument" => {
            "_id"=> o['_id'],
            'var' => 100,
          }
        }))
      assert_equal(100, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_nil(sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])
    end

    it 'handle "insert" with no existing record' do
      o = { '_id' => BSON::ObjectId.new }

      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"insert",
          "ns" => {"db"=>"mosql_test", "coll"=>"collection"},
          "documentKey"=>{"_id"=> o['_id']},
          "fullDocument" => {
            "_id"=> o['_id'],
            'var' => 100,
            'arry' => [1, 2, 3]
          }
        }))
      assert_equal(100, sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:var])
      assert_equal([1, 2, 3], sequel[:sqltable].where(:_id => o['_id'].to_s).select.first[:arry])
    end

    it 'handle "update" with dotted fields' do
      o = { '_id' => BSON::ObjectId.new, 'var' => 17, 'sku' => {
        '_id' => BSON::ObjectId.new, 'name' => 'test'
      } }
      @adapter.upsert_ns('mosql_test.dotted_test', o)
      assert_equal(o['sku']['_id'].to_s, sequel[:dotted_table].where(:_id => o['_id'].to_s).select.first[:sku_id])
      assert_equal(o['sku']['name'], sequel[:dotted_table].where(:_id => o['_id'].to_s).select.first[:sku_name])

      # updates are a hack where we read the object mongo so make sure the new object exists in mongo
      updated_o = o.merge('sku' => o['sku'].merge({"name" => "test2"}))
      mongo.use('mosql_test')['dotted_test'].insert_one(updated_o, :w => 1)
      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"update",
          "ns" => {"db"=>"mosql_test", "coll"=>"dotted_test"},
          "documentKey"=>{"_id"=> o['_id']},
          "updateDescription" => {
            "updatedFields"  => { 'sku' => {"name" => "not_using_this"} },
            "removedFields" => [],
            "truncatedArrays" => []
          }
        }))
      assert_equal(o['sku']['_id'].to_s, sequel[:dotted_table].where(:_id => o['_id'].to_s).select.first[:sku_id])
      assert_equal('test2', sequel[:dotted_table].where(:_id => o['_id'].to_s).select.first[:sku_name])
    end
  end


  describe 'timestamps' do
    TIMESTAMP_MAP = <<EOF
---
db:
  has_timestamp:
    :meta:
      :table: has_timestamp
    :columns:
      - _id: TEXT
      - ts: timestamp
EOF

    before do
      @map = MoSQL::Schema.new(YAML.load(TIMESTAMP_MAP))
      @adapter = MoSQL::SQLAdapter.new(@map, sql_test_uri)

      mongo.use('db')['has_timestamp'].drop
      @sequel.drop_table?(:has_timestamp)
      @map.create_schema(@sequel)

      @streamer = build_streamer
    end

    it 'preserves milliseconds on tailing' do
      ts = Time.utc(2006,01,02, 15,04,05,678000)
      id = mongo.use('db')['has_timestamp'].insert_one({ts: ts}).inserted_id
      o =  mongo.use('db')['has_timestamp'].find({_id: id}).first
      @streamer.handle_op(BSON::Document.new(
        {
          "clusterTime"=>BSON::Timestamp.new(1737859517, 2),
          "wallTime" => Time.at(1737859517, 556, :millisecond).utc.to_bson,
          "_id"=>{"_data"=>"TOKEN"},
          "operationType"=>"insert",
          "ns" => {"db"=>"db", "coll"=>"has_timestamp"},
          "fullDocument"  => o,
          "documentKey"=>{"_id"=> id}
        }))
      got = @sequel[:has_timestamp].where(:_id => id.to_s).select.first[:ts]
      assert_equal(ts.to_i, got.to_i)
      assert_equal(ts.tv_usec, got.tv_usec)
    end
  end
end
