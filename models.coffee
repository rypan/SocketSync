mongoose = require 'mongoose'
cheerio = require 'cheerio'

# _ = require 'underscore'

###### Account #######

noteSchema = new mongoose.Schema
  content:
    type: String
    default: ""
  creationDate: Date
  modificationDate: Date

# data params: timestamp, underneath_timestamp, text
noteSchema.methods.syncLine = (data, cb) ->
  if !data.timestamp then return

  $ = cheerio.load(@content)

  lineForTimestamp = (timestamp) ->
    $("div[data-timestamp=#{timestamp}]")

  lineForUnderneathTimestamps = (underneathTimestamps) ->
    $line = []

    while $line.length is 0 and underneathTimestamps.length > 0
      $line = lineForTimestamp(underneathTimestamps.shift())

    $line


  $existingLine = $("div[data-timestamp=#{data.timestamp}]")

  if $existingLine.length > 0 # update line
    $existingLine.html(data.text)

  else # create line
    newLine = "<div class='node' data-timestamp='#{data.timestamp}'>#{data.text}</div>"

    $underneath = lineForUnderneathTimestamps(data.underneath_timestamps.slice(0))

    if data.underneath_timestamps is "" or $underneath.length is 0
      $.root().prepend(newLine)

    else
      $underneath.after(newLine)

  @content = $.html()
  @save ->
    cb('lineSynced', data)

# data params: timestamp
noteSchema.methods.removeLine = (data, cb) ->
  $ = cheerio.load(@content)
  $("div[data-timestamp=#{data.timestamp}]").remove()
  @content = $.html()
  @save ->
    cb('lineRemoved', data)

noteSchema.pre 'save', (next) ->
  @updated_at = new Date
  @created_at ||= new Date
  next()

exports.note = DB.model('Note', noteSchema)
