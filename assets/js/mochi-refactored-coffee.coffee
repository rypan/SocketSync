`String.prototype.replaceCharacter = function (index, string) {
  if (index > 0)
    return this.substring(0, index) + string + this.substring(index + 1, this.length);
  else
    return string + this;
};
`
Helper =

  saveSelection: ->
    if window.getSelection
      sel = window.getSelection()
      return sel.getRangeAt(0)  if sel.getRangeAt and sel.rangeCount
    else return document.selection.createRange()  if document.selection and document.selection.createRange
    null

  restoreSelection: (range) ->
    if range
      if window.getSelection
        sel = window.getSelection()
        sel.removeAllRanges()
        sel.addRange range
      else range.select()  if document.selection and range.select

  getPasteData: (ev, cb) ->

    initialSelection = Helper.saveSelection()

    $elem = $("<div id='tempPaste' contenteditable='true'>Paste</div>")
    $("body").append($elem)
    $elem.focus()
    el = $elem[0]


    handlepaste = (elem, e) ->
      savedcontent = elem.innerHTML
      if e and e.clipboardData and e.clipboardData.getData # Webkit - get data from clipboard, put into editdiv, cleanup, then cancel event
        if /text\/html/.test(e.clipboardData.types)
          elem.innerHTML = e.clipboardData.getData("text/html")
        else if /text\/plain/.test(e.clipboardData.types)
          elem.innerHTML = e.clipboardData.getData("text/plain")
        else
          elem.innerHTML = ""
        waitforpastedata elem, savedcontent
      else # Everything else - empty editdiv and allow browser to paste content into it, then cleanup
        elem.innerHTML = ""
        waitforpastedata elem, savedcontent
    waitforpastedata = (elem, savedcontent) ->
      if elem.childNodes and elem.childNodes.length > 0
        return processpaste elem, savedcontent
      else
        that =
          e: elem
          s: savedcontent

        that.callself = ->
          return waitforpastedata that.e, that.s

        setTimeout ->
          return that.callself()
        , 20

        return
    processpaste = (elem, savedcontent) ->
      $elem = $(elem)
      $elem.find("[data-timestamp]").removeAttr('data-timestamp').data('timestamp', null)
      pasteddata = $elem[0].innerHTML

      #^^Alternatively loop through dom (elem.childNodes or elem.getElementsByTagName) here
      elem.innerHTML = savedcontent

      # Do whatever with gathered data;
      $elem.remove()
      $("#editor").focus()
      Helper.restoreSelection(initialSelection)
      cb(pasteddata)

    handlepaste(el, ev)

HostApp =
  noteChanged: ->
  triggerPaste: ->

