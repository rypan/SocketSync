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
  if data.underneath_id is ""
    @content = data.div + @content

  else
    $ = cheerio.load(@content)
    $("div[data-timestamp=#{data.underneath_id}]").after(data.div)
    @content = $.html()

  @save ->
    cb
      div: data.div
      underneath_id: data.underneath_id

noteSchema.pre 'save', (next) ->
  @updated_at = new Date
  @created_at ||= new Date
  next()

exports.note = DB.model('Note', noteSchema)
