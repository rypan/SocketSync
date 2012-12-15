var socket = io.connect('http://localhost');
// socket.on('news', function (data) {
//   console.log(data);
//   // socket.emit('my other event', { my: 'data' });
// });


socket.on('note.divAdded', function (divContent) {
  $(".note-body").prepend(divContent);
});



$(function(){

  $(".note-body > div").hover(
    function () {
      $(this).append($('<span>&nbsp; <a href="#">Update</a> <a href="#">Delete</a></span>'));
    },
    function () {
      $(this).find("span:last").remove();
    }
  );

  $("#add-line-button").click(function(){

    divHtml = "<div data-timestamp='"+Date.now()+"'>"+$("#line-text").val()+"</div>";


    socket.emit('note.addDiv', { note_id: $("#note-id").val(), div: divHtml });
  });

});