window.MochiEditor = (noteId, username) ->
  self = this
  noteId = noteId
  username = username || "noname"
  setupParams =
    noteId: noteId
    username: username
  $el = $("#editor")
  $titleEl = $("#title")
  $titleHint = $("#title-hint")
  $noteEl = $("#note")
  syncTimeouts = []
  noteChangeTimeoutId = undefined
  addingRemoteChanges = false
  linesArray = {}
  syncQueue = []
  cursors = {}

  $titleEl.on "focus", ->
    $titleHint.addClass "text-hint-focused"

  $titleEl.on "blur", ->
    $titleHint.removeClass "text-hint-focused"

  $titleEl.on "keydown", (event) ->
    if event.keyCode is 13 or event.keyCode is 40
      self.focusEditor()
      # Prevent newline from being inserted into editor.
      event.preventDefault()

    setTimeout handleTitleChange, 0 # @checkup

  $titleEl.on "cut", ->
    setTimeout handleTitleChange, 0

  $titleEl.on "paste", ->
    setTimeout handleTitleChange, 0

  $el.on "focus.bindDOMSubtreeModified", ->
    $el.off ".bindDOMSubtreeModified"
    $el.on "DOMSubtreeModified", (event) ->
      queueContentChange(event)

  $el.on "paste", (event) ->
    Helper.getPasteData event, (pastedData) ->
      event.preventDefault()
      addingRemoteChanges = true #don't sync yet
      self.pasteText(pastedData)
      addingRemoteChanges = false
      self.timestampNodes()
      self.flattenNodes()

    # HostApp.triggerPaste()

  $el.on "webkitAnimationEnd", (event) ->
    $(event.target).removeClass "checkbox-animated"


  $el.on "keydown", (event) ->
    keyCode = event.keyCode
    if keyCode is 32 # space
      #insert checkbox conditionally
      sel = window.getSelection()
      line = getSelectedLines()[0]
      if line.childNodes[0].textContent.match(/^\s*\+$/)
        line.childNodes[0].textContent = line.childNodes[0].textContent.replace(/\+\s*$/, '')
        addCheckbox($(line))
        sel.modify "move", "forward", "lineboundary"
        event.preventDefault()

    else if keyCode is 8 # delete
      # Prevent deletion of last div.
      event.preventDefault() if $el[0].childNodes.length is 1 and $el[0].firstChild.childNodes.length is 1 and $el[0].firstChild.firstChild.tagName is "BR"

    else
      # if key is up and we're at the top, focus the title
      if keyCode is 38 # up
        selection = window.getSelection()
        line = getLine(selection.anchorNode)
        unless line.previousSibling
          startTop = line.offsetTop + 1
          origRange = selection.getRangeAt(0)
          currentRects = origRange.getClientRects()
          currentTop = undefined
          if currentRects.length
            currentTop = currentRects[0].top
          else
            currentTop = startTop
          self.focusTitle()  if currentTop <= startTop

      else if keyCode is 9 # tab
        event.preventDefault()
        insertHtml "\t"

      else if keyCode is 13 # return
        sel = window.getSelection()
        indent = getIndentString(getLine(sel.anchorNode))
        if indent
          setTimeout (->
            insertHtml indent
          ), 0
    # handleSelectionChange()

  $el.on "mouseup", ".checkbox", (event) ->
    toggleCheckbox $(@)
    # handleSelectionChange()


  # Disable drag.
  # $el.on "dragstart", (event) ->
  #   event.preventDefault()

  # Disable external drop.
  # $el.on "dragover", (event) ->
  #   event.preventDefault()


  # @checkup i think this is only used for pasting
  #
  # getSelRange = function() {
  #     var selection = window.getSelection();
  #     var start = indexFromNodeAndOffset(
  #         $el, selection.anchorNode, selection.anchorOffset
  #     );
  #     var end = indexFromNodeAndOffset(
  #         $el, selection.focusNode, selection.focusOffset
  #     );
  #     return [start, end];
  # }

  queueContentChange = (event) ->
    syncTimeouts.push setTimeout(->
        clearTimeout(i) for i in syncTimeouts
        self.cursorCharacterOffset = if event then getCaretCharacterOffsetWithin(event.target) else undefined
        handleContentChange() unless addingRemoteChanges
        self.cursorCharacterOffset = undefined
      , 500)

  makeCursor = (username) ->
    return if cursors[username]
    cursors[username] = $("<span class='cursor'><span class='name'>#{username}</span></span>")
    $noteEl.append(cursors[username])

  getCaretCharacterOffsetWithin = (element) ->
    caretOffset = 0
    unless typeof window.getSelection is "undefined" or !window.getSelection().anchorNode
      range = window.getSelection().getRangeAt(0)
      preCaretRange = range.cloneRange()
      preCaretRange.selectNodeContents element
      preCaretRange.setEnd range.endContainer, range.endOffset
      caretOffset = preCaretRange.toString().length
    else if typeof document.selection isnt "undefined" and document.selection.type isnt "Control"
      textRange = document.selection.createRange()
      preCaretTextRange = document.body.createTextRange()
      preCaretTextRange.moveToElementText element
      preCaretTextRange.setEndPoint "EndToEnd", textRange
      caretOffset = preCaretTextRange.text.length
    caretOffset

  lineForTimestamp = (timestamp) ->
    $("#editor div").filter ->
      `$(this).data("timestamp") == timestamp`

  lineForUnderneathTimestamps = (underneathTimestamps) ->
    $line = []

    while $line.length is 0 and underneathTimestamps.length > 0
      $line = lineForTimestamp(underneathTimestamps.shift())

    $line

  setEditable = (editable) ->
    if editable
      $el.attr "contenteditable", "true"
    else
      $el.removeAttr "contenteditable"

  nodeListToArray = (nodeList) ->
    returnArray = []
    length = nodeList.length
    i = 0

    while i < length
      returnArray.push nodeList.item(i)
      i++

    returnArray

  setOtherUsersCursorAtLocation = (top, right, username) ->
    if !cursors[username] then makeCursor(username)

    cursors[username].css
      left: right
      top: top

    .find(".name").text(username)

    cursors[username].show()

  setOtherUsersCursorOnLine = ($line, characterOffset, username) ->
    lastNode = $line[0].childNodes.item($line[0].childNodes.length - 1) || $line[0]

    if lastNode.nodeType is 3 # last child is a text node, wrap it in a span
      text = lastNode.textContent

      if characterOffset is 0
        lastChar = text.substr(-1)
        newText = text.slice(0, -1)
        tempEl = "<span id='getPos'>#{lastChar}</span>"
      else
        replaceChar = text[characterOffset - 1]
        newText = if characterOffset is 1 then "" else text.replaceCharacter characterOffset - 1, ""
        tempEl = "<span id='getPos'>#{replaceChar || ''}</span>"

      lastNode.textContent = newText
      $line.append(tempEl)
      offsetRight = $("#getPos").offset().left + $("#getPos").width()
      offsetTop = $("#getPos").offset().top
      $line.find("#getPos").remove()
      lastNode.textContent = text

    else if lastNode.nodeName is "BR"
      $br = $line.children(":last")
      $br.remove()
      $line.append("<span id='getPos'><br /></span>")
      offsetRight = $("#getPos").offset().left + $("#getPos").width()
      offsetTop = $("#getPos").offset().top
      $line.find("#getPos").remove()
      $line.append("<br />")

    else
      offsetRight = $(lastNode).offset().left + $(lastNode).width()
      offsetTop = $(lastNode).offset().top

    setOtherUsersCursorAtLocation(offsetTop, offsetRight, username)

  updateTitleHint = ->
    if $titleEl.val()
      $titleHint.hide()
    else
      $titleHint.show()

  handleTitleChange = ->
    # handleNoteChange();
    updateTitleHint()

  buildUnderneathTimestamps = ($line) ->
    i = 0
    returnArray = []

    while $line.length > 0 and i < 3
      returnArray.push $line.prev().data("timestamp")
      $line = $line.prev()
      i++

    returnArray

  syncLine = ($line) ->
    return  if linesArray[$line.data("timestamp")] is $line.html()
    timestamp = $line.data("timestamp")
    linesArray[timestamp] = $line.html()
    syncQueue.push ["syncLine",
      timestamp: timestamp
      underneath_timestamps: buildUnderneathTimestamps($line)
      text: linesArray[timestamp]
      characterOffset: self.cursorCharacterOffset
    ]


  removeLine = (timestamp) ->
    delete linesArray[timestamp]
    syncQueue.push ["removeLine", {timestamp: timestamp}]

  cleanupSync = ->
    for timestamp, line of linesArray
      if lineForTimestamp(timestamp).length is 0
        removeLine(timestamp)

  handleContentChange = ->
    $line = $el.children(":first")
    while $line.length > 0
      if $line.find(".checkbox").length > 0
        $line.addClass "task"
      else
        $line.removeClass "task"
      syncLine $line
      $line = $line.next()
    cleanupSync()
    syncUp()

  syncUp = ->
    socket.emit "syncUp", syncQueue.splice(0), setupParams

  # handleNoteChange();
  handleSelectionChange = ->


  # handleNoteChange();
  insertHtml = (html) ->
    document.execCommand "inserthtml", false, html


  getIndentString = (line) ->
    str = line.firstChild
    if str.nodeType is Node.TEXT_NODE
      text = str.textContent
      match = text.match(/\S/)
      if match
        return text.substring(0, match.index)
      else
        return text
    ""

  addCheckbox = ($line, addToBegginingOfLine, showAnimation = true) ->
    checkbox = "<img class='checkbox #{if showAnimation then 'checkbox-animated'}' src='' width='0' height='0' />"

    if addToBegginingOfLine
      # if line begins with whitespace, add after that whitespace
      if $line[0].childNodes[0].nodeType is 3 and whitespace = $line[0].childNodes[0].textContent.match(/^\s+/)
        $line[0].childNodes[0].textContent = $line[0].childNodes[0].textContent.replace(/^\s+/, "")
        $($line[0].childNodes[0]).before(whitespace)
        $($line[0].childNodes[0]).after(checkbox + " ")
      else
        # add at beginning
        $line.prepend(checkbox + " ")
    else
      $($line[0].childNodes[0]).after(checkbox + " ")


  self.toggleTask = ->
    lines = getSelectedLines()

    $(lines).each ->

      if $(@).find(".checkbox").length > 0
        # remove the checkbox
        $(@).find(".checkbox").remove()

        # if there's still a blank space at the beginning of the line, remove that too.
        if $(@)[0].childNodes[0].nodeType is 3 and $(@)[0].childNodes[0].textContent[0] is " "
          $(@)[0].childNodes[0].textContent = $(@)[0].childNodes[0].textContent.substring(1)

      else
        addCheckbox($(@), true, false)

  self.toggleTaskDone = ->
    lines = getSelectedLines()

    $(lines).each ->
      if $(@).find(".checkbox").length > 0
        toggleCheckbox($(@).find(".checkbox"))

    # @todo abide by the rules of the timeout!
    handleContentChange()

  toggleCheckbox = ($checkbox) ->
    $checkbox.toggleClass("checkbox-checked")


  # checkup new preservingSelection function

  $(document).on "DOMNodeRemoved", (e) ->
    return if addingRemoteChanges
    return if e.srcElement.nodeName isnt "DIV"
    $line = $(e.srcElement)
    removeLine $line.data("timestamp") if $line.hasClass("node")

  $(document).on "DOMNodeInserted", (e) ->
    return if addingRemoteChanges # @possible use '?'
    return if e.srcElement.nodeName isnt "DIV"
    return if $(e.srcElement).attr('id') is "tempPaste"
    $(e.srcElement).removeAttr "data-timestamp"
    $(e.srcElement).data "timestamp", Date.now()


  self.timestampNodes = ->
    $nodes = $el.find(".node").filter ->
      !$(@).data('timestamp')

    i = 0

    $nodes.each ->
      $(@).data('timestamp', "" + Date.now() + i)
      i++

  getLine = (node) ->
    node = node.parentNode while $(node.parentNode).attr('id') isnt "editor"
    node

  isBefore = (a, aOffset, b, bOffset) ->
    rangeA = document.createRange()
    rangeB = document.createRange()
    rangeA.setStart a, aOffset
    rangeA.setEnd a, aOffset
    rangeB.setStart b, bOffset
    rangeB.setEnd b, bOffset
    rangeA.compareBoundaryPoints(Range.START_TO_START, rangeB) is -1

  getSelectedLines = ->
    sel = window.getSelection()
    first = getLine(sel.anchorNode)
    last = getLine(sel.focusNode)
    if isBefore(last, 0, first, 0)
      temp = first
      first = last
      last = temp
    node = first
    divs = []
    while node
      divs.push node
      break  if node is last
      node = node.nextSibling
    divs

  # function getTasks() {
  #     var tasks = [];
  #     var checkboxes = editorEl.querySelectorAll('.checkbox');
  #     for (var i = 0; i < checkboxes.length; i++) {
  #         var checkbox = checkboxes[i];
  #         tasks.push({
  #             id: checkbox.id,
  #             complete: checkbox.classList.contains('checkbox-checked')
  #         });
  #     }
  #     return tasks;
  # }

  setupLinesArray = ->
    $el.find("[data-timestamp]").each ->
      linesArray[$(@).data('timestamp')] = $(@).html()

  self.show = ->
    $noteEl.show()

  self.hide = ->
    $noteEl.hide()

  self.setTitle = (title) ->
    $titleEl.val title
    updateTitleHint()

  self.setContent = (content, selectionStart, selectionEnd) ->
    # Need <br> so that text cursor shows up.
    content = "<div><br></div>"  unless content
    $el.html content

  # selectRange(selectionStart, selectionEnd);
  self.moveLineDown = ->

  self.moveLineUp = ->

  self.focusTitle = ->
    $titleEl.focus()

  self.focusEditor = ->
    $el.focus()

  self.pasteText = (text) ->
    insertHtml text

  self.flattenNodes = ->

    flattenChildren = (node) ->
      i = 0
      return if !node
      length = node.childNodes.length

      return node if length is 0

      while i < length
        if node.childNodes[i] and node.childNodes[i].nodeType is 1 and node.childNodes[i].classList and node.childNodes[i].classList.contains("node")
          if node.childNodes[i].parentNode.id isnt $el.attr('id')
            $(node.childNodes[i].parentNode).after node.childNodes[i]

          flattenChildren(node.childNodes[i])
        i++

    flattenChildren($el[0])

    queueContentChange()

  # getNoteData: function () {
  #     return {
  #         title: titleEl.value,
  #         content: editorEl.innerHTML,
  #         tasks: getTasks(),
  #         selection: getSelRange()
  #     };
  # }



  #### Initial Setup ####
  setEditable true
  setupLinesArray()

  socket = io.connect()
  socket.emit "setup", setupParams

  socket.on "note.lineSynced", (data, username) ->
    addingRemoteChanges = true
    $existingLine = lineForTimestamp(data.timestamp)

    if $existingLine.length > 0
      # update line
      $existingLine.html data.text
      setOtherUsersCursorOnLine($existingLine, data.characterOffset, username)

    else
      # create line
      $newLine = $("<div class='node' data-timestamp='" + data.timestamp + "'>" + data.text + "</div>")

        # @possible ==
      $underneathLine = lineForUnderneathTimestamps(data.underneath_timestamps)

      if !data.underneath_timestamps? or $underneathLine.length is 0
        $("#editor").prepend $newLine
      else
        $underneathLine.after $newLine

      setOtherUsersCursorOnLine($newLine, data.characterOffset, username)

    linesArray[data.timestamp] = data.text
    addingRemoteChanges = false

  socket.on "note.lineRemoved", (data, username) ->
    addingRemoteChanges = true
    lineForTimestamp(data.timestamp).remove()
    delete linesArray[data.timestamp]

    addingRemoteChanges = false

  return