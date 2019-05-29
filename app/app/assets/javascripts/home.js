$(window).load(function() {
  $('.slider-for').slick({
    slidesToShow: 1,
    slidesToScroll: 1,
    fade: true,
    dots: true,
    focusOnSelect: true,
    autoplay: true,
    autoplaySpeed: 3000,
    arrows: true,
    prevArrow:"<img class='a-left control-c prev slick-prev' src='left-arrow.png'>",
    nextArrow:"<img class='a-right control-c next slick-next' src='right-arrow.png'>"

  });

  $('#featuredContent').css('visibility', 'visible');

  $(document).on('click', ".dropdown.dropdown-toggle", function(e) {
    var parentDropdown = $(this).closest(".dropdown");
    parentDropdown.toggleClass("open");
    e.preventDefault();
  });

  $(document).on('click', function(e) {
    if ($(e.target).closest('.dropdown').length === 0) {
      $('.dropdown').removeClass('open');
    }
  });
  
});
