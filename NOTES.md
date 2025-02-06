
```
docker buildx build --load -t mosql .
```

```
docker  run -it -v $(pwd -P):/app mosql
```

```
def symbolize_keys(hash)
  Hash[hash.map{|k,v| v.is_a?(Hash) ? [k.to_sym, symbolize_keys(v)] : [k.to_sym, v] }]
end
```

```aiignore
export MONGOSQL_TEST_SQL=postgres://test:test@localhost:5433/mosql
export MONGOSQL_TEST_MONGO=mongodb://test:test@localhost:27018
export MONGOSQL_TEST_MONGO_DB=admin
```