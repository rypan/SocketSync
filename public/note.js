$(".note-body > div").hover(
  function () {
    $(this).append($('<span>&nbsp; <a href="#">Update</a> <a href="#">Delete</a></span>'));
  }, 
  function () {
    $(this).find("span:last").remove();
  }
);