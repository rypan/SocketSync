socket = io.connect()
socket.emit('setNote', SocketSync.note_id)

// socket.on('note.divRemoved', function(data){
//   $("#editor div[data-timestamp="+data.div_id+"]").remove();
// });

// socket.on('note.divAdded', function(data){
//   if (!data.underneath_id) {
//     // # insert at top
//     $("#editor").prepend(data.div);
//   } else {
//     // # insert data.div underneath the correct div
//     $("#editor div[data-timestamp="+data.underneath_id+"]").after(data.div);
//   }
// });

var addingRemoteChanges = false;
var linesArray = {};

var lineForTimestamp = function (timestamp) {
    return $("#editor div").filter(function(){
        return $(this).data('timestamp') == timestamp;
    });
}

socket.on('note.lineSynced', function(data){
    addingRemoteChanges = true;

    var $existingLine = lineForTimestamp(data.timestamp);

    if ($existingLine.length > 0) {
        // update line
        $existingLine.html(data.text)

    } else {
        // create line
        var newLine = "<div class='node' data-timestamp='"+data.timestamp+"'>"+data.text+"</div>";

        if (data.underneath_timestamp == "" || lineForTimestamp(data.underneath_timestamp).length == 0) {
          $("#editor").prepend(newLine);
        } else {
          lineForTimestamp(data.underneath_timestamp).after(newLine)
        }
    }

    linesArray[data.timestamp] = data.text;

    addingRemoteChanges = false;
});

socket.on('note.lineRemoved', function(data){
    addingRemoteChanges = true;
    lineForTimestamp(data.timestamp).remove()
    delete linesArray[data.timestamp];
    addingRemoteChanges = false;
});


var HostApp = {
    noteChanged: function(){},
    triggerPaste: function(){}
};

