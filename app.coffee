express = require 'express'
path = require 'path'
mongoose = require 'mongoose'
redis = require 'redis'
RedisStore  = require('connect-redis')(express);
sharejs = require('share').server

require 'express-mongoose'

if process.env.DATABASE_CONNECTION_STRING
  global.DB = mongoose.createConnection(process.env.DATABASE_CONNECTION_STRING)
else
  global.DB = mongoose.createConnection('localhost', 'socketsync')

app = express()
app.set("trust proxy", true)

if process.env.REDIS_HOST
  redisStore = new RedisStore
    host: process.env.REDIS_HOST
    pass: process.env.REDIS_PW
    port: 6379

else
  redisStore = new RedisStore
    host: "localhost"
    pass: ""
    port: 6379

app.configure ->
  app.set('port', process.env.PORT || 8000)
  app.set('views', __dirname + '/views')
  app.set('view engine', 'jade')
  app.use(express.favicon())
  app.use(express.logger('dev'))
  app.use(express.bodyParser())
  app.use(express.methodOverride())
  app.use(express.cookieParser('your secret here'))
  app.use express.session
    secret: 'this is a great session secret, really.'
    store: redisStore
  app.use(app.router)
  app.use require('connect-assets')()
  app.use(express.static(path.join(__dirname, 'public')))

app.configure 'development', ->
  app.use(express.errorHandler())

Note = require('./models').note

app.get '/', (req, res) ->
  res.send 'index'

app.get '/mochi', (req, res) ->
  Note.create {}, (err, note) ->
    res.redirect "mochi/#{note.id}"

app.get '/mochi/:id', (req, res) ->
  Note.findById req.params.id, (err, note) ->
    res.render "mochi", {note: note}

app.get '/note/:id', (req, res) ->
  Note.findById req.params.id, (err, note) ->
    res.render "note", {note: note}

redisConfig = {type: 'redis'}

if process.env.REDIS_HOST
  redisConfig.hostname = process.env.REDIS_HOST
  redisConfig.authPassword = process.env.REDIS_PW

else
  redisConfig.hostname = "localhost"

options = {db: redisConfig, browserChannel: {cors:"*"}}

sharejs.attach(app, options)

app.listen(app.get('port'))
console.log("Express server listening on port " + app.get('port')) unless process.env.SUBDOMAIN