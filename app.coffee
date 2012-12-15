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

app.get '/', (req, res) ->
  Note = require('./models').note
  Note.create {}, (err, note) ->
    res.redirect "note/#{note.id}"

app.get '/note/:id', (req, res) ->
  Note = require('./models').note
  Note.findById req.params.id, (err, note) ->
    res.render "note", {note: note}

# routes.init(app)

io.sockets.on 'connection', (socket) ->

  socket.on 'setNote', (data) =>
    socket.join(data)
    console.log "joined #{data}"

  ## add div ##
  socket.on 'note.addDiv', (data) ->
    Note = require('./models').note

    return unless data.note_id

    Note.findById data.note_id, (err, note) ->
      note.addDiv data.div, ->
        console.log "room: #{note.id}"
        io.sockets.in(note.id).emit 'note.divAdded', data.div

server.listen app.get('port'), ->
  console.log("Express server listening on port " + app.get('port'))