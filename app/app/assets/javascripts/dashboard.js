 
$(document).ready(function() {
  $('#payment-history').click(function(e) {
    e.preventDefault();
    $('.modal_table_container .loading').show();
    var pending_credit = $('#pending_credit').text().match(/(.*?)([0-9]*\.[0-9]+|[0-9]+)/)[2];
    $.ajax({
      url: "/payment_history?pending_credit=" + pending_credit,
      type: 'GET',
      dataType: 'html',
      success: function (response) {
        $(".modal_table_container").html(response);
      }
    });
  });
});
