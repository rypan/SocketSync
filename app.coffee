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
  res.send("hello world!")

app.get '/note/:id', (req, res) ->
  res.render "note", {id: req.params.id}

# routes.init(app)

io.sockets.on 'connection', (socket) ->
  socket.emit('news', { hello: 'wor!ld' })

  socket.on 'yell', (data) ->
    socket.emit 'news', data.toUpperCase()

  socket.on 'yellToAll', (data) ->
    io.sockets.emit 'news', data.toUpperCase()

server.listen app.get('port'), ->
  console.log("Express server listening on port " + app.get('port'))