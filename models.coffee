mongoose = require 'mongoose'
# _ = require 'underscore'

###### Account #######

noteSchema = new mongoose.Schema
  content: String
  creationDate: Date
  modificationDate: Date

noteSchema.pre 'save', (next) ->
  @updated_at = new Date
  @created_at ||= new Date
  next()

exports.account = DB.model('Note', noteSchema)
