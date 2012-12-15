$(function(){

  var socket = io.connect('http://localhost:3000', function(){
  // socket
  });

  socket.emit('setNote', $("#note-id").val());

  socket.on('note.divAdded', function (data) {
    $(".note-body").prepend(data.content);
  });


  $(document).on({
    mouseenter: function () {
      $(this).append($('<span>&nbsp; <a href="javascript:insertRow()">Insert</a> <a href="javascript:updateRow()">Update</a> <a href="javascript:deleteRow()">Delete</a></span>'));
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

function insertRow(){
	$(this).append($('<form><input id="insert-line-text" placeholder="Type a line - hit enter to submit"><button id="insert-line-button">Insert Line</button></form>'));
}

function updateRow(){

}

function deleteRow(){

}

