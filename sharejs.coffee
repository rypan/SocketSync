sharejs = require('share').server
connect = require 'connect'

redisConfig = {type: 'redis'}

if process.env.REDIS_HOST
  redisConfig.hostname = process.env.REDIS_HOST
  redisConfig.auth = process.env.REDIS_PW

else
  redisConfig.hostname = "localhost"
  redisConfig.auth = ""

server = connect(connect.logger())

options = {db: redisConfig, browserChannel: {cors:"*"}}

sharejs.attach(server, options)

server.listen(8000)
console.log('Server running at http://127.0.0.1:8000/')