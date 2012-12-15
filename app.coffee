express = require 'express'
# routes = require './routes'
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

  socket.on 'setNote', (data) =>
    socket.join(data)

  socket.on 'note.addDiv', (data) ->
    Note.findById data.note_id, (err, note) ->
      note.addDiv data.div, (params) ->
        socket.broadcast.to(note.id).emit 'note.divAdded', params

  socket.on 'note.addDivUnderneath', (data) ->
    Note.findById data.note_id, (err, note) ->
      note.addDivUnderneath data.div, data.underneath_id, (params) ->
        socket.broadcast.to(note.id).emit 'note.divAdded', params

server.listen app.get('port'), ->
  console.log("Express server listening on port " + app.get('port'))