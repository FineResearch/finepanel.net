$(window).load(function() {
  
  function add_other_to_select(select) {
    $(select).append('<option value="" class="other">' + $(select).data('other') + '</option>');
  }

  function other_selected(select) {
    return $(select).children(':selected').attr('class') == 'other';
  }

  add_other_to_select('#country_id');
  add_other_to_select('#city_id');
  add_other_to_select('#specialty_id');

  $('#other_country').hide();
  $('#other_city').hide();
  $('#other_specialty').hide();

  $("#country_id").on('change', function(e) {
    var countryId = $(this).val();
    var citiesSelect = $("#city_id");

    citiesSelect.find('option').remove();
    if (other_selected('#country_id')) {
      $('div#other_country').show();
      add_other_to_select('#city_id');
      $('div#other_city').show();
    } else {
      $('div#other_country').hide();

      $.ajax({
        url: "/countries/cities/" + countryId,
        type: 'GET',
        dataType: 'json',
        success: function (response) {
          $.each(response, function(key, value) {
            citiesSelect.append('<option value='+value[1]+'>'+value[0]+'</option>');
          });
          add_other_to_select('#city_id');
        }
      });
    }
  });

  function city_selection() {
    if (other_selected('select#city_id')) {
      $('div#other_city').show();
    } else {
      $('div#other_city').hide();
    }
  }
  function specialty_selection() {
    if (other_selected('select#specialty_id')) {
      $('div#other_specialty').show();
    } else {
      $('div#other_specialty').hide();
    }
  }

  $('select#city_id').on('change', city_selection);
  $('select#specialty_id').on('change', specialty_selection);
});
