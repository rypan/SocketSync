resetAddFormLocation = ->
  $("#add-line-form").insertBefore(".note-body")

resetUpdateFormLocation = ->
  $("#update-line-form").hide().insertBefore(".note-body")

addDiv = (data) ->
  if data.underneath_id is ""
    # insert at top
    $(".note-body").prepend(data.div)
  else
    # insert data.div underneath the correct div
    $("div[data-timestamp=#{data.underneath_id}]").after(data.div)

updateDiv = (data) ->
  $("div[data-timestamp=#{data.div_id}]").html(data.new_text)

removeDiv = (div_id) ->
  $("div[data-timestamp=#{div_id}]").remove()

socket = io.connect 'http://localhost:3000'
socket.emit('setNote', SocketSync.note_id)

socket.on 'note.divAdded', addDiv
socket.on 'note.divUpdated', updateDiv
socket.on 'note.divRemoved', (data) ->
  removeDiv(data.div_id)

$(document).on
  mouseenter: ->
    $(this).append """
      <span>&nbsp; <a href="#" id="insert-row">Insert Below</a> <a href="#" id="update-row">Update</a> <a href="#" id="delete-row">Delete</a></span>
    """

  mouseleave: ->
    $(this).find("span:last").remove()

, ".note-body > div"


$(document).on "submit", "#add-line-form", (e) ->
  e.preventDefault()

  divHtml = """
    <div data-timestamp="#{Date.now()}">#{$("#line-text").val()}</div>
  """

  socket.emit 'note.addDiv',
    underneath_id: $("#underneath-id").val()
    div: divHtml

  addDiv
    underneath_id: $("#underneath-id").val()
    div: divHtml

  $(this).find("input").val("")
  resetAddFormLocation()

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
