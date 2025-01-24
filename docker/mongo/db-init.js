db.grantRolesToUser("test",[{role:"readWrite",db:"test"}])
db = db.getSiblingDB('test')

db.createCollection('placeholders')

placeholders = db.getCollection('placeholders')

placeholders.insertMany([
    {name:'This is a placeholder'}
])