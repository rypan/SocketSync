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
    if node and node.nodeType is Node.TEXT_NODE
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

  $editor = $("#editor")
  $titleEl = $("#title")
  $titleHint = $("#title-hint")
  $noteEl = $("#note")

  @doc = undefined
  @cachedValue = undefined

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
    handleTitleChange()

  # listen for modifications to the dom, and queue a timeout that will handle the modifications.
  $editor.on "DOMSubtreeModified", =>
    @queueContentChange() unless stopListeningForChanges

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
      if line.childNodes[0] and line.childNodes[0].textContent.match(/^\s*\+$/)
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
    else if keyCode is 38
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

    ################################################
    # Formatting Hotkeys
    # @todo remove these if running in native container?
    ################################################

    else if (event.ctrlKey || event.metaKey) and keyCode is 66 # ctrl+b
      event.preventDefault()
      document.execCommand "bold"

    else if (event.ctrlKey || event.metaKey) and keyCode is 73 # ctrl+i
      event.preventDefault()
      document.execCommand "italic"

    else if (event.ctrlKey || event.metaKey) and keyCode is 85 # ctrl+u
      event.preventDefault()
      document.execCommand "underline"

    else if (event.ctrlKey || event.metaKey) and keyCode is 83 # ctrl+s
      event.preventDefault()
      document.execCommand "strikeThrough"


  # toggle checkboxes when clicked
  $editor.on "click", ".checkbox", (event) ->
    toggleCheckbox $(@)

  # Disable drag.
  # $editor.on "dragstart", (event) ->
  #   event.preventDefault()

  # Disable external drop.
  # $editor.on "dragover", (event) ->
  #   event.preventDefault()

  applyChange = (oldval, newval) =>
    return if oldval == newval
    commonStart = 0
    commonStart++ while oldval.charAt(commonStart) == newval.charAt(commonStart)

    commonEnd = 0
    commonEnd++ while oldval.charAt(oldval.length - 1 - commonEnd) == newval.charAt(newval.length - 1 - commonEnd) and
      commonEnd + commonStart < oldval.length and commonEnd + commonStart < newval.length

    @doc.del commonStart, oldval.length - commonStart - commonEnd unless oldval.length == commonStart + commonEnd
    @doc.insert commonStart, newval[commonStart ... newval.length - commonEnd] unless newval.length == commonStart + commonEnd

  # executes the provided callback while ignoring changes to the dom.
  ignoreChanges = (cb) ->
    originalVal = stopListeningForChanges
    stopListeningForChanges = true
    cb()
    stopListeningForChanges = originalVal


  # set a timeout for handleContentChange(), to ensure it gets called no more than once every X ms.
  this.queueContentChange = ->
    return if !@doc
    html = sanitizeHtml($editor.html())
    if html != @cachedValue
      # IE constantly replaces unix newlines with \r\n. ShareJS docs
      # should only have unix newlines.
      @cachedValue = html
      applyChange @doc.getText(), html

  updateTitleHint = ->
    if $titleEl.val()
      $titleHint.hide()
    else
      $titleHint.show()

  handleTitleChange = ->
    # @todo save the title on the server
    updateTitleHint()

  # insert html into the document
  insertHtml = (html) ->
    document.execCommand "inserthtml", false, html

  # adds a checkbox to the given line
  addCheckbox = ($line) ->
    checkbox = "<img class='checkbox checkbox-animated' src='' width='0' height='0' />"

    ignoreChanges ->
      # if line begins with whitespace, add after that whitespace
      whitespace = Helper.getIndentString($line[0].childNodes[0])
      $line[0].childNodes[0].textContent = $line[0].childNodes[0].textContent.replace(/^\s+/, "")
      $($line[0].childNodes[0]).before(whitespace + checkbox + " ")

    self.queueContentChange()

  # finds the top-level node for a given node
  getLine = (node) ->
    return if !node
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
  this.toggleTaskDone = ->
    lines = getSelectedLines()

    $(lines).each ->
      if $(@).find(".checkbox").length > 0
        toggleCheckbox($(@).find(".checkbox"))

    self.queueContentChange()

  # toggles a checkbox's state from done/not done
  toggleCheckbox = ($checkbox) ->
    $checkbox.toggleClass("checkbox-checked")
    self.queueContentChange()

  sanitizeHtml = (html) ->
    html = html.replace """<img class="checkbox checkbox-animated" src="" width="0" height="0">""", """<img class="checkbox" src="" width="0" height="0">"""
    html

  this.focusTitle = ->
    $titleEl.focus()

  this.focusEditor = ->
    $editor.focus()

  this.pasteText = (text) ->
    insertHtml text


  ################################################
  # Initial Setup
  ################################################

  $editor.attr "contenteditable", "true"

  sharejs.open noteId, 'text', '/channel', (error, doc) =>
    $editor.html doc.getText()
    @cachedValue = $editor.html()
    @doc = doc

    doc.on 'remoteop', (ops) =>

      tempValue = $editor.html()
      beforeTotalChars = rangy.innerText($editor[0]).length

      savedSelection = rangy.getSelection().saveCharacterRanges($editor[0])

      for op in ops
        if op.i? # insert
          tempValue = tempValue[...op.p] + op.i + tempValue[op.p..]
        else if op.d? # delete
          tempValue = tempValue[...op.p] + tempValue[op.p + op.d.length..]

        opPosition = op.p

      ignoreChanges =>
        $editor.html tempValue

      afterTotalChars = rangy.innerText($editor[0]).length

      if savedSelection[0].range?.start > opPosition
        # find the entire length of selectable chars from rangy and add the difference
        savedSelection[0].range.start += afterTotalChars - beforeTotalChars
        savedSelection[0].range.end += afterTotalChars - beforeTotalChars

      rangy.getSelection().restoreCharacterRanges($editor[0], savedSelection)

      @cachedValue = $editor.html()

  return