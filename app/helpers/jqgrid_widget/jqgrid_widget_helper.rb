module JqgridWidget::JqgridWidgetHelper
  include JqgridWidgetUtilities
  
  # JqgridWidgetHelper defines a few things to use in the views to get the jqgrid_widgets in there.
  #
  # This requires jqGrid 3.6 or later, as it uses the "new API"
  #
  # Minimally, you need to call html_table_to_wire in the place where you want the jqgrid to be,
  # and then call wire_jqgrid to insert the Javascript that will connect the jqgrid to it.
  # Those are the main two methods here for use from the outside, but there are a lot of methods
  # here that support the wire_ methods.  All of the jQGrid-specific Javascript should be in here, or
  # else in the jqgrid_widget.js file in public/javascripts.
  #
  # To use this, put in your cell view something like:
  # <%= html_table_to_wire %>
  # <%= wire_jqgrid %>
  #
  # You can also add filters, with html_filters and wire_filters, and a live search with html_live_search_to_wire.
  # TODO: Document this better.
  
  # html_table_to_wire inserts an empty table and div into the html, where the grid and pager will go.
  # A subsequent call to wire_jqgrid will fill it in and start it up.
  # Relies on having @jqgrid_id set.
  def html_table_to_wire
    # puts "Hello from html_table_to_wire: " + @cell.name.to_s
    <<-HTML
		<table id="#{@jqgrid_id}" class="scroll layout_table" cellpadding="0" cellspacing="0"></table>
		<div id="#{@jqgrid_id}_pager" class="scroll" style="text-align:center;"></div>
		HTML
  end

  # wire_jqgrid activates a table as a jqgrid, and sets a bunch of its options.
  # @jqgrid_id (DOM id of the table) must be set ahead of time
  # @jqgrid_options holds the general options.
  # These can be set in the widget, or in the view as a parameter to wire_jqgrid.  View overrides widget.
  # Relies on:
  # @jqgrid_id (DOM id of table)
  # @descendant_dom_ids (structured array of DOM ids of child tables)
  # @select_first_on_load (true if the first record will be automatically selected)
  # @collapse_if_empty (true if the table should be collapsed when it is empty, expanded when nonempty)
  # @columns (set up in the _setup state of the widget)
  #
  # Things you can set in the options (in principle a bit more display-connected than logic-connected):
  # :url (has a smart default, probably won't need to be set)
  # :caption (title bar name, defaults to 'Records')
  # :collapsed (whether the table should start collapsed, defaults to false)
  # :enable_panel (defaults to false; set it to 'row' for a panel under current row, anything else for a titlebar panel)
  # :enable_cell_panel (defaults to false; same options as :enable_panel, but can bring up different panels depending on the cell)
  # :pager => {:rows => 20, :rows_options => '10,20,30'} or just false (default) for no pager.
  # :height => height of the grid in pixels
  # :initial_sort => something, I think it should correspond to a database table field.  TODO: Figure this out
  # :add_button => something other than false if we want to add an add button
  # :row_action => either panel (edit panel opens under row) or title_panel (edit panel opens under title)
  # TODO: Add some more configuration here, make sure the documentation is accurate.
  # I decided to try to put all of the options in the default array in order to make this a bit more future-proof.
  def wire_jqgrid(passed_options = {})
    # Fallback defaults
    options = {
      :viewrecords => true,
      :scrollrows => true,
      :sortorder => 'asc',
      :viewsortable => true,
      :loadui => 'disable',
      :height => 200,
      :collapsed => false,
      :caption => 'Records',
      :altRows => false,
      # :toolbar => [true, 'top'],
      # :loadonce => true,
      
      # If set, :pager should have {:rows_options => , :rows => }
      # These correspond to jqGrid's rowList and rowNum
      # :rows_options is an string representing an array of options for how many records to display
      # :rows is the number of rows to view in the grid
      # If no pager is set, rows is set to "all" (-1).
      :pager => {},
      :pager_id => @jqgrid_id + '_pager',
      :url => url_for(address_to_event({:state => '_send_recordset', :escape => false})),
      :initial_sort => @columns[0][:index],
      :add_button => true,
      :del_button => true,
      :row_action => 'title_panel'
    }.merge(@jqgrid_options).merge(passed_options)
    # Keys in not_in_grid_definition will not be inserted into the main grid
    # (They are handled separately)
    not_in_grid_definition = [:url, :pager, :pager_id, :add_button, :del_button, :row_action]
    # Keys in renamed_options have different names in jqGrid than in jqGrid_widget
    # (Whether or not that was a good idea, I'm handling it now.)
    renamed_options = {
      :initial_sort => :sortname,
      :collapsed => :hiddengrid,
    }
    
    # What is the point of the jQuery() call there?
    # empty_table = @is_top_widget ? "jQuery('##{@jqgrid_id}');" : js_push_json_to_cache(empty_json)
    # js_emit = @is_top_widget ? "jQuery('##{@jqgrid_id}');" : js_push_json_to_cache(empty_json)
    js_emit = @is_top_widget ? '' : js_push_json_to_cache(empty_json)
    
    # TODO: This does not emit particularly pretty Javascript. Maybe clean this up someday.
    js_emit += <<-JS
    jQuery('##{@jqgrid_id}').jqGrid({
      datatype: function(pdata) { retrieveJSON('##{@jqgrid_id}','#{options[:url]}',pdata); },
      colModel:[#{wire_jqgrid_columns}],
      pager: jQuery('##{options[:pager_id]}'),
      #{wire_jqgrid_pager(options)}
      #{wire_jqgrid_cellselect(options)}
      #{wire_jqgrid_rowbeforeselect(options)}
      #{wire_jqgrid_load_complete(options)}
    JS
    (options.reject {|k,v| not_in_grid_definition.include?(k)}).each do |k,v|
      js_emit += (renamed_options.include?(k) ? renamed_options[k].to_s : k.to_s) + ': ' + jqgrid_make_js(v) + ', '
    end
    js_emit += <<-JS
    });
    JS
    js_emit += wire_jqgrid_nav(options)
    js_emit += wire_jqgrid_add_button(options) if options[:add_button]
    # Make the whole titlebar expand and collapse the table
    # Replace 'loading...' with a spinner
    # Store the callback url for a cell click so that I can use it later to regenerate the table
    # Same for the url that provides the html for the edit panels
    # TODO: Someday make this not an event, if possible, would speed things up.
    js_emit += <<-JS
    activateTitleBar('##{@jqgrid_id}');
    jQuery('#load_#{@jqgrid_id}').html("<img src='/images/indicator.white.gif'>");
    jQuery('##{@jqgrid_id}').data('cell_click_url', '#{url_for(address_to_event({:type => :cellClick, :escape => false}))}');
    jQuery('##{@jqgrid_id}').data('draw_panel_url', '#{url_for(address_to_event({:type => :drawPanel, :escape => false}, :data))}');
    JS

    javascript_tag js_emit
  end
  
  # Set the options for the navigation bar
  # The options for add and edit are intentionally not added this way, but as a custom button
  def wire_jqgrid_nav(options)
    if options[:del_button]
      prmDel = {
        :url => url_for(address_to_event({:type => :deleteRecord, :escape => false}))
      }
    else
      prmDel = {}
    end
    prmEdit = {}
    prmAdd = {}
    prmSearch = {}
    prmView = {}
    "jQuery('##{@jqgrid_id}').jqGrid('navGrid','##{options[:pager_id]}'," + jqgrid_make_js({
      :edit => false,
      :add => false,
      :del => options[:del_button],
      :search => false,
      :refresh => false
    }) + ',' + 
    jqgrid_make_js(prmEdit) + ',' + 
    jqgrid_make_js(prmAdd) + ',' + 
    jqgrid_make_js(prmDel) + ',' + 
    jqgrid_make_js(prmSearch) + ',' + 
    jqgrid_make_js(prmView) + ');'
  end
  
  # Add an add button to the navigation bar
  def wire_jqgrid_add_button(options)
    click_function = <<-JS
    function(){
    	var specs = clickSpecsData('0','row','##{@jqgrid_id}'),
    	url = jQuery('##{@jqgrid_id}').data('cell_click_url');
			jQuery.get(url, specs, null, 'script');
    }
    JS
    "jQuery('##{@jqgrid_id}').jqGrid('navButtonAdd','##{options[:pager_id]}'," + jqgrid_make_js({
      :caption => '',
      :title => 'Add new record',
      :buttonicon => 'ui-icon-plus',
      :onClickButton => ActiveSupport::JSON::Variable.new(click_function)
    }) + ');'
  end
  
  # Return the Javascript columns model (with just the jQGrid options, not the JqgridWidget options)
  # See http://www.secondpersonplural.ca/jqgriddocs/index.htm
  def wire_jqgrid_columns
    omit_options = [:custom, :action, :object]
    (@columns.map {|c| jqgrid_make_js(c.dup.delete_if{|k,v| omit_options.include?(k)})}).join(',')
  end
  
  # Return the pager options
  def wire_jqgrid_pager(options)
    if options[:pager].keys.size > 0
      return <<-JS
       	pginput: true,
      	pgbuttons: true,
      	rowList:[#{options[:pager][:rows_options] || ''}],
      	rowNum:#{options[:pager][:rows] || 20},
      JS
    else
      return <<-JS
       	pginput: false,
      	pgbuttons: false,
      	rowList: [],
      	rowNum: -1,
      JS
    end
  end
      
  # Prepare the reaction to the load completion.
  def wire_jqgrid_load_complete(options)
    return '' unless (options[:collapse_if_empty] || options[:single_record_caption])
    return <<-JS
    loadComplete: function(req) {
  		ids = jQuery('##{@jqgrid_id}').getDataIDs();
  		if (ids.length > 0) {
		    var row = jQuery('##{@jqgrid_id}').getRowData(ids[0]);
  		  if (ids.length == 1 && #{(options[:single_record_caption] ? 'true' : 'false')}) {
      		hideTable('##{@jqgrid_id}');
  		    jQuery('##{@jqgrid_id}').setCaption(#{options[:single_record_caption]});
  		    jQuery('##{@jqgrid_id}').closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar').addClass('ui-state-highlight');
  		  } else {
  		    jQuery('##{@jqgrid_id}').setCaption("#{options[:caption]}");
  		    jQuery('##{@jqgrid_id}').closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar').removeClass('ui-state-highlight');
    		  openTable('##{@jqgrid_id}');
  		  }
  		} else {
		    jQuery('##{@jqgrid_id}').setCaption("#{options[:caption]}");
		    jQuery('##{@jqgrid_id}').closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar').removeClass('ui-state-highlight');
    		hideTable('##{@jqgrid_id}');
  		}
    },
    JS
  end

  # Click handling
  # This handles everything, on the basis of a cell select (used to be split into subcalls). Simpler.
  # TODO: However, it's much slower, because nothing happens immediately, AJAX needs to be waited for.
  # It would be nice if I could make the OpenRowPanel or OpenTitlePanel from here.
  # Or at least provide some kind of loading feedback.
  def wire_jqgrid_cellselect(options)
    # cell_actions = jqgrid_make_js(@columns.map {|c| c[:action]})
    # default_action = jqgrid_make_js(options[:row_action])
    # url = jqgrid_make_js(url_for(address_to_event({:type => :cellClick, :escape => false}, :data)))
    <<-JS
    onCellSelect: function(rowid,cellindex,html,event) {
    	var specs = clickSpecsData(rowid,cellindex,event.target),
    	url = jQuery('##{@jqgrid_id}').data('cell_click_url');
			jQuery.get(url, specs, null, 'script');
    },
    JS
  end
  
  # This is a simplified beforeSelectRow handler.
  # Its only purpose is to send the children into the 'loading...' state if the selection has changed.
  def wire_jqgrid_rowbeforeselect(options)
    return <<-JS
    beforeSelectRow: function(ids) {
      if(ids != jQuery('##{@jqgrid_id}').getGridParam('selrow')){
        #{wire_jqgrid_rowselect_set_children_loading}
      }
      return true;
    },
    JS
  end
  
  # When a new selection is made, we need to notify the children, who will need to reload in sympathy.
  def wire_jqgrid_rowselect_set_children_loading
    children_loading = ''
    @cell.descendants_to_reload.each do |child|
    # @descendants_to_reload.each do |child|
      children_loading += <<-JS
        indicateReq('##{child}');closeEditPanel('##{child}');
      JS
    end
    return children_loading
  end
  
  # This puts in the filter placeholder
  def html_filters(table = @jqgrid_id)
    <<-HTML
		<div id="#{table}_filters" class="scroll" style="text-align:center;"></div>
		HTML
  end
  
  # This wires up the filters
  def wire_filters(table = @jqgrid_id)
    filter_partial = url_for(address_to_event({:state => '_filter_display', :escape => false}, :data))
    subfilter_open = url_for(address_to_event({:state => '_set_filter', :escape => false}))
    filter_counts = url_for(address_to_event({:state => '_filter_counts', :escape => false}, :data))
    javascript_tag <<-JS
      jQuery('##{table}_filters').load('#{filter_partial}', function() {
        jQuery(this).find('input[type=checkbox]').click(function() {
          //jQuery(this).find
          var options = {
            dataType:'script'
          }
          jQuery(this).closest('form').ajaxSubmit(options); // uses jQuery Form plugin
          return true;
        });
        jQuery('##{table}_filters').find('.jqgw-filter-category')
          .hover(function(){jQuery(this).addClass('ui-state-hover');},
        		   function(){jQuery(this).removeClass('ui-state-hover');})
          .click(function() {
            jQuery.getScript('#{subfilter_open}&catid='+jQuery(this).attr('id'));
            });
        jQuery.getScript('#{subfilter_open}&init=yes'); // open the default filter
        jQuery.getScript('#{filter_counts}'); // fill in the filter counts
      });
    JS
  end
  
  # Provide the HTML for a live search field
  def html_live_search_to_wire(field, prompt = 'Search', table = @jqgrid_id)
    submit_search_url = url_for(address_to_event({:state => '_send_recordset', :escape => false}))
    <<-HTML
    <form id="#{table}_#{field}_search_form" action="#">
      #{prompt}: <input type="text" name="#{field}" autocomplete="off" value="" id="#{table}_#{field}_search" onkeydown="doLiveSearch('#{table}_#{field}_search','#{submit_search_url}', arguments[0]||event)" />
    </form>    
    HTML
  end

  # TODO: At the moment it isn't possible to have two live searches on the same screen, at least not without redefining this.
  # This should probably go into the main .js file, and have the url passed by the form instead.
  # FIXME: This isn't working quite as expected. The value searched for seems to be the one prior to the keypress.
  # TODO: Also, add some way to "go when unique"
  # def wire_live_search
  #   submit_search_url = url_for(address_to_event({:state => '_send_recordset', :escape => false}))
  #   javascript_tag <<-JS
  #   var timeoutHnd;
  #   function doLiveSearch(table,ev){
  #     // var elem = ev.target||ev.srcElement;
  #     if(timeoutHnd)
  #       clearTimeout(timeoutHnd)
  #     timeoutHnd = setTimeout("gridReload('"+table+"');",450);
  #   }
  #   function gridReload(table){
  #     var fv = jQuery("##{@jqgrid_id}_live_search_field").val();
  #     var fn = jQuery("##{@jqgrid_id}_live_search_field").attr('name');
  #     jQuery.getScript("#{submit_search_url}"+"&livesearch="+table+"@"+fn+"@"+escape(fv));
  #   } 
  #   JS
  # end
  
  def cancel_button(text = 'Cancel')
    submit_tag "Cancel", :onClick => 'closeEditPanel(this);return false;'
  end

  def selector_display(selector_id)
    if selector = @selectors[selector_id]
      field, custom = selector
      resource = @cell.resource
      display_value = self.send(custom, @record)
      <<-HTML
      <span id='display_#{resource}_#{field}'>#{display_value}</span>
      HTML
    else
      ''
    end
  end
  
end