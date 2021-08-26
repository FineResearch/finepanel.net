$(document).ready(function(){
  var url = window.location.href;
  if (url.match(/faq/)) {
    // fade in #back-top
    $(function() {
      $(window).scroll(function () {
        if ($(this).scrollTop() > 172) {
          $('#back-top').fadeIn();
          $('#side-nav').removeClass('relative-nav').addClass('fixed-nav');
        } else {
          $('#back-top').fadeOut();
          $('#side-nav').removeClass('fixed-nav').addClass('relative-nav');
        }
      });
      // scroll body to 0px on click
      $('#back-top a').click(function () {
        $('body,html').animate({
          scrollTop: 0
        }, 800);
        return false;
      });
    });

    $('.faq_toc').on('click', function(e) {
      var target = $(this.getAttribute('href'));
      if( target.length ) {
        e.preventDefault();
        $('html, body').stop().animate({
          scrollTop: target.offset().top
        }, 1000);
      }
      $("li.active").removeClass("active");
      $(this).parent().addClass("active");
    });
  }
});
