module ShowdatesHelper

  def showdate_seating_choices(showdate)
    if showdate.seatmap
      link_to 'Seats...', '', :class => 'btn btn-outline-primary btn-small'
    else
      content_tag 'span', 'General Admission'
    end
  end

  def time_in_words_relative_to(ed,sd)
    if (sd.month == ed.month) && (sd.day == ed.day) && (sd.year == ed.year)
      ed.strftime("%l:%M%p day of show")
    else
      ed.to_formatted_s(:showtime)
    end
  end

end
