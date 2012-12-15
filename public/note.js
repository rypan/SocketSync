$(function(){

  var socket = io.connect('http://localhost:3000', function(){
  // socket
  });

  socket.emit('setNote', $("#note-id").val());

  socket.on('note.divAdded', function (data) {
    if (data.underneath_id) {
      // insert data.content underneath the correct div
      // do it here
    } else {
      // insert at top
      $(".note-body").prepend(data.content);
    }
  });


  $(document).on({
    mouseenter: function () {
      $(this).append($('<span>&nbsp; <a href="#" id="insert-row">Insert</a> <a href="javascript:updateRow()">Update</a> <a href="javascript:deleteRow()">Delete</a></span>'));
    },
    mouseleave: function () {
      $(this).find("span:last").remove();
    }
  }, ".note-body > div");


  $("#add-line-button").click(function(){

    divHtml = "<div data-timestamp='"+Date.now()+"'>"+$("#line-text").val()+"</div>";


    socket.emit('note.addDiv', { note_id: $("#note-id").val(), div: divHtml });

    $(".note-body").prepend(divHtml);


  });

  $("form").submit(function(e){
    e.preventDefault();
  });

});

$(document).on("click", "#insert-row", function(){
  $(this).closest("div").after('hi');
});

// function insertRow(){
// 	$(this).append($('<form><input id="insert-line-text" placeholder="Type a line - hit enter to submit"><button id="insert-line-button">Insert Line</button></form>'));
// }

function updateRow(){

}

function deleteRow(){

}

