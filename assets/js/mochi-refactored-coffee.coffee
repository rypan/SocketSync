`String.prototype.replaceCharacter = function (index, string) {
  if (index > 0)
    return this.substring(0, index) + string + this.substring(index + 1, this.length);
  else
    return string + this;
};
`

HostApp =
  noteChanged: ->
  triggerPaste: ->

window.MochiEditor = (noteId, username) ->
  self = this
  noteId = noteId
  username = username || "noname"
  $el = $("#editor")
  $titleEl = $("#title")
  $titleHint = $("#title-hint")
  $noteEl = $("#note")
  $cursor = $("<span id='cursor'><span class='name'></span></span>")
  syncTimeout = undefined
  noteChangeTimeoutId = undefined
  addingRemoteChanges = false
  linesArray = {}

  $noteEl.append($cursor)

  $titleEl.on "focus", ->
    $titleHint.addClass "text-hint-focused"

  $titleEl.on "blur", ->
    $titleHint.removeClass "text-hint-focused"

  $titleEl.on "keydown", (event) ->
    if event.keyCode is 13 or event.keyCode is 40
      focusEditor() # @checkup this should be ok though

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
      syncTimeout = setTimeout(->
        clearTimeout syncTimeout
        self.cursorCharacterOffset = getCaretCharacterOffsetWithin(event.target)
        handleContentChange() unless addingRemoteChanges
        self.cursorCharacterOffset = undefined
      , 500)

  $el.on "paste", (event) ->
    event.preventDefault()
    HostApp.triggerPaste()

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

    # else if event.metaKey
    #   if keyCode is 13 # return
    #     lines = []
    #     outlineChildNodes editorEl, lines, ""
    #     console.log "OUTLINE:\n" + lines.join("\n")
    #     event.preventDefault()
    #     return

    else
      if keyCode is 38 # up
      #   selection = window.getSelection()
      #   line = getLine(selection.anchorNode)
      #   unless line.previousSibling
      #     startTop = line.offsetTop + 1
      #     origRange = selection.getRangeAt(0)
      #     currentRects = origRange.getClientRects()
      #     currentTop = undefined
      #     if currentRects.length
      #       currentTop = currentRects[0].top
      #     else
      #       currentTop = startTop
      #     editor.focusTitle()  if currentTop <= startTop
      else if keyCode is 9 # tab
        event.preventDefault()
        insertHtml "\t"
      # else if keyCode is 13 # return
      #   sel = window.getSelection()
      #   indent = getIndentString(getLine(sel.anchorNode))
      #   if indent
      #     setTimeout (->
      #       insertHtml indent
      #     ), 0
    # handleSelectionChange()

  # $el.on "mouseup", (event) ->
  #   # @checkup change $el
  #   $el = $(event.target)
  #   toggleCheckbox $el  if $el.hasClass("checkbox")
  #   handleSelectionChange()


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

  setEditable = (editable) ->
    if editable
      $el.attr "contenteditable", "true"
    else
      $el.removeAttr "contenteditable"

  # outlineChildNodes = (node, lines, indent) ->
  #   child = node.firstChild
  #   while child
  #     name = (child.tagName or "TXT")
  #     name = name.toLowerCase()  if name is "DIV" or name is "BR" or name is "TXT"
  #     lines.push indent + name
  #     outlineChildNodes child, lines, indent + "    "
  #     child = child.nextSibling


  # @checkup this just calls some shit on HostApp
  #
  # handleNoteChange = function() {
  #     if (noteChangeTimeoutId) return;

  #     noteChangeTimeoutId = setTimeout(function () {
  #         noteChangeTimeoutId = null;
  #         HostApp.noteChanged();
  #     }, 70);
  # }

  nodeListToArray = (nodeList) ->
    returnArray = []
    length = nodeList.length
    i = 0

    while i < length
      returnArray.push nodeList.item(i)
      i++

    returnArray

  setOtherUsersCursorAtLocation = (top, right, username) ->
    $cursor.css
      left: right
      top: top

    .find(".name").text(username)

    $cursor.show()

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
        tempEl = "<span id='getPos'>#{replaceChar}</span>"

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

  syncLine = ($line) ->
    return  if linesArray[$line.data("timestamp")] is $line.html()
    timestamp = $line.data("timestamp")
    linesArray[timestamp] = $line.html()
    socket.emit "note.syncLine",
      timestamp: timestamp
      underneath_timestamp: $line.prev().data("timestamp")
      text: linesArray[timestamp]
      characterOffset: self.cursorCharacterOffset


  removeLine = (timestamp) ->
    delete linesArray[timestamp]

    socket.emit "note.removeLine",
      timestamp: timestamp


  cleanupSync = ->
    for timestamp, line of linesArray
      if lineForTimestamp(timestamp).length is 0
        return removeLine(timestamp)

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


  # handleNoteChange();
  handleSelectionChange = ->


  # handleNoteChange();
  insertHtml = (html) ->
    document.execCommand "inserthtml", false, html


  # getIndentString = function(line) {
  #     var str = line.firstChild;
  #     if (str.nodeType === Node.TEXT_NODE) {
  #         var text = str.textContent;
  #         var match = text.match(/\S/);
  #         if (match) {
  #             return text.substring(0, match.index);
  #         } else {
  #             return text;
  #         }
  #     }

  #     return '';
  # }

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

    handleContentChange()

  toggleCheckbox = ($checkbox) ->
    $checkbox.toggleClass("checkbox-checked")


    # preservingSelection ->
    #   changes = []
    #   lines.forEach (line) ->
    #     lineIndex = indexFromNodeAndOffset(editorEl, line, 0)
    #     afterIndentIndex = lineIndex + getIndentString(line).length
    #     isTask = line.classList.contains("task")
    #     if isTask
    #       checkbox = line.querySelector(".checkbox")
    #       range = document.createRange()
    #       range.setStartBefore checkbox
    #       checkboxIndex = indexFromNodeAndOffset(editorEl, range.startContainer, range.startOffset)
    #       range.setStartAfter checkbox
    #       sel = window.getSelection()
    #       sel.removeAllRanges()
    #       sel.addRange range
    #       sel.modify "extend", "forward", "character"
    #       isSpace = (sel.toString() is " ")
    #       if isSpace
    #         selectRange checkboxIndex, checkboxIndex + 2
    #         changes.push [checkboxIndex, -2]
    #       else
    #         selectRange checkboxIndex, checkboxIndex + 1
    #         changes.push [checkboxIndex, -1]
    #       document.execCommand "delete", false, null
    #     else
    #       selectRange afterIndentIndex, afterIndentIndex
    #       insertCheckbox " "
    #       changes.push [afterIndentIndex, 2]

    #   changes

  # function toggleTaskDone() {
  #     var lines = getSelectedLines();
  #     preservingSelection(function () {
  #         var changes = [];
  #         lines.forEach(function (line) {
  #             var lineIndex = indexFromNodeAndOffset(editorEl, line, 0);
  #             var afterIndentIndex = lineIndex + getIndentString(line).length;
  #             var isTask = line.classList.contains('task');
  #             if (isTask) {
  #                 var checkbox = line.querySelector('.checkbox');
  #                 toggleCheckbox(checkbox);
  #             }
  #         });
  #         return changes;
  #     });
  # }

  # function cycleTaskState() {
  #     var lines = getSelectedLines();
  #     preservingSelection(function () {
  #         var changes = [];
  #         lines.forEach(function (line) {
  #             var lineIndex = indexFromNodeAndOffset(editorEl, line, 0);
  #             var afterIndentIndex = lineIndex + getIndentString(line).length;
  #             var isTask = line.classList.contains('task');
  #             if (isTask) {
  #                 var checkbox = line.querySelector('.checkbox');
  #                 var checked = checkbox.classList.contains('checkbox-checked');
  #                 if (checked) {
  #                     var range = document.createRange();
  #                     range.setStartBefore(checkbox);

  #                     var checkboxIndex = indexFromNodeAndOffset(editorEl, range.startContainer, range.startOffset);

  #                     range.setStartAfter(checkbox);
  #                     var sel = window.getSelection();
  #                     sel.removeAllRanges();
  #                     sel.addRange(range);
  #                     sel.modify('extend', 'forward', 'character');
  #                     var isSpace = (sel.toString() === ' ');

  #                     if (isSpace) {
  #                         selectRange(checkboxIndex, checkboxIndex + 2);
  #                         changes.push([checkboxIndex, -2]);
  #                     } else {
  #                         selectRange(checkboxIndex, checkboxIndex + 1);
  #                         changes.push([checkboxIndex, -1]);
  #                     }
  #                     document.execCommand('delete', false, null);
  #                 } else {
  #                     checkbox.classList.add('checkbox-checked');
  #                 }
  #             } else {
  #                 selectRange(afterIndentIndex, afterIndentIndex);
  #                 insertCheckbox(' ');
  #                 changes.push([afterIndentIndex, 2]);
  #             }
  #         });
  #         return changes;
  #     });
  # }
  $(document).on "DOMNodeRemoved", (e) ->
    return if addingRemoteChanges
    return if e.srcElement.nodeName isnt "DIV"
    $line = $(e.srcElement)
    removeLine $line.data("timestamp") if $line.hasClass("node")

  $(document).on "DOMNodeInserted", (e) ->
    return if addingRemoteChanges # @possible use '?'
    return if e.srcElement.nodeName isnt "DIV"
    $(e.srcElement).removeAttr "data-timestamp"
    $(e.srcElement).data "timestamp", Date.now()


  # adjustIndex = function(anchorIndex, index, delta) {
  #     if (delta > 0) {
  #         if (index <= anchorIndex) {
  #             anchorIndex += delta;
  #         }
  #     } else if (delta < 0) {
  #         if (index < anchorIndex) {
  #             var diff;
  #             var end = index - delta;
  #             if (end > anchorIndex) {
  #                 diff = index - anchorIndex;
  #             } else {
  #                 diff = delta;
  #             }
  #             anchorIndex += diff;
  #         }
  #     }

  #     return anchorIndex;
  # }

  # function preservingSelection(callback) {
  #     var sel = window.getSelection();
  #     var anchorNode = sel.anchorNode;
  #     var anchorOffset = sel.anchorOffset;
  #     var focusNode = sel.focusNode;
  #     var focusOffset = sel.focusOffset;
  #     var anchorIndex = indexFromNodeAndOffset(editorEl, anchorNode, anchorOffset);
  #     var focusIndex = indexFromNodeAndOffset(editorEl, focusNode, focusOffset);

  #     var changes = callback();
  #     if (changes) {
  #         changes.forEach(function (change) {
  #             var index = change[0];
  #             var delta = change[1];
  #             anchorIndex = adjustIndex(anchorIndex, index, delta);
  #             focusIndex = adjustIndex(focusIndex, index, delta);
  #         });
  #     }

  #     selectRange(anchorIndex, focusIndex);
  # }

  # isMaterialElement = function(node) {
  #     return node.nodeType === Node.TEXT_NODE || node.tagName === 'IMG' || node.tagName === 'BR';
  # }

  # function getMaterialElementNode(node) {
  #     if (node.nodeType === Node.TEXT_NODE) {
  #         return node;
  #     }

  #     return node.parentNode;
  # }

  # function getMaterialElementLength(node) {
  #     if (node.nodeType === Node.TEXT_NODE) {
  #         return node.length;
  #     } else if (node.tagName === 'IMG') {
  #         return 1;
  #     }

  #     return 0;
  # }

  # function findNodeAndOffsetRelTo(referenceNode, index) {
  #     var it = document.createNodeIterator(referenceNode, NodeFilter.SHOW_ALL, null);

  #     var node = it.nextNode();
  #     // Skip to first child in editor.
  #     node = it.nextNode();

  #     var seenMaterial = false;
  #     var offset = 0;
  #     while (node) {
  #         if (!seenMaterial && isMaterialElement(node)) {
  #             seenMaterial = true;
  #         }

  #         var startingOffset = offset;
  #         if (seenMaterial) {
  #             offset += getOffsetContribution(node);
  #         }

  #         if (isMaterialElement(node) && offset >= index) {
  #             var targetNode;
  #             var targetNodeOffset;
  #             if (node.nodeType === Node.TEXT_NODE) {
  #                 targetNode = node;
  #                 targetNodeOffset = index - startingOffset;
  #             } else {
  #                 targetNode = node.parentNode;
  #                 targetNodeOffset = 0;

  #                 while (offset > index) {
  #                     offset -= getMaterialElementLength(node);
  #                     node = node.previousSibling;
  #                 }

  #                 if (node) {
  #                     var child = targetNode.firstChild;
  #                     while (child) {
  #                         targetNodeOffset++;
  #                         if (child === node) {
  #                             break;
  #                         }
  #                         child = child.nextSibling;
  #                     }
  #                 }
  #             }

  #             return [targetNode, targetNodeOffset];
  #         }

  #         node = it.nextNode();
  #     }

  #     return [null, -1];
  # }

  # function findNodeAndOffset(index) {
  #     return findNodeAndOffsetRelTo(editorEl, index);
  # }

  # function getOffsetContribution(node) {
  #     if (node.tagName === 'DIV') {
  #         // Crossing into a div adds a newline character.
  #         return 1;
  #     } else if (node.tagName === 'IMG') {
  #         return 1;
  #     } else if (node.nodeType === Node.TEXT_NODE) {
  #         return node.length;
  #     }

  #     return 0;
  # }

  # function indexFromNodeAndOffset(referenceNode, targetNode, targetNodeOffset) {
  #     var it = document.createNodeIterator(
  #         referenceNode, NodeFilter.SHOW_ALL, null
  #     );
  #     var node = it.nextNode();
  #     var seenMaterial = false;
  #     var offset = 0;
  #     while (node) {
  #         if (!seenMaterial && isMaterialElement(node)) {
  #             seenMaterial = true;
  #         }

  #         var startingOffset = offset;

  #         // Skip counting divs until one material element has been seen.
  #         if (seenMaterial) {
  #             offset += getOffsetContribution(node);
  #         }

  #         if (node === targetNode) {
  #             if (targetNode.nodeType === Node.TEXT_NODE) {
  #                 offset = startingOffset + targetNodeOffset;
  #             } else if (targetNode.nodeType === Node.ELEMENT_NODE) {
  #                 for (var i = 0; i < targetNodeOffset; i++) {
  #                     var childNode = node.childNodes[i];
  #                     offset += getMaterialElementLength(childNode);
  #                 }
  #             }

  #             return offset;
  #         }

  #         node = it.nextNode();
  #     }

  #     return null;
  # }

  # function selectRange(anchorIndex, focusIndex) {
  #     var anchor = findNodeAndOffset(anchorIndex);
  #     var focus = findNodeAndOffset(focusIndex);

  #     var range = document.createRange();
  #     range.setStart(anchor[0], anchor[1]);
  #     range.setEnd(anchor[0], anchor[1]);

  #     var sel = window.getSelection();
  #     sel.removeAllRanges();
  #     sel.addRange(range);

  #     // Preserve forward/backward direction.
  #     sel.extend(focus[0], focus[1]);
  # }

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

  # function flattenNode(node) {
  #     var it = document.createNodeIterator(
  #         node, NodeFilter.SHOW_ALL, null
  #     );
  #     it.nextNode();
  #     var nodes = [];
  #     var inlineNodes = [];

  #     function insertInlines() {
  #         if (!inlineNodes.length) {
  #             return;
  #         }

  #         var div = document.createElement('div');
  #         inlineNodes.forEach(function (value) {
  #             div.appendChild(value);
  #         });
  #         inlineNodes = [];
  #         nodes.push(div);
  #     }

  #     var child = it.nextNode();
  #     while (child) {
  #         if (child.tagName === 'DIV') {
  #             insertInlines();
  #             nodes.push(child);
  #         } else {
  #             inlineNodes.push(child);
  #         }

  #         child = it.nextNode();
  #     }

  #     insertInlines();

  #     nodes.reverse();
  #     nodes.forEach(function (value) {
  #         node.parentNode.insertBefore(value, node.nextSibling);
  #     });
  #     node.parentNode.removeChild(node);
  # }

  # function getRange() {
  #     var sel = window.getSelection();
  #     return sel.getRangeAt(0);
  # }

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


  # self.pasteText = function (text) {
  #     var origScrollTop = document.body.scrollTop;

  #     if (text.indexOf('\n') < 0) {
  #         insertHtml(text);
  #     } else {
  #         // Delete selection, if a non-empty selection exists.
  #         var selRange = getSelRange();
  #         if (selRange[0] !== selRange[1]) {
  #             document.execCommand('delete', false, null);
  #         }

  #         // Create container for making edits to nodes.
  #         var container = document.createElement('div');
  #         container.innerHTML = editorEl.innerHTML;

  #         var pivotIndex = selRange[0];
  #         var pivot = findNodeAndOffsetRelTo(container, pivotIndex);
  #         var pivotNode = pivot[0];
  #         var pivotOffset = pivot[1];

  #         var lineDiv = pivotNode;
  #         while (lineDiv !== container && lineDiv.parentNode !== container) {
  #             lineDiv = lineDiv.parentNode;
  #         }

  #         var range = document.createRange();
  #         range.selectNodeContents(lineDiv);
  #         range.setEnd(pivotNode, pivotOffset);
  #         var startContent = range.cloneContents();

  #         range.selectNodeContents(lineDiv);
  #         range.setStart(pivotNode, pivotOffset);
  #         var endContent = range.cloneContents();

  #         // The line that new lines should be inserted before.
  #         var anchorLine = lineDiv.nextSibling;
  #         container.removeChild(lineDiv);

  #         var pastedLength = text.length;

  #         var element = document.createElement('div');
  #         element.appendChild(startContent);
  #         var newlineIndex = text.indexOf('\n');
  #         var textContent = text.substring(0, newlineIndex);
  #         if (textContent) {
  #             element.appendChild(document.createTextNode(textContent));
  #         }
  #         text = text.substring(newlineIndex + 1);
  #         element.normalize();
  #         if (!element.firstChild) {
  #             element.appendChild(document.createElement('br'));
  #         }
  #         container.insertBefore(element, anchorLine);

  #         var buffer = [];
  #         for (var i = 0; i < text.length; i++) {
  #             var c = text[i];
  #             if (c === '\n') {
  #                 var element = document.createElement('div');
  #                 var line = buffer.join('');
  #                 buffer = [];
  #                 if (line) {
  #                     element.appendChild(document.createTextNode(line));
  #                 } else {
  #                     element.appendChild(document.createElement('br'));
  #                 }
  #                 container.insertBefore(element, anchorLine);
  #             } else {
  #                 buffer.push(c);
  #             }
  #         }

  #         var element = document.createElement('div');
  #         var line = buffer.join('');
  #         if (line) {
  #             element.appendChild(document.createTextNode(line));
  #         }
  #         element.appendChild(endContent);
  #         element.normalize();
  #         if (!element.firstChild) {
  #             element.appendChild(document.createElement('br'));
  #         }
  #         container.insertBefore(element, anchorLine);

  #         document.execCommand('selectall', false, null);

  #         // Delete selection.
  #         document.execCommand('delete', false, null);

  #         // Delete starting div.
  #         document.execCommand('delete', false, null);

  #         insertHtml(container.innerHTML);
  #         document.body.scrollTop = origScrollTop;

  #         var finalIndex = pivotIndex + pastedLength;
  #         selectRange(finalIndex, finalIndex);
  #     }

  #     var currentLine = getLine(window.getSelection().anchorNode);
  #     var scrollTop = origScrollTop;
  #     var scrollBottom = scrollTop + window.innerHeight;
  #     var lineTop = currentLine.offsetTop;
  #     var lineBottom = lineTop + currentLine.offsetHeight;
  #     if (lineTop < scrollTop) {
  #         document.body.scrollTop = lineTop;
  #     } else if (lineBottom > scrollBottom) {
  #         document.body.scrollTop = lineBottom - window.innerHeight;
  #     }
  # },

  # toggleTask: toggleTask,
  # toggleTaskDone: toggleTaskDone,
  # getNoteData: function () {
  #     return {
  #         title: titleEl.value,
  #         content: editorEl.innerHTML,
  #         tasks: getTasks(),
  #         selection: getSelRange()
  #     };
  # }
  setEditable true

  setupLinesArray()

  socket = io.connect()

  socket.emit "setup",
    noteId: noteId
    username: username

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
      if !data.underneath_timestamp? or lineForTimestamp(data.underneath_timestamp).length is 0
        $("#editor").prepend $newLine
      else
        lineForTimestamp(data.underneath_timestamp).after $newLine

      setOtherUsersCursorOnLine($newLine, data.characterOffset, username)

    linesArray[data.timestamp] = data.text
    addingRemoteChanges = false

  socket.on "note.lineRemoved", (data, username) ->
    addingRemoteChanges = true
    lineForTimestamp(data.timestamp).remove()
    delete linesArray[data.timestamp]

    addingRemoteChanges = false

  self