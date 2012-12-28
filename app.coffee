express = require 'express'
http = require 'http'
path = require 'path'
mongoose = require 'mongoose'
redis = require 'redis'
RedisStore  = require('connect-redis')(express);

require 'express-mongoose'

if process.env.DATABASE_CONNECTION_STRING
  global.DB = mongoose.createConnection(process.env.DATABASE_CONNECTION_STRING)
else
  global.DB = mongoose.createConnection('localhost', 'socketsync')

app = express()
app.set("trust proxy", true)

server = http.createServer(app)
io = require('socket.io').listen(server)

if process.env.REDIS_HOST
  redisStore = new RedisStore
    host: process.env.REDIS_HOST
    pass: process.env.REDIS_PW
    port: 6379
    maxAge: 1209600000

else
  redisStore = new RedisStore
    host: "localhost"
    pass: ""
    port: 6379
    maxAge: 1209600000

app.configure ->
  app.set('port', process.env.PORT || 3000)
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
  Note.create {}, (err, note) ->
    res.redirect "mochi/#{note.id}"

app.get '/mochi/:id', (req, res) ->
  Note.findById req.params.id, (err, note) ->
    res.render "mochi", {note: note}

app.get '/note/:id', (req, res) ->
  Note.findById req.params.id, (err, note) ->
    res.render "note", {note: note}

io.sockets.on 'connection', (socket) ->

  syncEventsQueue = []
  syncTimeouts = {}

  setupSocket = (params, cb) =>
    socket.noteId = params.noteId
    socket.username = params.username
    socket.join(socket.noteId)
    Note.findById socket.noteId, (err, note) =>
      @note = note
      if cb then cb()

  queueSyncDown = (note) ->

    syncTimeouts[note.id] ||= setTimeout =>
      syncTimeouts[note.id] = false
      socket.broadcast.to(note.id).emit "syncDown", syncEventsQueue.splice(0)
    , 500

  socket.on 'setup', setupSocket

  socket.on 'syncUp', (syncQueue, setupParams) =>

    processSyncQueue = (syncQueue) =>
      return if syncQueue.length is 0
      item = syncQueue.shift()

      @note[item[0]] item[1], (eventName, params) =>
        syncEventsQueue.push [eventName, params, socket.username]
        processSyncQueue(syncQueue)

      queueSyncDown(@note)

    if !@note
      setupSocket setupParams, ->
        processSyncQueue(syncQueue)
    else
      processSyncQueue(syncQueue)

server.listen app.get('port'), ->
  console.log("Express server listening on port " + app.get('port')) unless process.env.SUBDOMAIN