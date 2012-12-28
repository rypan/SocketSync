Helper =

  findPixelOffsetForNode: (node, characterOffset) ->

    return if !node

    $node = $(node)
    $line = $node.closest(".node")

    if node.nodeType is 3

      text = node.textContent

      if characterOffset is 0
        lastChar = text.substr(-1)
        newText = text.slice(0, -1)
        $tempEl = $("<span id='getPos'>#{lastChar}</span>")
      else
        replaceChar = text[characterOffset - 1]
        newText = if characterOffset is 1 then "" else text.slice 0, characterOffset - 1
        $tempEl = $("<span id='getPos'>#{replaceChar || ''}</span>")

      node.textContent = newText
      $(node).after($tempEl)
      offset =
        left: $tempEl.offset().left + $tempEl.width()
        top: $tempEl.offset().top
      $tempEl.remove()
      node.textContent = text


    else if node.nodeName is "BR"

      $(node).remove()
      $line.append("<span id='getPos'><br /></span>")
      offset =
        left: $("#getPos").offset().left + $("#getPos").width()
        top: $("#getPos").offset().top
      $line.find("#getPos").remove()
      $line.append("<br />")

    else
      # @ todo find offset in other elements
      offset =
        left: $node.offset().left + $node.width()
        top: $node.offset().top

    offset

  isBefore: (a, aOffset, b, bOffset) ->
    rangeA = document.createRange()
    rangeB = document.createRange()
    rangeA.setStart a, aOffset
    rangeA.setEnd a, aOffset
    rangeB.setStart b, bOffset
    rangeB.setEnd b, bOffset
    rangeA.compareBoundaryPoints(Range.START_TO_START, rangeB) is -1

  getIndentString: (node) ->
    if node.nodeType is Node.TEXT_NODE
      text = node.textContent
      match = text.match(/\S/)
      if match
        return text.substring(0, match.index)
      else
        return text
    ""

  # get the distance between the end of the line and the user's cursor
  getCaretCharacterOffsetWithin: (element) ->
    if !element or element.id is "editor" or !element.parentNode
      return {character: 0, node: 0}
    else if element.parentNode.id is "editor"
      return {character: 1, node: 0}

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


    nodeOffset = 0
    e = element
    while e = e.previousSibling
      nodeOffset++

    return {
      character: caretOffset
      node: nodeOffset
    }

  preserveSelection: (cb) ->
    selection = Helper.saveSelection()
    cb()
    Helper.restoreSelection(selection)

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

    $tempPaste = $("<div id='tempPaste' contenteditable='true'>Paste</div>")
    $("body").append($tempPaste)
    $tempPaste.focus()
    el = $tempPaste[0]

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

    processpaste = (tempEditor, savedcontent) ->
      $tempEditor = $(tempEditor)
      $tempEditor.find("[data-timestamp]").removeAttr('data-timestamp').data('timestamp', null)
      pasteddata = $tempEditor[0].innerHTML

      tempEditor.innerHTML = savedcontent

      # Do whatever with gathered data;
      $tempEditor.remove()
      $("#editor").focus()
      Helper.restoreSelection(initialSelection)
      cb(pasteddata)

    handlepaste(el, ev)

