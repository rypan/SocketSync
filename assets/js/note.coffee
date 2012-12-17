resetFormLocation = ->
  $("#add-line-form").insertBefore(".note-body")

addDiv = (data) ->
  if data.underneath_id is ""
    # insert at top
    $(".note-body").prepend(data.div)
  else
    # insert data.div underneath the correct div
    $("div[data-timestamp=#{data.underneath_id}]").after(data.div)

socket = io.connect 'http://localhost:3000'
socket.emit('setNote', SocketSync.note_id)

socket.on 'note.divAdded', addDiv

$(document).on
  mouseenter: ->
    $(this).append """
      <span>&nbsp; <a href="#" id="insert-row">Insert</a> <a href="#" id="update-row">Update</a> <a href="#" id="delete-row">Delete</a></span>
    """

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

  addDiv
    underneath_id: $("#underneath-id").val()
    div: divHtml

  $(this).find("input").val("")
  resetFormLocation()

$(document).on "click", "#insert-row", ->
  line = $(this).closest("div")
  $("#add-line-form").insertAfter(line)
  $("#add-line-form #underneath-id").val(line.data('timestamp'))
