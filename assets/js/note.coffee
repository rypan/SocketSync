socket = io.connect 'http://localhost:3000', (socket) ->
  socket.emit('setNote', SocketSync.note_id)

socket.on 'note.divAdded', (data) ->
  if data.underneath_id
    # insert data.content underneath the correct div
    # do it here
  else
    # insert at top
    $(".note-body").prepend(data.content)


$(document).on
  mouseenter: ->
    $(this).append($('<span>&nbsp; <a href="#" id="insert-row">Insert</a> <a href="#" id="update-row">Update</a> <a href="#" id="delete-row">Delete</a></span>'));
  mouseleave: ->
    $(this).find("span:last").remove()
, ".note-body > div"


$(document).on "submit", "#add-line-form", (e) ->
  e.preventDefault()

  divHtml = """
    <div data-timestamp="#{Date.now()}">
      #{$("#line-text").val()}
    </div>
  """

  socket.emit 'note.addDiv',
    note_id: SocketSync.note_id
    underneath_id: $("#underneath-id").val()
    div: divHtml

  $(".note-body").prepend(divHtml)

  $(this).find("input").val("")

