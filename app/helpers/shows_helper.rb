module ShowsHelper

  def label_for_event_type(type)
    case type
    when 'Special Event' then 'Event'
    when 'Class' then 'Class'
    else 'Show'
    end
  end

  def link_to_show_tickets(show)
    params = {:show_id => show.id}
    params[:what] = 'Special Events' if show.special?
    store_url(params)
  end

  def link_to_showdate_tickets(showdate, params={})
    params[:showdate_id] = showdate.id
    params[:what] = 'Special Events' if showdate.show.special?
    store_url(params)
  end

end
