module JqueryApotomoControllerMethods

  # I'm overriding the apotomo function below (from controller_methods)
  # This is a) in order to use jQuery without even having Prototype loaded, b) to allow the Javascript emission magic with >>
  def render_page_update_for(processed_handlers)
    js_emit = ''
    js_tail_emit = ''
    processed_handlers.each do |item|
    (handler, content) = item
      next unless content

      if content.kind_of? String
        # This is terrible, but I need some way to emit JavaScript directly.
        # So, for now, prepend >> to the JS and it'll go.
        # If there is a "<<>>" in the content the stuff after it will be executed after the rest.
        if content[0..1] == '>>'
          contents = content[2..-1].split('<<>>')
          js_emit += contents[0]
          js_tail_emit += contents[1] if contents[1] 
          # js_emit += content[2..-1]
        else
          js_emit += "jQuery('##{handler.widget_id}').html('#{@template.escape_javascript(content)}');"
        end
        # page.replace handler.widget_id, content
      else
        js_emit += content
        # page << content
      end
    end
    render :js => js_emit + js_tail_emit
  end
  
end
