# mongoose = require 'mongoose'
# _ = require 'underscore'
# moment = require 'moment'

# ###### Account #######

# accountSchema = new mongoose.Schema
#   _scraper:
#     type: mongoose.Schema.Types.ObjectId
#     ref: 'Scraper'
#   name: String
#   updated_at: Date
#   nickname: String
#   balance:
#     type: Number
#     set: (n) ->
#       return parseFloat(n.replace(",", ""))
#   transactions: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Transaction' }]

# accountSchema.virtual('balance_pretty').get ->
#   if this.balance > 0
#     return "$#{this.balance.toFixed(2)}"
#   else
#     return "-$#{Math.abs(this.balance).toFixed(2)}"

# accountSchema.statics.json = (filters) ->
#   promise = new mongoose.Promise()

#   this.find(filters || {})
#       .exec (err, accounts) ->

#     returnArray = []

#     _.each accounts, (account) ->
#       returnArray.push account.toObject({getters: true})

#     promise.complete(returnArray)

#   return promise


# ###### Transaction ######

# transactionSchema = new mongoose.Schema
#   _account:
#     type: mongoose.Schema.Types.ObjectId
#     ref: 'Account'
#   bank_id: String
#   name: String
#   amount:
#     type: Number
#     set: (n) ->
#       return parseFloat(n.replace(",", ""))
#   date: Date

# transactionSchema.virtual('amount_pretty').get ->
#   if this.amount > 0
#     return "$#{this.amount.toFixed(2)}"
#   else
#     return "-$#{Math.abs(this.amount).toFixed(2)}"

# transactionSchema.virtual('date_pretty').get ->
#   moment(this.date).fromNow()

# transactionSchema.statics.json = (filters) ->
#   promise = new mongoose.Promise()

#   this.find(filters || {})
#       .populate('_account')
#       .sort('-date')
#       .exec (err, transactions) ->

#     returnArray = []

#     _.each transactions, (transaction) ->
#       returnArray.push transaction.toObject({getters: true})

#     promise.complete(returnArray)

#   return promise


# ###### Scraper ######

# scraperSchema = new mongoose.Schema
#   file: String
#   fields: String
#   creds: {}

# ###### Preference ######

# preferenceSchema = new mongoose.Schema
#   encrypted_encryption_key: String
#   scrapers: [scraperSchema]

# preferenceSchema.statics.findOrCreate = (cb) ->
#   promise = new mongoose.Promise()
#   Preference = this

#   this.findOne (err, preference) ->
#     if preference
#       if cb then return cb(preference) else promise.complete(preference)
#     else
#       preference = new Preference
#       preference.save (err) ->
#         if cb then return cb(preference) else promise.complete(preference)

#   if !cb then return promise

# ###### EXPORTS #######

# exports.account = DB.model('Account', accountSchema)
# exports.transaction = DB.model('Transaction', transactionSchema)
# exports.preference = DB.model('Preference', preferenceSchema)
# exports.scraper = DB.model('Scraper', scraperSchema)
