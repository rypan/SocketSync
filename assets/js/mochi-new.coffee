# $(document).on "keydown", "#note", (e) ->
#   return unless e.keyCode is 13

#   console.log $(@)

bound = false

socket = io.connect()
socket.emit('setNote', SocketSync.note_id)

removeDiv = ($div) ->
  console.log "removing", $div
  socket.emit 'note.removeDiv',
    div_id: $div.data 'timestamp'

updateDiv = ($div) ->
  #

addDiv = ($div) ->
  console.log $div.data('timestamp')
  return unless $div[0]
  if $div.data('timestamp') then return updateDiv($div)
  $div.data 'timestamp', Date.now()
  console.log $div.data 'timestamp'

  socket.emit 'note.addDiv',
    underneath_id: if $div.prev() then $div.prev().data('timestamp') else ""
    div: "<div data-timestamp='#{$div.data('timestamp')}'>#{$div.html()}</div>"

  console.log "added", $div[0].outerHTML

findPreviousDiv = ($div) ->
  $div.prev()


$(document).on "focus", "#note", ->
  return if bound
  bound = true

  $(document).create "div", (e) ->
    return unless e.target.nodeName = "DIV"
    addDiv findPreviousDiv($(e.target))

  $(document).on "DOMNodeRemoved", (e) ->
    return if e.srcElement.nodeName is "BR"
    removeDiv $(e.target)


socket.on 'note.divAdded', (data) ->
  console.log "received", data
  if !data.underneath_id
    # insert at top
    $("#note").prepend(data.div)
  else
    # insert data.div underneath the correct div
    $("#note div[data-timestamp=#{data.underneath_id}]").after(data.div)

# updateDiv = (data) ->
#   $("div[data-timestamp=#{data.div_id}]").html(data.new_text)

socket.on 'note.divRemoved', (data) ->
  $("#note div[data-timestamp=#{data.div_id}]").remove()



# socket.on 'note.divUpdated', updateDiv
, removeDiv


$(document).on "submit", "#update-line-form", (e) ->
  e.preventDefault()

  params =
    div_id: $(this).find(".div-id").val()
    new_text: $(this).find(".div-text").val()

  socket.emit 'note.updateDiv', params

  updateDiv params

  $(this).find("input").val("")
  resetUpdateFormLocation()

$(document).on "click", "#insert-row", ->
  line = $(this).closest("div")
  $("#add-line-form").insertAfter(line)
  $("#add-line-form #underneath-id").val(line.data('timestamp'))

$(document).on "click", "#delete-row", ->
  line = $(this).closest("div")

  socket.emit 'note.removeDiv',
    div_id: line.data('timestamp')

  removeDiv(line.data('timestamp'))

$(document).on "click", "#update-row", ->
  line = $(this).closest("div")
  tempLine = line.clone()
  tempLine.find("span:last").remove()
  $("#update-line-form").insertAfter(line).show()
  $("#update-line-form .div-id").val(line.data('timestamp'))
  $("#update-line-form .div-text").val(tempLine.html())
