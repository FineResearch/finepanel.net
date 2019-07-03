// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require jquery
//= require jquery_ujs
//= require slick
//= require jquery.scrollTo
//= require addtohomescreen.min
//= require foundation
//= require responsive-tables
//= require home
//= require registrations
//= require posts
//= require dashboard
//= require jquery.remotipart
//= require_self



$(document).on('ready turbolinks:load', function() {
  addToHomescreen();
  /* Use this js doc for all application specific JS */

  /* TABS --------------------------------- */
  /* Remove if you don't need :) */

  function activateTab($tab) {
    var $activeTab = $tab.closest('dl').find('dd.active'),
        contentLocation = $tab.children('a').attr("href") + 'Tab';

    // Strip off the current url that IE adds
    contentLocation = contentLocation.replace(/^.+#/, '#');

    //Make Tab Active
    $activeTab.removeClass('active');
    $tab.addClass('active');

    //Show Tab Content
    $(contentLocation).closest('.tabs-content').children('li').removeClass('active').hide();
    $(contentLocation).css('display', 'block').addClass('active');
  }

  $('dl.tabs dd a').on('click.fndtn', function (event) {
    activateTab($(this).parent('dd'));
  });

  if (window.location.hash) {
    activateTab($('a[href="' + window.location.hash + '"]').parent('dd'));
    $.foundation.customForms.appendCustomMarkup();
  }

  /* ALERT BOXES ------------ */
  $(".alert-box").delegate("a.close", "click", function(event) {
    event.preventDefault();
    $(this).closest(".alert-box").fadeOut(function(event){
      $(this).remove();
    });
  });   

  /* DROPDOWN NAV ------------- */
  var lockNavBar = false;
  // Check if nav is visible to know if mobile version is being used
  var mobile = !$('#header .navigation').is(':visible');
  if (mobile) {
    $('.nav-bar a.flyout-toggle').on('click.fndtn touchstart.fndtn', function(e) {
      e.preventDefault();
      var flyout = $(this).siblings('.flyout').first();
      if (lockNavBar === false) {
        $('.nav-bar .flyout').not(flyout).slideUp(500);
        flyout.slideToggle(500, function(){
          lockNavBar = false;
        });
      }
      lockNavBar = true;
    });
    $('.nav-bar>li.has-flyout').addClass('is-touch');
  } else {
    $('.nav-bar>li.has-flyout').hover(function(e) {
      e.stopPropagation();
      $(this).children('.flyout').show();
    }, function() {
      $(this).children('.flyout').hide();
    });
  }

  /* DISABLED BUTTONS ------------- */
  /* Gives elements with a class of 'disabled' a return: false; */
  $('.button.disabled').on('click.fndtn', function (event) {
    event.preventDefault();
  });


  /* SPLIT BUTTONS/DROPDOWNS */
  $('.button.dropdown > ul').addClass('no-hover');

  $('.button.dropdown li').on('click.fndtn touchstart.fndtn', function (e) {
    e.stopPropagation();
  });
  $('.button.dropdown.split span').on('click.fndtn touchstart.fndtn', function (e) {
    e.preventDefault();
    $('.button.dropdown').not($(this).parent()).children('ul').removeClass('show-dropdown');
    $(this).siblings('ul').toggleClass('show-dropdown');
  });
  $('.button.dropdown').not('.split').on('click.fndtn touchstart.fndtn', function (e) {
    $('.button.dropdown').not(this).children('ul').removeClass('show-dropdown');
    $(this).children('ul').toggleClass('show-dropdown');
  });
  $('body, html').on('click.fndtn touchstart.fndtn', function () {
    $('.button.dropdown ul').removeClass('show-dropdown');
  });

  // Positioning the Flyout List
  var normalButtonHeight  = $('.button.dropdown:not(.large):not(.small):not(.tiny)').outerHeight() - 1,
      largeButtonHeight   = $('.button.large.dropdown').outerHeight() - 1,
      smallButtonHeight   = $('.button.small.dropdown').outerHeight() - 1,
      tinyButtonHeight    = $('.button.tiny.dropdown').outerHeight() - 1;

  $('.button.dropdown:not(.large):not(.small):not(.tiny) > ul').css('top', normalButtonHeight);
  $('.button.dropdown.large > ul').css('top', largeButtonHeight);
  $('.button.dropdown.small > ul').css('top', smallButtonHeight);
  $('.button.dropdown.tiny > ul').css('top', tinyButtonHeight);

  $('.button.dropdown.up:not(.large):not(.small):not(.tiny) > ul').css('top', 'auto').css('bottom', normalButtonHeight - 2);
  $('.button.dropdown.up.large > ul').css('top', 'auto').css('bottom', largeButtonHeight - 2);
  $('.button.dropdown.up.small > ul').css('top', 'auto').css('bottom', smallButtonHeight - 2);
  $('.button.dropdown.up.tiny > ul').css('top', 'auto').css('bottom', tinyButtonHeight - 2);

  $(".header-menu").click(function(){
    $("ul").toggleClass("active");
  })

  $(function(){ $(document).foundation(); });

});
