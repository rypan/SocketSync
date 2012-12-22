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

  $existingLine = $("div[data-timestamp=#{data.timestamp}]")

  if $existingLine.length > 0 # update line
    $existingLine.html(data.text)

  else # create line
    newLine = "<div class='node' data-timestamp='#{data.timestamp}'>#{data.text}</div>"

    if data.underneath_timestamp is "" or $("div[data-timestamp=#{data.underneath_timestamp}]").length is 0
      $.root().prepend(newLine)

    else
      $("div[data-timestamp=#{data.underneath_timestamp}]").after(newLine)

  @content = $.html()
  @save ->
    cb(data)

# data params: timestamp
noteSchema.methods.removeLine = (data, cb) ->
  $ = cheerio.load(@content)
  $("div[data-timestamp=#{data.timestamp}]").remove()
  @content = $.html()
  @save ->
    cb(data)

noteSchema.pre 'save', (next) ->
  @updated_at = new Date
  @created_at ||= new Date
  next()

exports.note = DB.model('Note', noteSchema)
