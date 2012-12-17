express = require 'express'
http = require 'http'
path = require 'path'
mongoose = require 'mongoose'

require 'express-mongoose'

global.DB = mongoose.createConnection('localhost', 'socketsync')

app = express()
app.set("trust proxy", true)

server = http.createServer(app)
io = require('socket.io').listen(server)

app.configure ->
  app.set('port', process.env.PORT || 3000)
  app.set('views', __dirname + '/views')
  app.set('view engine', 'jade')
  app.use(express.favicon())
  app.use(express.logger('dev'))
  app.use(express.bodyParser())
  app.use(express.methodOverride())
  app.use(express.cookieParser('your secret here'))
  app.use(express.session())
  app.use(app.router)
  app.use require('connect-assets')()
  app.use(express.static(path.join(__dirname, 'public')))

app.configure 'development', ->
  app.use(express.errorHandler())

Note = require('./models').note

app.get '/', (req, res) ->
  Note.create {}, (err, note) ->
    res.redirect "note/#{note.id}"

app.get '/note/:id', (req, res) ->
  Note.findById req.params.id, (err, note) ->
    res.render "note", {note: note}

# routes.init(app)

io.sockets.on 'connection', (socket) ->

  socket.on 'setNote', (note_id) =>
    socket.join(note_id)
    socket.note_id = note_id

  socket.on 'note.addDiv', (data) ->
    data.note_id = socket.note_id
    Note.findById data.note_id, (err, note) ->
      note.addDiv data, (params) ->
        socket.broadcast.to(note.id).emit 'note.divAdded', params

  socket.on 'note.removeDiv', (data) ->
    data.note_id = socket.note_id
    Note.findById data.note_id, (err, note) ->
      note.removeDiv data, (params) ->
        socket.broadcast.to(note.id).emit 'note.divRemoved', params

server.listen app.get('port'), ->
  console.log("Express server listening on port " + app.get('port'))