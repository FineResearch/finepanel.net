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

  if ($("#dynamed-download-icons").length > 0){
    $("#footer-download-icons").hide();
  }

  function loadPaymentInfo() {
    var url = "/payment_info";
    var loadingMessage = $("#payment-panel-container").data("loading-message");

    $("#pending_credit").html(loadingMessage);

    $.ajax({ url: url, type: 'GET' });
  }

  function loadParticipations() {
    var url = "/participations";
    var loadingMessage = $("#survey-history-container").data("loading-message");

    $("#survey-history-status td:first-child").html(loadingMessage);

    $.ajax({ url: url, type: 'GET' });
  }

  function loadSurveys() {
    var url = "/survey_list";
    var loadingMessage = $("#available-surveys-container").data("loading-message");

    $("#survey-info-status td:first-child").html(loadingMessage);

    $.ajax({ url: url, type: 'GET' });
  }

  loadPaymentInfo();
  loadParticipations();
  loadSurveys();
});
