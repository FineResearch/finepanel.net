$(document).ready(function() {

  $('form#new_post').bind('ajax:complete', function(xhr, data) {
    if(data.status == 200) {
      var $this = $(this);
      //Add the post to the timeline
      $(data.responseText).hide().prependTo("div#posts").fadeIn("slow");

      //And reset all the fields
      $this.find('input, textarea').not("input[type=submit], input[type=hidden]").val('');

      if(!$this.hasClass("finepanel")) {
        // Minimize the composer if the first tab is selected
        if(getSelectedTab().attr('href') == "#comment") $this.addClass("mini");
        // Change filter to all if it's not selected
        if(getSelectedFilter() != "all") $("a[data-post-kind=all]").click();
      } else {
        $this.addClass("mini");
      }

      $this.find(".post-loader").hide();

      // Remove zero state
      var $zero_state = $("div#posts p.zero-state");
      if($zero_state.length > 0) $zero_state.remove();
    }
  }).bind('ajax:error', function(xhr, data) {
      // Display the errors
      if(data.status != 200) {
        $("form#new_post .post-loader").hide();
        $("#postErrors").text(data.responseJSON['error_msg']);
        $('#postErrors').show();
        $('#postErrors').delay(5000).fadeOut('slow');
      }
  });

  $('div#posts').on('ajax:success', 'form#new_comment', function(xhr, data) {
    var $this = $(this);
    var $zero_state = $this.parent().find('.no-comments');
    // Add the post to the timeline
    $this.before(data).hide().fadeIn("slow");
    // And reset all the fields
    $this.find('input').not("input[type=hidden]").val('');

    if ($zero_state.length > 0) {
      // Remove zero state
      var comments_text = $('#has_one_comment').val();
      $zero_state.removeClass("no-comments");
      // Update comments count
      $($zero_state).siblings('.comments_count').html('<span class="count">1</span> ' + comments_text);
    }
    else {
      // Already has comments
      var count = parseInt($this.parent().find('.count').text());
      var comments_text = $('#has_many_comments').val();
      // Update comments count
      count = count + 1;
      $this.parent().find('.comments_count').html('<span class="count">' + count + '</span> ' + comments_text);
    }
  }).on('ajax:error', 'form#new_comment', function(xhr, data) {
    // Display the errors
    $("div#errors-modal").html(data).reveal({
      animation: 'none', //fade, fadeAndPop, none
      animationspeed: 300, //how fast animations are
      closeOnBackgroundClick: true, //if you click background will modal close?
      dismissModalClass: 'close-reveal-modal' //the class of a button or element that will close an open modal
    });
  }).on('submit', 'form#new_comment', function(e){
    if($(this).find('.comment-input').val() == '')
      return false;
  }).on('ajax:beforeSend', 'form#new_comment', function(e) {
    if($(this).find('.comment-input').prop('disabled'))
      return false;
    $(this).find('.comment-input').prop('disabled', true);
    $(this).siblings('.post-loader').css('display', 'inline-block').show();
  }).on('ajax:complete', 'form#new_comment', function(e) {
    $(this).find('.comment-input').removeProp('disabled', true);
    $(this).siblings('.post-loader').hide();
  });


  $("form#new_post input[type=submit]").click(function() {
    $("form#new_post .post-loader").show();
  });

  $("form#new_post textarea.comment-text").focus(function() {
    $("form#new_post").removeClass("mini");
  });

  $("form#new_post textarea.comment-text").blur(function() {
    if(!$(this).val()) {
      $("form#new_post").addClass("mini");
    }
  });

  $("a[data-bind=attach-url]").click(function(event) {
    event.stopPropagation();
    event.preventDefault();

    var $this = $(this);

    var $file_input = $("input.image-file-field", "#imageTab");
    var $url_input = $("input.external-url-input", "#imageTab");

    if($file_input.is(":hidden")) {
      $file_input.show();
      $url_input.hide();
      $url_input.val("");

      $this.html("Adjuntar un URL");
    } else {
      $file_input.hide();
      $file_input.val("");
      $url_input.show();

      $this.html("Adjuntar un archivo");
    }
  });

  updateFormTabs(getSelectedTab());

  function getSelectedFilter() {
    return $("dl.sub-nav dd.active a").data("post-kind");
  }

  function getSelectedTab() {
    return $('div#new-post dl.tabs dd.active a');
  }

  $('div#new-post dl.tabs a').click(function() {
    var $tab = $(this);

    if ($tab.attr("href") == "#comment"){
      $("form#new_post").addClass("mini");
    } else {
      $("form#new_post").removeClass("mini");
    }

    updateFormTabs($tab);
  });

  function updateFormTabs(active_tab) {
    $('input, textarea', '.tabs-content li').each(function(index, value) {
      var $input = $(value);
      $input.prop("disabled", true);

      if($input.attr("id") != "post_kind") $input.val('');
    });

    $("input, textarea", active_tab.attr('href') + 'Tab').each(function(index, value) {
      $(value).prop("disabled", false);
    });    
  }

});
