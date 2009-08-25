module JqgridWidget::JqgridWidgetHelper
  # JqgridWidgetHelper defines a few things to use in the views to get the jqgrid_widgets in there.
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
  #
  # html_table_to_wire inserts an empty table and div into the html, where the grid and pager will go.
  # A subsequent call to wire_jqgrid will fill it in and start it up.
  # Relies on having @jqgrid_id set.
  def html_table_to_wire
    <<-HTML
		<table id="#{@jqgrid_id}" class="scroll" cellpadding="0" cellspacing="0"></table>
		<div id="#{@jqgrid_id}_pager" class="scroll" style="text-align:center;"></div>
		HTML
  end

  # wire_jqgrid activates a table as a jqgrid, and sets a bunch of its options.
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
  def wire_jqgrid(options = {})
    options[:pager] ||= {}
    options[:pager_id] ||= @jqgrid_id + '_pager'
    options[:height] ||= 150
    # options[:enable_panel] ||= false
    # options[:enable_cell_panel] ||= false
    options[:collapsed] ||= false #(options[:collapsed] != false) instead to make it default to true
    # options[:url] ||= url_for(address_to_event({:state => '_send_recordset', :escape => false}, :data))
    # I have to make this not be a data call, because I need it to be able to react to rowClicks.
    # It would have been more convenient as a data call.  But I don't think data calls will bundle the child responses.
    # options[:url] ||= url_for(address_to_event({:state => '_send_recordset', :bundle => 'yes', :escape => false}))
    options[:url] ||= url_for(address_to_event({:state => '_send_recordset', :escape => false}))
    options[:caption] ||= @caption || 'Records'
    options[:initial_sort] ||= @columns[0][:index]
    options[:add_button] ||= true

    # col_names, col_model = wire_jqgrid_columns
    empty_table = (@is_top_widget == 'yes') ? "jQuery('##{@jqgrid_id}');" : js_push_json_to_cache(empty_json)
    javascript_tag <<-JS
    #{empty_table}
    jQuery("##{@jqgrid_id}").jqGrid({
      datatype: function(pdata) { retrieveJSON('##{@jqgrid_id}','#{options[:url]}',pdata); },
      height: #{options[:height]},
      colModel:[#{wire_jqgrid_columns}],
      #{wire_jqgrid_pager(options)}
      viewrecords: true,
      scrollrows: true,
      pager: jQuery('##{options[:pager_id]}'),
      sortname: '#{options[:initial_sort]}',
      loadui: 'block',
      hiddengrid: #{options[:collapsed] ? 'true' : 'false'},
      #{wire_jqgrid_cellselect}
      #{wire_jqgrid_rowbeforeselect}
      #{wire_jqgrid_rowselect}
      #{wire_jqgrid_load_complete}
      sortorder: "asc",
      viewsortable: true,
      //toolbar: [true,'top'],
      //loadonce: true,
      caption: "#{options[:caption]}"
    }).navGrid('##{options[:pager_id]}', {edit:false,add:false,del:true,search:false,refresh:false})
    #{wire_jqgrid_add_button(options)}
    ;
    // make the whole titlebar expland and collapse the table
    activateTitleBar('##{@jqgrid_id}');
    // replace "Loading..." with a spinner
    jQuery('#load_#{@jqgrid_id}').html("<img src='/images/indicator.white.gif'>");
    JS
  end
  
  # Prepare the columns model
  # See http://www.secondpersonplural.ca/jqgriddocs/index.htm
  # This turned out to be a pretty trivial method once everything got put into make_js.
  def wire_jqgrid_columns
    # Don't emit jqGridWidget options, just jqGrid options
    (@columns.map {|c| make_js(c.dup.delete_if{|k,v| [:custom, :panel, :panel_under_row].include?(k)})}).join(',')
  end
  
  # Turn Ruby datatypes into emittable Javascript
  # Cf. array_or_string_to_javascript, is there an official way to do this already built in?
  # I couldn't get case/when to work here for some reason
  def make_js(thing)
    (thing.class == Hash) ? '{' + (thing.map{|k,v| k.to_s + ':' + make_js(v)}).join(',') + '}' :
      (thing.class == Array ? '[' + (thing.map{|v| make_js(v)}).join(',') + ']' :
        (thing.class == String ? "'#{thing}'" : thing.to_s
        )
      )
  end
  
  # Prepare the pager options
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
      	rowList:[],
      JS
    end
  end
  
  # Add an "add" button
  def wire_jqgrid_add_button(options)
    return '' unless options[:add_button]
    return <<-JS
        .navButtonAdd('##{options[:pager_id]}',{caption:'',title:'Add new record',buttonicon:'ui-icon-plus',
        	onClickButton:function(){
            #{wire_jqgrid_rowselect_panel(:add)}
          } 
        });
    JS
  end
    
  # Prepare the reaction to the load completion.
  def wire_jqgrid_load_complete
    return '' unless (@collapse_if_empty || @single_record_caption)
    return <<-JS
    loadComplete: function(req) {
  		ids = jQuery('##{@jqgrid_id}').getDataIDs();
  		if (ids.length > 0) {
		    var row = jQuery('##{@jqgrid_id}').getRowData(ids[0]);
  		  if (ids.length == 1 && #{(@single_record_caption ? 'true' : 'false')}) {
    	    //console.dir(ids);
  		    //console.dir(row);
      		hideTable('##{@jqgrid_id}');
  		    jQuery('##{@jqgrid_id}').setCaption(#{@single_record_caption});
  		    jQuery('##{@jqgrid_id}').closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar').addClass('ui-state-highlight');
  		  } else {
  		    jQuery('##{@jqgrid_id}').setCaption("#{@caption}");
  		    jQuery('##{@jqgrid_id}').closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar').removeClass('ui-state-highlight');
    		  openTable('##{@jqgrid_id}');
  		  }
  		} else {
		    jQuery('##{@jqgrid_id}').setCaption("#{@caption}");
		    jQuery('##{@jqgrid_id}').closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar').removeClass('ui-state-highlight');
    		hideTable('##{@jqgrid_id}');
  		}
    },
    JS
  end

  # This generates the onRowSelect option for jqgrid, which handles the event of a row being clicked on.
  def wire_jqgrid_rowbeforeselect
    children_loading = wire_jqgrid_rowselect_children
    return <<-JS
      beforeSelectRow: function(ids) {
        //console.log(jQuery('##{@jqgrid_id}').getGridParam('selrow'));
        //console.log(ids);
        if(ids != jQuery('##{@jqgrid_id}').getGridParam('selrow')){
          #{children_loading}
          closeEditPanel('##{@jqgrid_id}');
          jQuery.getScript("#{url_for(address_to_event({:type => :rowClick, :escape => false}))}&id="+ids);
        }
        return true;
      },
    JS
  end
    
  # This generates the onRowSelect option for jqgrid, which handles the event of a row being clicked on.
  def wire_jqgrid_rowselect
    children_loading = ''
    #children_loading = wire_jqgrid_rowselect_children
    return <<-JS
      onSelectRow: function(ids) {
        //if(ids == null) ids==0; // can this happen? And what is this supposed to do? Generate false?
        //console.log(jQuery('##{@jqgrid_id}').getGridParam('selrow'));
        //console.log(ids);
        //if(ids != jQuery('##{@jqgrid_id}').getGridParam('selrow')){
        //  #{children_loading}
        //}
        //jQuery.getScript("#{url_for(address_to_event({:type => :rowClick, :escape => false}))}&bundle=yes&id="+ids);
        #{wire_jqgrid_rowselect_panel(:edit)}
      },
    JS
  end
  
  # Prepare the edit panel arising from row clicks
  # The :edit mode is the normal behavior, the :add mode is used to respond to clicking an add button.
  def wire_jqgrid_rowselect_panel(mode = :edit)
    return '' unless @row_panel.size > 0
    ids = (mode == :edit) ? 'ids' : "'0'"
    func = @row_panel_under_row ? 'openRowPanel' : 'openTitlePanel'
    return <<-JS
      #{func}(#{ids},'row','','##{@jqgrid_id}','#{url_for(address_to_event({:type => :openEditPanel, :escape => false}, :data))}',[]);
      JS
  end
  
  # When a new selection is made, we need to notify the children, who will need to reload in sympathy.
  def wire_jqgrid_rowselect_children
    children_loading = ''
    @descendants_to_reload.each do |child|
      children_loading += <<-JS
        indicateReq('##{child}');closeEditPanel('##{child}');
      JS
    end
    return children_loading
  end
  
  # When a cell is clicked on, it might trigger the opening of an edit panel.
  # Different cells can have different behaviors, based on the properties in the columns model.
  # TODO: Get rid of opts?  I'm not using it for anything.
  def wire_jqgrid_cellselect(mode = :edit)
    row_panels = @columns.map {|c| (mode == :edit && c[:panel].size > 0 && c[:panel_under_row]) ? 1 : 0}
    title_panels = @columns.map {|c| (c[:panel].size > 0 && !c[:panel_under_row]) ? 1 : 0}
    row_needed = row_panels.include?(1)
    title_needed = title_panels.include?(1)
    return '' unless row_needed || title_needed
    rowid = (mode == :edit) ? 'rowid' : "'0'"
    url = url_for(address_to_event({:type => :openEditPanel, :escape => false}, :data))
    if row_needed
      panel_js = <<-JS
      openRowPanel(#{rowid},cellindex,html,target,'#{url}',[#{row_panels.join(',')}]);
      JS
    else
      panel_js = ''
    end
    if title_needed
      panel_js += <<-JS
      openTitlePanel(#{rowid},cellindex,html,target,'#{url}',[#{title_panels.join(',')}]);
      JS
    end
    return <<-JS
    onCellSelect: function(rowid,cellindex,html,target) {
      #{panel_js}
    },
    JS
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
          jQuery(this).find
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
  
end