window.MochiEditor = (noteId, username) ->

  ################################################
  # Setup Variables
  ################################################

  self = this

  # the params used to setup our socket connection
  setupParams =
    noteId: noteId
    username: username || "noname"

  $editor = $("#editor")
  $titleEl = $("#title")
  $titleHint = $("#title-hint")
  $noteEl = $("#note")

  # holds the timeout id for our sync function
  syncTimeout = false

  # queue of changes to be synced
  syncQueue = []

  # this array holds a complete representation of our note, almost like a shadow-DOM,
  # except it's just a javascript array. this allow us to compare changes quickly and
  # only sync lines that need syncing.
  linesArray = {}

  cursors = {}
  cursorTimeouts = {}

  # setting this to "true" will temporarily disable the event listeners for DOM changes.
  stopListeningForChanges = false

  ################################################
  # Attach Event Listeners
  ################################################

  $titleEl.on "focus", ->
    $titleHint.addClass "text-hint-focused"

  $titleEl.on "blur", ->
    $titleHint.removeClass "text-hint-focused"

  # when the title is focused and we hit 'return', focus the main editor.
  $titleEl.on "keydown", (event) ->
    if event.keyCode is 13 or event.keyCode is 40
      self.focusEditor()
      event.preventDefault()

  $titleEl.on "input", ->
    # @todo why is there a timeout on this?
    setTimeout handleTitleChange, 0

  # listen for modifications to the dom, and queue a timeout that will handle the modifications.
  $editor.on "DOMSubtreeModified", (event) ->
    queueContentChange(event.srcElement) unless stopListeningForChanges

  # When we remove a top-level node, remove its counterpart from linesArray
  $editor.on "DOMNodeRemoved", (e) ->
    $node = $(e.srcElement)
    return unless is_top_level_node($node) and !stopListeningForChanges
    removeLine $node.data("timestamp") if $node.hasClass("node")

  # contenteditable inserts nodes by copying them from the previous one. listen for this event,
  # so we can change the timestamps to ensure we don't get duplicates.
  $editor.on "DOMNodeInserted", (e) ->
    $node = $(e.srcElement)
    return unless is_top_level_node($node) and !stopListeningForChanges
    timestamp_nodes($node)

  # on paste, use our helper to get the pasted data. insert it into the editor,
  # and make sure that we don't have multiple levels of top-level nodes.
  $editor.on "paste", (event) ->
    Helper.getPasteData event, (pastedData) ->
      event.preventDefault()

      # @todo make sure that any top-level nodes that get added have the class 'node'
      ignoreChanges ->
        self.pasteText(pastedData)

      self.timestampUntimestampedNodes()
      self.flattenNodes()

  # Remove checkbox animation after it's finished.
  $editor.on "webkitAnimationEnd", ".checkbox-animated", ->
    $(@).removeClass('checkbox-animated')

  # listen for various keyboard events
  $editor.on "keydown", (event) ->
    keyCode = event.keyCode

    # key: space
    # if our line consists of '+' and whitespace, we add a checkbox.
    if keyCode is 32
      sel = window.getSelection()
      line = getSelectedLines()[0]
      if line.childNodes[0].textContent.match(/^\s*\+$/)
        line.childNodes[0].textContent = line.childNodes[0].textContent.replace(/\+\s*$/, '')
        addCheckbox($(line))
        sel.modify "move", "forward", "lineboundary"
        event.preventDefault()

    # key: delete
    # prevent deletion of last div in contenteditable.
    else if keyCode is 8
      event.preventDefault() if $editor[0].childNodes.length is 1 and $editor[0].firstChild.childNodes.length is 1 and $editor[0].firstChild.firstChild.tagName is "BR"

    # key: up
    # if we're at the top of the editor and we hit the up key, focus the title input
    else
      if keyCode is 38
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

      # key: tab
      # insert a tab into the editor
      else if keyCode is 9
        event.preventDefault()
        insertHtml "\t"

      # key: return
      # if we're on an indented line and we hit return, indent the newly-created line too
      else if keyCode is 13
        sel = window.getSelection()
        indent = Helper.getIndentString(getLine(sel.anchorNode).firstChild)
        if indent
          setTimeout (->
            insertHtml indent # @todo why timeout?
          ), 0

  # toggle checkboxes when clicked
  $editor.on "click", ".checkbox", (event) ->
    toggleCheckbox $(@)

  # Disable drag.
  # $editor.on "dragstart", (event) ->
  #   event.preventDefault()

  # Disable external drop.
  # $editor.on "dragover", (event) ->
  #   event.preventDefault()

  # executes the provided callback while ignoring changes to the dom.
  ignore_changes = (cb) ->
    originalVal = stopListeningForChanges
    stopListeningForChanges = true
    cb()
    stopListeningForChanges = originalVal

  # returns true if $node's parent is $editor
  is_top_level_node = ($node) ->
    $node.parent().attr('id') is $editor.attr('id')

  # adds a 'data-timestamp' attributes to the given nodes
  timestamp_nodes = ($nodes) ->
    $nodes.each (i) ->
      $(@).data('timestamp', "" + Date.now() + i)
      i++

  # set a timeout for handleContentChange(), to ensure it gets called no more than once every X ms.
  queueContentChange = (srcElement) ->
    syncTimeout ||= setTimeout ->
      syncTimeout = false
      offset = if srcElement then Helper.getCaretCharacterOffsetWithin(srcElement)
      handleContentChange(offset) unless stopListeningForChanges
    , 500

  # find or create a remote user's cursor
  getCursor = (username) ->
    if !cursors[username]
      cursors[username] = $("<span class='cursor'><span class='name'>#{username}</span></span>")
      $noteEl.append(cursors[username])

    cursors[username]

  # find the node for a given timestamp
  nodeForTimestamp = (timestamp) ->
    $("#editor div").filter ->
      `$(this).data("timestamp") == timestamp`

  # loop through an array of underneath timestamps and return the first
  # node that exists. quick hack to deal with the edge case of trying to
  # insert a line underneath a line that doesn't exist.
  nodeForUnderneathTimestamps = (underneathTimestamps) ->
    $line = []

    while $line.length is 0 and underneathTimestamps.length > 0
      $line = nodeForTimestamp(underneathTimestamps.shift())

    $line

  # locate the pixel offset of another user's cursor and display it accordingly
  setOtherUsersCursorOnLine = ($line, offset, username) ->
    cursor = getCursor(username)

    node = $line[0].childNodes.item(offset.node || 0)

    offset = Helper.findPixelOffsetForNode(node, offset.character || 0)

    return unless offset

    cursor.css(offset).show()

    clearTimeout(cursorTimeouts[username])
    cursorTimeouts[username] = setTimeout ->
      cursor.hide()
    , 10000

  updateTitleHint = ->
    if $titleEl.val()
      $titleHint.hide()
    else
      $titleHint.show()

  handleTitleChange = ->
    # @todo save the title on the server
    updateTitleHint()

  # build an array of timestamps from the lines preceding the given line.
  buildUnderneathTimestamps = ($line) ->
    i = 0
    returnArray = []

    while $line.length > 0 and i < 3
      returnArray.push $line.prev().data("timestamp")
      $line = $line.prev()
      i++

    returnArray

  getSanitizedLineHtml = ($line) ->
    $line = $line.clone()
    $line.find(".checkbox-animated").removeClass('checkbox-animated')
    html = $line.html()
    $line.remove()
    html

  # if the given line has changed, update its counterpart in linesArray and add a sync event to the queue
  syncLine = ($line, offset) ->
    return if linesArray[$line.data("timestamp")] is $line.html()
    timestamp = $line.data("timestamp")
    linesArray[timestamp] = getSanitizedLineHtml($line)
    syncQueue.push ["syncLine",
      timestamp: timestamp
      underneath_timestamps: buildUnderneathTimestamps($line)
      text: linesArray[timestamp]
      offset: offset
    ]

  # remove a line (by timestamp) from the linesArray, and add a 'removeLine' event to the queue
  removeLine = (timestamp) ->
    delete linesArray[timestamp]
    syncQueue.push ["removeLine", {timestamp: timestamp}]

  # remove any stray lines that exist in linesArray but not in our editor
  cleanupSync = ->
    for timestamp, line of linesArray
      if nodeForTimestamp(timestamp).length is 0
        removeLine(timestamp)

  # call syncLine() for each top-level node
  handleContentChange = (offset) ->
    $line = $editor.children(":first")

    while $line.length > 0
      syncLine $line, offset
      $line = $line.next()

    cleanupSync()
    syncUp()

  # push the entire syncQueue to the server, empty the syncQueue.
  syncUp = ->
    socket.emit "syncUp", syncQueue.splice(0), setupParams if syncQueue.length > 0

  handleSelectionChange = ->
    #

  # insert html into the document
  insertHtml = (html) ->
    document.execCommand "inserthtml", false, html

  # adds a checkbox to the given line
  addCheckbox = ($line) ->
    checkbox = "<img class='checkbox checkbox-animated' src='' width='0' height='0' />"

    # if line begins with whitespace, add after that whitespace
    whitespace = Helper.getIndentString($line[0].childNodes[0])
    $line[0].childNodes[0].textContent = $line[0].childNodes[0].textContent.replace(/^\s+/, "")
    $($line[0].childNodes[0]).before(whitespace + checkbox + " ")

  # toggles the selected lines to/from being tasks
  # @todo this gets funky when line breaks are selected
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

  # toggles the selected task lines to be done/not done
  # @todo this probably needs a checkup too
  self.toggleTaskDone = ->
    lines = getSelectedLines()

    $(lines).each ->
      if $(@).find(".checkbox").length > 0
        toggleCheckbox($(@).find(".checkbox"))

    queueContentChange()

  # toggles a checkbox's state from done/not done
  toggleCheckbox = ($checkbox) ->
    $checkbox.toggleClass("checkbox-checked")
    queueContentChange()

  # find any top-level nodes that aren't timestamped, and timestamp them.
  self.timestampUntimestampedNodes = ->
    $nodes = $editor.find("> .node").filter ->
      !$(@).data('timestamp')

    timestamp_nodes($nodes)

  # finds the top-level node for a given node
  getLine = (node) ->
    node = node.parentNode while $(node.parentNode).attr('id') isnt "editor"
    node

  # gets the currently-selected lines
  getSelectedLines = ->
    sel = window.getSelection()
    first = getLine(sel.anchorNode)
    last = getLine(sel.focusNode)
    if Helper.isBefore(last, 0, first, 0)
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

  # uses the contents of $editor to set up the initial linesArray
  setupLinesArray = ->
    $editor.find("[data-timestamp]").each ->
      linesArray[$(@).data('timestamp')] = $(@).html()



  self.focusTitle = ->
    $titleEl.focus()

  self.focusEditor = ->
    $editor.focus()

  self.pasteText = (text) ->
    insertHtml text

  # make sure that we don't have multiple levels of top-level nodes.
  self.flattenNodes = ->

    flattenChildren = (node) ->
      i = 0
      return if !node
      length = node.childNodes.length

      return node if length is 0

      while i < length
        if node.childNodes[i] and node.childNodes[i].nodeType is 1 and node.childNodes[i].classList and node.childNodes[i].classList.contains("node")
          if node.childNodes[i].parentNode.id isnt $editor.attr('id')
            $(node.childNodes[i].parentNode).after node.childNodes[i]

          flattenChildren(node.childNodes[i])
        i++

    flattenChildren($editor[0])

    queueContentChange()

  ################################################
  # Initial Setup
  ################################################

  $editor.attr "contenteditable", "true"
  setupLinesArray()

  socket = io.connect()
  socket.emit "setup", setupParams

  socket.on "syncDown", (messages) ->
    ignore_changes ->
      for message, i in messages
        socketEvents[message[0]](message[1], message[2], i is (messages.length - 1))

  socketEvents =

    lineSynced: (data, username, setCursor = false) ->
      $line = nodeForTimestamp(data.timestamp)

      if $line.length > 0
        # update line
        $line.html data.text

      else
        # create line
        $line = $("<div class='node' data-timestamp='" + data.timestamp + "'>" + data.text + "</div>")

          # @possible ==
        $underneathLine = nodeForUnderneathTimestamps(data.underneath_timestamps)

        if !data.underneath_timestamps? or $underneathLine.length is 0
          $("#editor").prepend $line
        else
          $underneathLine.after $line

      setOtherUsersCursorOnLine($line, data.offset, username) if setCursor

      linesArray[data.timestamp] = data.text

    lineRemoved: (data, username, setCursor = false) ->
      nodeForTimestamp(data.timestamp).remove()
      delete linesArray[data.timestamp]

  return