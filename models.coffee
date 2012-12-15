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
  @content = data + @content
  @save ->
    cb
      content: data

noteSchema.methods.addDivUnderneath = (data, underneath_id, cb) ->
  $ = cheerio.load(@content)

  $("div[data-timestamp=#{underneath_id}]").after(data)

  @content = $.html()

  @save ->
    cb
      content: data
      underneath_id: underneath_id

noteSchema.pre 'save', (next) ->
  @updated_at = new Date
  @created_at ||= new Date
  next()

exports.note = DB.model('Note', noteSchema)
