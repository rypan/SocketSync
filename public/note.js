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
      $(this).append($('<span>&nbsp; <a href="#" id="insert-row">Insert</a> <a href="#" id="update-row">Update</a> <a href="#" id="delete-row">Delete</a></span>'));
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
  $(this).closest("div").after('<form><input id="insert-line-text" placeholder="Insert line here"><button id="insert-line-button">Insert Line</button></form>');
});

$(document).on("click", "#update-row", function(){
  $(this).closest("div").after('<form><input id="update-line-text"><button id="insert-line-button">Update</button></form>');
});

$(document).on("click", "#delete-row", function(){
  // Delete Code
});
