module JqgridWidgetUtilities
  # Utility functions
  # Mixed into the jqgrid_widget_helper via:
  # include JqgridWidgetUtilities
  
  # Turn Ruby datatypes into emittable Javascript
  # Cf. array_or_string_to_javascript, is there an official way to do this already built in?
  def jqgrid_make_js(thing)
    (thing.class == Hash) ? '{' + (thing.map{|k,v| k.to_s + ':' + jqgrid_make_js(v)}).join(',') + '}' :
      (thing.class == Array ? '[' + (thing.map{|v| jqgrid_make_js(v)}).join(',') + ']' :
        (thing.class == String ? "'#{thing}'" : thing.to_s
        )
      )
  end

  # http://errtheblog.com/posts/11-block-to-partial
  def jqgrid_widget_block_to_partial(partial_name, options = {}, &block)
    options.merge!(:body => capture(&block))
    concat(render(:partial => partial_name, :locals => options))
  end
  
end