var editor = (function () {
    var syncTimeout;
    var noteEl;
    var titleEl;
    var titleHint;
    var editorEl;
    var noteChangeTimeoutId;

    function getSelRange() {
        var selection = window.getSelection();
        var start = indexFromNodeAndOffset(
            editorEl, selection.anchorNode, selection.anchorOffset
        );
        var end = indexFromNodeAndOffset(
            editorEl, selection.focusNode, selection.focusOffset
        );
        return [start, end];
    }

    function setEditable(editable) {
        if (editable) {
            editorEl.setAttribute('contenteditable', 'true');
        } else {
            editorEl.removeAttribute('contenteditable');
        }
    }

    function outlineChildNodes(node, lines, indent) {
        var child = node.firstChild;
        while (child) {
            var name = (child.tagName || 'TXT');
            if (name === 'DIV' || name === 'BR' || name === 'TXT') {
                name = name.toLowerCase();
            }
            lines.push(indent + name);
            outlineChildNodes(child, lines, indent + '    ');
            child = child.nextSibling;
        }
    }

    function handleNoteChange() {
        if (noteChangeTimeoutId) {
            return;
        }

        noteChangeTimeoutId = setTimeout(function () {
            noteChangeTimeoutId = null;
            HostApp.noteChanged();
        }, 70);
    }

    function updateTitleHint() {
        if (titleEl.value) {
            titleHint.style.display = 'none';
        } else {
            titleHint.style.display = '';
        }
    }

    function handleTitleChange() {
        handleNoteChange();
        updateTitleHint();
    }

    function syncLine($line) {
        var timestamp = $line.data('timestamp');
        linesArray[timestamp] = $line.html();
        socket.emit('note.syncLine', {
            timestamp: timestamp,
            underneath_timestamp: $line.prev().data('timestamp'),
            text: linesArray[timestamp]
        });
    }

    function removeLine(timestamp) {
        delete linesArray[timestamp];
        socket.emit('note.removeLine', {
            timestamp: timestamp
        });
    }

    function handleSync($line) {
        if (linesArray[$line.data('timestamp')] !== $line.html()) return syncLine($line);
    }

    function cleanupSync() {
        for (i in linesArray) {
            var line = lineForTimestamp(i);
            if (line.length === 0) return removeLine(i);
            // if (line.html() === "") {
            //     // line.remove();
            //     return removeLine(i);
            // }
        }
    }

    function handleContentChange() {
        var line = editorEl.firstChild;
        while (line) {
            if (line.querySelector('.checkbox')) {
                line.classList.add('task');
            } else {
                line.classList.remove('task');
            }

            handleSync($(line))

            line = line.nextSibling;
        }

        cleanupSync();

        handleNoteChange();
    }

    window.handleContentChange = handleContentChange;

    function handleSelectionChange() {
        handleNoteChange();
    }

    function insertHtml(html) {
        document.execCommand('inserthtml', false, html);
    }

    function getIndentString(line) {
        var str = line.firstChild;
        if (str.nodeType === Node.TEXT_NODE) {
            var text = str.textContent;
            var match = text.match(/\S/);
            if (match) {
                return text.substring(0, match.index);
            } else {
                return text;
            }
        }

        return '';
    }

    function insertCheckbox(suffix, animated) {
        suffix = suffix || '';
        if (animated) {
            animated = ' checkbox-animated';
        } else {
            animated = '';
        }
        insertHtml('<img class="checkbox' + animated + '" src="" width="0" height="0">' + suffix);
    }

    function toggleCheckbox(checkbox) {
        checkbox.classList.toggle('checkbox-checked');

        // Toggling class does not trigger DOMSubtreeModified event, so
        // we have to call handleContentChange() manually.
        handleContentChange();
    }

    function toggleTask() {
        var lines = getSelectedLines();
        preservingSelection(function () {
            var changes = [];
            lines.forEach(function (line) {
                var lineIndex = indexFromNodeAndOffset(editorEl, line, 0);
                var afterIndentIndex = lineIndex + getIndentString(line).length;
                var isTask = line.classList.contains('task');
                if (isTask) {
                    var checkbox = line.querySelector('.checkbox');
                    var range = document.createRange();
                    range.setStartBefore(checkbox);

                    var checkboxIndex = indexFromNodeAndOffset(editorEl, range.startContainer, range.startOffset);

                    range.setStartAfter(checkbox);
                    var sel = window.getSelection();
                    sel.removeAllRanges();
                    sel.addRange(range);
                    sel.modify('extend', 'forward', 'character');
                    var isSpace = (sel.toString() === ' ');

                    if (isSpace) {
                        selectRange(checkboxIndex, checkboxIndex + 2);
                        changes.push([checkboxIndex, -2]);
                    } else {
                        selectRange(checkboxIndex, checkboxIndex + 1);
                        changes.push([checkboxIndex, -1]);
                    }
                    document.execCommand('delete', false, null);
                } else {
                    selectRange(afterIndentIndex, afterIndentIndex);
                    insertCheckbox(' ');
                    changes.push([afterIndentIndex, 2]);
                }
            });
            return changes;
        });
    }

    function toggleTaskDone() {
        var lines = getSelectedLines();
        preservingSelection(function () {
            var changes = [];
            lines.forEach(function (line) {
                var lineIndex = indexFromNodeAndOffset(editorEl, line, 0);
                var afterIndentIndex = lineIndex + getIndentString(line).length;
                var isTask = line.classList.contains('task');
                if (isTask) {
                    var checkbox = line.querySelector('.checkbox');
                    toggleCheckbox(checkbox);
                }
            });
            return changes;
        });
    }

    // function cycleTaskState() {
    //     var lines = getSelectedLines();
    //     preservingSelection(function () {
    //         var changes = [];
    //         lines.forEach(function (line) {
    //             var lineIndex = indexFromNodeAndOffset(editorEl, line, 0);
    //             var afterIndentIndex = lineIndex + getIndentString(line).length;
    //             var isTask = line.classList.contains('task');
    //             if (isTask) {
    //                 var checkbox = line.querySelector('.checkbox');
    //                 var checked = checkbox.classList.contains('checkbox-checked');
    //                 if (checked) {
    //                     var range = document.createRange();
    //                     range.setStartBefore(checkbox);

    //                     var checkboxIndex = indexFromNodeAndOffset(editorEl, range.startContainer, range.startOffset);

    //                     range.setStartAfter(checkbox);
    //                     var sel = window.getSelection();
    //                     sel.removeAllRanges();
    //                     sel.addRange(range);
    //                     sel.modify('extend', 'forward', 'character');
    //                     var isSpace = (sel.toString() === ' ');

    //                     if (isSpace) {
    //                         selectRange(checkboxIndex, checkboxIndex + 2);
    //                         changes.push([checkboxIndex, -2]);
    //                     } else {
    //                         selectRange(checkboxIndex, checkboxIndex + 1);
    //                         changes.push([checkboxIndex, -1]);
    //                     }
    //                     document.execCommand('delete', false, null);
    //                 } else {
    //                     checkbox.classList.add('checkbox-checked');
    //                 }
    //             } else {
    //                 selectRange(afterIndentIndex, afterIndentIndex);
    //                 insertCheckbox(' ');
    //                 changes.push([afterIndentIndex, 2]);
    //             }
    //         });
    //         return changes;
    //     });
    // }

    $(document).on("focus.boundRemoveNode", "#editor", function(){
        $(document).off(".boundRemoveNode")

        $(document).on("DOMNodeRemoved", function(e){
            if (addingRemoteChanges) return;
            if (e.srcElement.nodeName !== "DIV") return;
            $line = $(e.srcElement);
            if ($line.hasClass('node')) return removeLine($line.data('timestamp'));
        });

        $(document).on("DOMNodeInserted", function(e){
            if (addingRemoteChanges) return;
            if (e.srcElement.nodeName !== "DIV") return;
            $(e.srcElement).removeAttr('data-timestamp');
            $(e.srcElement).data('timestamp', Date.now());
        });
    });


    window.addEventListener('load', function () {
        noteEl = document.getElementById('note');
        titleEl = document.getElementById('title');
        editorEl = document.getElementById('editor');
        titleHint = document.getElementById('title-hint');

        setEditable(true);

        titleEl.addEventListener('focus', function () {
            titleHint.classList.add('text-hint-focused');
        }, false);
        titleEl.addEventListener('blur', function () {
            titleHint.classList.remove('text-hint-focused');
        }, false);
        titleEl.addEventListener('keydown', function (event) {
            if (event.keyCode === 13 /* return */ || event.keyCode === 40 /* down */) {
                // return
                editor.focusEditor();

                // Prevent newline from being inserted into editor.
                event.preventDefault();
            }

            setTimeout(handleTitleChange, 0);
        }, false);
        titleEl.addEventListener('cut', function () {
            setTimeout(handleTitleChange, 0);
        }, false);
        titleEl.addEventListener('paste', function () {
            setTimeout(handleTitleChange, 0);
        }, false);

        editorEl.addEventListener('DOMSubtreeModified', function (event) {
            syncTimeout = setTimeout(function(){
                console.log('sync')
                clearTimeout(syncTimeout);
                if (!addingRemoteChanges) handleContentChange();
            }, 500);

        }, false);
        editorEl.addEventListener('paste', function (event) {
            event.preventDefault();
            HostApp.triggerPaste();
        }, false);
        editorEl.addEventListener('webkitAnimationEnd', function (event) {
            event.target.classList.remove('checkbox-animated');
        }, false);

        editorEl.addEventListener('keydown', function () {
            var keyCode = event.keyCode;

            if (keyCode === 32) { // space
                var sel = window.getSelection();
                var line = getLine(sel.anchorNode);
                var firstNode = line.firstChild;
                if (firstNode.nodeType === Node.TEXT_NODE) {
                    if (sel.anchorNode === firstNode) {
                        var match = firstNode.textContent.match(/^\s*\+$/);
                        if (match) {
                            sel.modify('extend', 'backward', 'character');

                            // Preserve height to avoid page jump when inserting
                            // checkbox at the end of a long, scrolled note.
                            line.style.height = line.offsetHeight + 'px';
                            insertCheckbox('', true);

                            // Remove fixed height.
                            line.setAttribute('style', '');
                        }
                    }
                }
            } else if (keyCode === 8) { // delete
                // Prevent deletion of last div.
                if (editorEl.childNodes.length === 1 &&
                    editorEl.firstChild.childNodes.length === 1 &&
                    editorEl.firstChild.firstChild.tagName === 'BR') {
                    event.preventDefault();
                }
            } else if (event.metaKey) {
                if (keyCode === 13) { // return
                    var lines = [];
                    outlineChildNodes(editorEl, lines, '');
                    console.log('OUTLINE:\n' + lines.join('\n'));

                    event.preventDefault();
                    return;
                }
            } else {
                if (keyCode === 38) { // up
                    var selection = window.getSelection();
                    var line = getLine(selection.anchorNode);
                    if (!line.previousSibling) {
                        var startTop = line.offsetTop + 1;

                        var origRange = selection.getRangeAt(0);
                        var currentRects = origRange.getClientRects();
                        var currentTop;
                        if (currentRects.length) {
                            currentTop = currentRects[0].top;
                        } else {
                            currentTop = startTop;
                        }

                        if (currentTop <= startTop) {
                            editor.focusTitle();
                        }
                    }
                } else if (keyCode === 9) { // tab
                    event.preventDefault();
                    insertHtml('\t');
                } else if (keyCode === 13) { // return
                    var sel = window.getSelection();
                    var indent = getIndentString(getLine(sel.anchorNode));
                    if (indent) {
                        setTimeout(function () {
                            insertHtml(indent);
                        }, 0);
                    }
                }
            }

            handleSelectionChange();
        }, false);
        editorEl.addEventListener('mouseup', function () {
            var el = event.target;
            if (el.classList.contains('checkbox')) {
                toggleCheckbox(el);
            }

            handleSelectionChange();
        }, false);

        // Disable drag.
        editorEl.addEventListener('dragstart', function (event) {
            event.preventDefault();
        }, false);

        // Disable external drop.
        editorEl.addEventListener('dragover', function (event) {
            event.preventDefault();
        }, false);
    }, false);

    function adjustIndex(anchorIndex, index, delta) {
        if (delta > 0) {
            if (index <= anchorIndex) {
                anchorIndex += delta;
            }
        } else if (delta < 0) {
            if (index < anchorIndex) {
                var diff;
                var end = index - delta;
                if (end > anchorIndex) {
                    diff = index - anchorIndex;
                } else {
                    diff = delta;
                }
                anchorIndex += diff;
            }
        }

        return anchorIndex;
    }

    function preservingSelection(callback) {
        var sel = window.getSelection();
        var anchorNode = sel.anchorNode;
        var anchorOffset = sel.anchorOffset;
        var focusNode = sel.focusNode;
        var focusOffset = sel.focusOffset;
        var anchorIndex = indexFromNodeAndOffset(editorEl, anchorNode, anchorOffset);
        var focusIndex = indexFromNodeAndOffset(editorEl, focusNode, focusOffset);

        var changes = callback();
        if (changes) {
            changes.forEach(function (change) {
                var index = change[0];
                var delta = change[1];
                anchorIndex = adjustIndex(anchorIndex, index, delta);
                focusIndex = adjustIndex(focusIndex, index, delta);
            });
        }

        selectRange(anchorIndex, focusIndex);
    }

    function isMaterialElement(node) {
        return node.nodeType === Node.TEXT_NODE || node.tagName === 'IMG' || node.tagName === 'BR';
    }

    function getMaterialElementNode(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            return node;
        }

        return node.parentNode;
    }

    function getMaterialElementLength(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            return node.length;
        } else if (node.tagName === 'IMG') {
            return 1;
        }

        return 0;
    }

    function findNodeAndOffsetRelTo(referenceNode, index) {
        var it = document.createNodeIterator(referenceNode, NodeFilter.SHOW_ALL, null);

        var node = it.nextNode();
        // Skip to first child in editor.
        node = it.nextNode();

        var seenMaterial = false;
        var offset = 0;
        while (node) {
            if (!seenMaterial && isMaterialElement(node)) {
                seenMaterial = true;
            }

            var startingOffset = offset;
            if (seenMaterial) {
                offset += getOffsetContribution(node);
            }

            if (isMaterialElement(node) && offset >= index) {
                var targetNode;
                var targetNodeOffset;
                if (node.nodeType === Node.TEXT_NODE) {
                    targetNode = node;
                    targetNodeOffset = index - startingOffset;
                } else {
                    targetNode = node.parentNode;
                    targetNodeOffset = 0;

                    while (offset > index) {
                        offset -= getMaterialElementLength(node);
                        node = node.previousSibling;
                    }

                    if (node) {
                        var child = targetNode.firstChild;
                        while (child) {
                            targetNodeOffset++;
                            if (child === node) {
                                break;
                            }
                            child = child.nextSibling;
                        }
                    }
                }

                return [targetNode, targetNodeOffset];
            }

            node = it.nextNode();
        }

        return [null, -1];
    }

    function findNodeAndOffset(index) {
        return findNodeAndOffsetRelTo(editorEl, index);
    }

    function getOffsetContribution(node) {
        if (node.tagName === 'DIV') {
            // Crossing into a div adds a newline character.
            return 1;
        } else if (node.tagName === 'IMG') {
            return 1;
        } else if (node.nodeType === Node.TEXT_NODE) {
            return node.length;
        }

        return 0;
    }

    function indexFromNodeAndOffset(referenceNode, targetNode, targetNodeOffset) {
        var it = document.createNodeIterator(
            referenceNode, NodeFilter.SHOW_ALL, null
        );
        var node = it.nextNode();
        var seenMaterial = false;
        var offset = 0;
        while (node) {
            if (!seenMaterial && isMaterialElement(node)) {
                seenMaterial = true;
            }

            var startingOffset = offset;

            // Skip counting divs until one material element has been seen.
            if (seenMaterial) {
                offset += getOffsetContribution(node);
            }

            if (node === targetNode) {
                if (targetNode.nodeType === Node.TEXT_NODE) {
                    offset = startingOffset + targetNodeOffset;
                } else if (targetNode.nodeType === Node.ELEMENT_NODE) {
                    for (var i = 0; i < targetNodeOffset; i++) {
                        var childNode = node.childNodes[i];
                        offset += getMaterialElementLength(childNode);
                    }
                }

                return offset;
            }

            node = it.nextNode();
        }

        return null;
    }

    function selectRange(anchorIndex, focusIndex) {
        var anchor = findNodeAndOffset(anchorIndex);
        var focus = findNodeAndOffset(focusIndex);

        var range = document.createRange();
        range.setStart(anchor[0], anchor[1]);
        range.setEnd(anchor[0], anchor[1]);

        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);

        // Preserve forward/backward direction.
        sel.extend(focus[0], focus[1]);
    }

    function getLine(node) {
        while (node.parentNode !== editorEl) {
            node = node.parentNode;
        }
        return node;
    }

    function isBefore(a, aOffset, b, bOffset) {
        var rangeA = document.createRange();
        var rangeB = document.createRange();

        rangeA.setStart(a, aOffset);
        rangeA.setEnd(a, aOffset);
        rangeB.setStart(b, bOffset);
        rangeB.setEnd(b, bOffset);

        return rangeA.compareBoundaryPoints(Range.START_TO_START, rangeB) === -1;
    }

    function getSelectedLines() {
        var sel = window.getSelection();
        var first = getLine(sel.anchorNode);
        var last = getLine(sel.focusNode);
        if (isBefore(last, 0, first, 0)) {
            var temp = first;
            first = last;
            last = temp;
        }
        var node = first;
        var divs = [];
        while (node) {
            divs.push(node);
            if (node == last) {
                break;
            }
            node = node.nextSibling;
        }

        return divs;
    }

    function flattenNode(node) {
        var it = document.createNodeIterator(
            node, NodeFilter.SHOW_ALL, null
        );
        it.nextNode();
        var nodes = [];
        var inlineNodes = [];

        function insertInlines() {
            if (!inlineNodes.length) {
                return;
            }

            var div = document.createElement('div');
            inlineNodes.forEach(function (value) {
                div.appendChild(value);
            });
            inlineNodes = [];
            nodes.push(div);
        }

        var child = it.nextNode();
        while (child) {
            if (child.tagName === 'DIV') {
                insertInlines();
                nodes.push(child);
            } else {
                inlineNodes.push(child);
            }

            child = it.nextNode();
        }

        insertInlines();

        nodes.reverse();
        nodes.forEach(function (value) {
            node.parentNode.insertBefore(value, node.nextSibling);
        });
        node.parentNode.removeChild(node);
    }

    function getRange() {
        var sel = window.getSelection();
        return sel.getRangeAt(0);
    }

    function getTasks() {
        var tasks = [];
        var checkboxes = editorEl.querySelectorAll('.checkbox');
        for (var i = 0; i < checkboxes.length; i++) {
            var checkbox = checkboxes[i];
            tasks.push({
                id: checkbox.id,
                complete: checkbox.classList.contains('checkbox-checked')
            });
        }
        return tasks;
    }

    return {
        show: function () {
            noteEl.style.display = '';
        },
        hide: function () {
            noteEl.style.display = 'none';
        },
        setTitle: function (title) {
            titleEl.value = title;
            updateTitleHint();
        },
        setContent: function (content, selectionStart, selectionEnd) {
            if (!content) {
                // Need <br> so that text cursor shows up.
                content = '<div><br></div>';
            }

            editorEl.innerHTML = content;
            selectRange(selectionStart, selectionEnd);
        },
        moveLineDown: function () {},
        moveLineUp: function () {},
        focusTitle: function () {
            titleEl.focus();
        },
        focusEditor: function () {
            editorEl.focus();
        },
        pasteText: function (text) {
            var origScrollTop = document.body.scrollTop;

            if (text.indexOf('\n') < 0) {
                insertHtml(text);
            } else {
                // Delete selection, if a non-empty selection exists.
                var selRange = getSelRange();
                if (selRange[0] !== selRange[1]) {
                    document.execCommand('delete', false, null);
                }

                // Create container for making edits to nodes.
                var container = document.createElement('div');
                container.innerHTML = editorEl.innerHTML;

                var pivotIndex = selRange[0];
                var pivot = findNodeAndOffsetRelTo(container, pivotIndex);
                var pivotNode = pivot[0];
                var pivotOffset = pivot[1];

                var lineDiv = pivotNode;
                while (lineDiv !== container && lineDiv.parentNode !== container) {
                    lineDiv = lineDiv.parentNode;
                }

                var range = document.createRange();
                range.selectNodeContents(lineDiv);
                range.setEnd(pivotNode, pivotOffset);
                var startContent = range.cloneContents();

                range.selectNodeContents(lineDiv);
                range.setStart(pivotNode, pivotOffset);
                var endContent = range.cloneContents();

                // The line that new lines should be inserted before.
                var anchorLine = lineDiv.nextSibling;
                container.removeChild(lineDiv);

                var pastedLength = text.length;

                var element = document.createElement('div');
                element.appendChild(startContent);
                var newlineIndex = text.indexOf('\n');
                var textContent = text.substring(0, newlineIndex);
                if (textContent) {
                    element.appendChild(document.createTextNode(textContent));
                }
                text = text.substring(newlineIndex + 1);
                element.normalize();
                if (!element.firstChild) {
                    element.appendChild(document.createElement('br'));
                }
                container.insertBefore(element, anchorLine);

                var buffer = [];
                for (var i = 0; i < text.length; i++) {
                    var c = text[i];
                    if (c === '\n') {
                        var element = document.createElement('div');
                        var line = buffer.join('');
                        buffer = [];
                        if (line) {
                            element.appendChild(document.createTextNode(line));
                        } else {
                            element.appendChild(document.createElement('br'));
                        }
                        container.insertBefore(element, anchorLine);
                    } else {
                        buffer.push(c);
                    }
                }

                var element = document.createElement('div');
                var line = buffer.join('');
                if (line) {
                    element.appendChild(document.createTextNode(line));
                }
                element.appendChild(endContent);
                element.normalize();
                if (!element.firstChild) {
                    element.appendChild(document.createElement('br'));
                }
                container.insertBefore(element, anchorLine);

                document.execCommand('selectall', false, null);

                // Delete selection.
                document.execCommand('delete', false, null);

                // Delete starting div.
                document.execCommand('delete', false, null);

                insertHtml(container.innerHTML);
                document.body.scrollTop = origScrollTop;

                var finalIndex = pivotIndex + pastedLength;
                selectRange(finalIndex, finalIndex);
            }

            var currentLine = getLine(window.getSelection().anchorNode);
            var scrollTop = origScrollTop;
            var scrollBottom = scrollTop + window.innerHeight;
            var lineTop = currentLine.offsetTop;
            var lineBottom = lineTop + currentLine.offsetHeight;
            if (lineTop < scrollTop) {
                document.body.scrollTop = lineTop;
            } else if (lineBottom > scrollBottom) {
                document.body.scrollTop = lineBottom - window.innerHeight;
            }
        },
        toggleTask: toggleTask,
        toggleTaskDone: toggleTaskDone,
        getNoteData: function () {
            return {
                title: titleEl.value,
                content: editorEl.innerHTML,
                tasks: getTasks(),
                selection: getSelRange()
            };
        }
    };
})();

(function () {
    function getFunc(funcPath) {
        var obj = window;
        var context;
        funcPath.split('.').forEach(function (name) {
            context = obj;
            obj = obj[name];
            if (!obj) {
                console.log('Invalid function path segment: ' + name);
            }
        });
        return {
            func: obj,
            context: context
        };
    }

    window.callJS = function (funcPath, args) {
        var funcEntry = getFunc(funcPath);
        var result = funcEntry.func.apply(funcEntry.context, args);
        if (result !== undefined) {
            return JSON.stringify(result);
        }
    };
})();
