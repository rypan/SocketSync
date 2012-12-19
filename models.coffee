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

noteSchema.methods.addDiv = (data, cb) ->
  $ = cheerio.load(@content)
  if data.underneath_id is "" or $("div[data-timestamp=#{data.underneath_id}]").length is 0
    console.log "couldnt' find or at top"
    @content = data.div + @content

  else
    $("div[data-timestamp=#{data.underneath_id}]").after(data.div)
    @content = $.html()

  @save ->
    cb
      div: data.div
      underneath_id: data.underneath_id

noteSchema.methods.updateDiv = (data, cb) ->
  $ = cheerio.load(@content)
  $("div[data-timestamp=#{data.div_id}]").html(data.new_text)
  @content = $.html()

  @save ->
    cb
      div_id: data.div_id
      new_text: data.new_text

noteSchema.methods.removeDiv = (data, cb) ->
  $ = cheerio.load(@content)
  $("div[data-timestamp=#{data.div_id}]").remove()
  @content = $.html()

  @save ->
    cb
      div_id: data.div_id

noteSchema.pre 'save', (next) ->
  @updated_at = new Date
  @created_at ||= new Date
  next()

exports.note = DB.model('Note', noteSchema)
