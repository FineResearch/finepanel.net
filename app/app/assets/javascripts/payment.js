PaymentData = (function(){

  var enable_edit_mode = function() {
    show_input_container($('input[type=\"submit\"]'));
    show_input_container($('button#disable-edit-mode'));
    show_selects();
    hide_input_container($('button#enable-edit-mode'));
    $('div.input-data').remove();
    $('input, div.dropdown').not('input[type=\"hidden\"], input[type=\"submit\"], input[type=\"button\"]').fadeIn();
  };

  var disable_edit_mode = function() {
    hide_input_container($('form input[type=\"submit\"]').hide());
    hide_input_container($('button#disable-edit-mode'));
    show_input_container($('button#enable-edit-mode').show());
    hide_input_container($('form input, form div.dropdown').not('input[type=\"hidden\"], input[type=\"submit\"], input[type=\"button\"]'));
    hideInputs();
    hideSelects();
    $('div.input-data').fadeIn();
  };
  var hide_input_container = function(container) {
    $(container).hide();
  };

  var show_input_container = function(container) {
    $(container).show();
  };

  function show_selects(){
    $('form select').each(function() {
      $(this).show();
    })
  }

  var setupEditClick = function(){
    $('button#enable-edit-mode').on('click', function(event) {
      event.preventDefault();
      enable_edit_mode();
    });
  };

  var setupCancelClick = function(){
    $('button#disable-edit-mode').on('click', function(event) {
      event.preventDefault();
      disable_edit_mode();
    });
  };

  var setupAccountOwnerSelect = function(){
    $('#user_bank_account_owner').change(function() {
      var account_name = $('#account_name');
      $(this).val() == 'false' ?  account_name.fadeIn() : account_name.fadeOut();
    });
  };

  var hideSelects = function(){
    $('form select').each(function(index, node) {
      if ($(node).val() != '') {
        $(node).after($('<div></div>').html($(`#${node.id} option:selected`).text()).attr('class', 'input-data'));
      } else {
        var input_other = $(node).parents('div.row').first().next('div[id^=\"other_\"]').find('input');
        if (input_other.length) {
          $(node).after($('<div></div>').html(input_other.val()).attr('class', 'input-data'));
        } else {
          $(node).after($('<div></div>').html('n/a').attr('class', 'input-data'));
        }
      }
      $(node).hide();
    });
  };

  var hideInputs = function(){
    $('form input').not('input[type=\"hidden\"], input[type=\"submit\"], input[type="button"], input[id$=\"_text\"]').each(function(index, node) {
      if ($(node).val() != '')
        $(node).after($('<div></div>').html($(node).val()).attr('class', 'input-data'));
      else
        $(node).after($('<div></div>').html('n/a').attr('class', 'input-data'));
    });
  };

  var setup_initial_edit_status = function() {
    disable_edit_mode();
    setupEditClick();
    setupCancelClick();
    setupAccountOwnerSelect();
  };

  return {
    init: function(){
      setup_initial_edit_status();
    }
  }
})();

$(function() {
  PaymentData.init();
});
