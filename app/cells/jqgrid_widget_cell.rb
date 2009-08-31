class JqgridWidgetCell < Apotomo::StatefulWidget
  # JqgridWidgetCell is the heart of the jQGrid widget, an extension of Apatomo's StatefulWidget
  # TODO: Some documentation here.
  
  # In order to be able to do urlencoding, I bring in the Javascript helpers here.
  # TODO: I forget where I use this.  Is it really urlencoding?  Do I really still use it?  Check.
  include ActionView::Helpers::JavaScriptHelper 
  # Bring in address_to_event, since I use it here (though I might like to put it somewhere else)
  include Apotomo::ViewHelper
  # Bring in a couple of things from jRails.  Probably it would be better to simply attach jRails in full,
  # but for the moment there are only a couple of things that are needed for this to operate in jQuery alone.
  require 'jquery_apotomo_helper_methods'
  
  helper :all
  # Make some of the methods defined here available to the view as well
  helper_method :js_reload_grid, :js_select_id, :js_push_json_to_cache, :empty_json
  helper_method :param
  # helper_method :selector_field_id
  # Make the JqgridWidgetHelper methods available to the view; these appear not to be noticed by helper :all
  helper JqgridWidget::JqgridWidgetHelper
  
  attr_reader :record
  attr_reader :jqgrid_id
  
  # SETUP
  
  # Assume all documentation-like comments may be out of date.
  # The _setup state is the start state. This will render the partial app/cells/{cell}/_setup.html.erb.
  # That partial should contain the widget placeholders (empty html table and div) and a setup call to jQGrid.
  # The helpers html_table_to_wire and wire_jqgrid can assist in this endeavor.
  # The initial wiring of the jqgrid will trigger a call to load the recordset.
  # In order to reduce the number of AJAX requests, I have implemented a data-caching mechanism that is consulted
  # first before an AJAX request is made.  Upon initial wiring of all of the child tables, an empty recordset is cached,
  # which is used instead of querying the server.  When the topmost widget loads its recordset, it retrieves
  # the data (via the _send_recordsets state) of the widget and all of its descendants, in the form of a series
  # of Javascript calls to push the JSON data into the caches of the parent widget and all of its descendants,
  # clear the rest, and then trigger reloads for everybody.
  #
  # A subclass should call it in something like the following way.
  # Other things one can define:
  # @children_to_hide (ids of the tables that will be collapsed upon a row select)
  # @children_to_trigger (ids of the tables that will be put into a 'loading...' state upon a row select)
  # @select_first (true if the first record should be selected immediately upon loading the table)
  # @rows_per_page (in principle the number of records per page when using paginator, not tested)
  # @row_action = 'title_panel', 'row_panel', or 'event'
  # @row_object = partial to render when a row is clicked for (title_panel, row_panel)
  #
  # def _setup
  #   super do |col|
  #     col.add_column('name', :width => 100, :sortable => true)
  #     col.add_column('degrees', :width => 175, :custom => :custom_degrees)
  #     col.add_column('profiles', :width => 175, :custom => :custom_profiles)
  #   end
  #   @children_to_hide = ['person_student_degrees_list', 'person_employee_sections_list']
  #   nil
  # end
  # TODO: Perhaps later I may want to be able to make the default filter not be the first one?
  def _setup
    @caption = param(:resource).pluralize.humanize #'Records'
    @collapse_if_empty = false
    @single_record_caption = false
    # @single_record_caption is a small Javascript snippet, can make use of 'row' variable.
    # for example: @single_record_caption = "'Degree track: ' + row.name"
    @find_include = nil
    @filters = [['all', {:name => 'All'}]]
    
    @columns  = []
    @row_action = 'title_panel'
    @row_object = '_panel'
    
    # Make settings available to the helper.
    # Several of these have been derived from instance methods, because I need them to be available
    # before the widget hits the _init state.
    # TODO: Reduce the number of these to the bare minimum, once I'm sure what I need.
    # TODO: Or not, perhaps increasing them would be actually be better, for anything that need not be frozen.
    @jqgrid_id = jqgrid_dom_id
    @descendants_to_reload = descendants_to_reload
    @select_on_load = select_on_load
    @prefix = param(:prefix)
    @is_top_widget = param(:top_widget)
    
    @record = scoped_model.new
    
    yield self if block_given?
    
    @sortable_columns = (@columns.map {|c| c[:sortable] ? c[:index] : nil}).compact
    puts "sortable columns: " + @sortable_columns.inspect
    @default_sidx = (@columns.map {|c| c[:sortable] == 'default' ? c[:index] : nil}).compact.first
    puts "default sidx: " + @default_sidx.inspect
    nil
  end
 
  # To load a recordset for the table in this widget, a find call is passed to the scoped_model.
  # If this is a top widget, it is appropriate to leave it as resource_model.  If this is a
  # child widget, this can be something like parent.records.contacts (or, you have defined a named scope,
  # that could also go here).  You can rely on records being an attribute of parent.
  def scoped_model
    resource_model
  end

  # If this is child selector widget, put the field from which the ID is drawn here, as a symbol.
  # E.g., :thingie_id.  If this returns nil, it is presumed to be a subgrid-type child.
  def selector_for
    nil
  end

  # This retrieves the current value of the parent's field named in selector_for above
  def selector_field_value
    parent.record[selector_for] rescue nil
  end
      
  # If this widget is supposed to immediately select the first item in a list, set this to true
  # (This is useful for lists that are not that likely to have multiple entries, but for which there are children)
  # This should be false if nothing should be selected automatically, 'unique' if only a unique record should be
  # selected, 'exact' if an exact match to the search string should be selected, or just anything non-false
  # if the first available record should be selected.
  def select_on_load
    false
  end
  
  # UI for chosen and not chosen, can be overridden.
  def chosen_icon
    '<span class="ui-icon ui-icon-check" />'
  end

  def not_chosen_icon
    '<span class="ui-icon ui-icon-circle-arrow-w" />'
  end
  
  # This is the name of the choice mark column, can be overridden if needed.
  def choice_mark_column_name
    'choice_mark'
  end

  # UI for the chosen column header, can be overridden
  def choice_mark_column_icon
    '<span class="ui-icon ui-icon-link" />'
  end
  
  # STATES
  
  # For the moment, I'm just basically bypassing Apotomo's state transitions by allowing any state
  # to transition to any other state.  transition_all should include all of the states, transition_map is
  # defined off of that (and transition_map is what Apotomo itself consults).
  # TODO: Once this is all better defined, I should tighten this up probably, though it works as-is.
  def transitions_all
    [:_cell_click, :_edit_panel_submit, :_row_click, :_child_choice,
      :_child_updated, :_send_recordset, :_clear_recordset, :_set_filter,
      :_filter_display, :_filter_counts, :_setup, :_parent_selection, :_parent_unselection]
  end
  
  def transition_map
    {
      :_setup => ([:_setup] + transitions_all).uniq,
      :_send_recordset => ([:_send_recordset] + transitions_all).uniq,
      :_clear_recordset => ([:_clear_recordset] + transitions_all).uniq,
      :_cell_click => ([:_cell_click] + transitions_all).uniq,
      :_row_click => ([:_row_click] + transitions_all).uniq,
      :_edit_panel_submit => ([:_edit_panel] + transitions_all).uniq,
      :_child_updated => ([:_child_updated] + transitions_all).uniq,
      :_set_filter => ([:_set_filter] + transitions_all).uniq,
      :_filter_display => ([:_filter_display] + transitions_all).uniq,
      :_filter_counts => ([:_filter_counts] + transitions_all).uniq,
      :_parent_selection => ([:_parent_selection] + transitions_all).uniq,
      :_parent_unselection => ([:_parent_unselection] + transitions_all).uniq,
      :_child_choice => ([:_child_choice] + transitions_all).uniq,
    }
  end
  
  # Internal communications
  
  # State _row_click
  # This is triggered by a widget firing an :rowClick event.
  # The row click is intended to handle record selection in a list, only.
  # For actions that occur when a row is clicked on, refer to the :cellClick handler, which also fires.
  def _row_click
    select_record(param(:id))
  end
  
  # When a row is clicked, the controller's row selection handler gets the notification and sends it here.
  # This announces to the children that a record was selected, much as _send_recordsets does.
  def select_record(id)
    unless @record && @record.id == id #only announce if there was a change.
      if @record = resource_model.find_by_id(id)
        trigger(:recordSelected)
        return '>>' + js_select_id(id)
      else
        # @record = resource_model.new
        @record = scoped_model.new
        trigger(:recordUnselected)
      end
    end
    return ''
  end
  
  # Family communications
  
  # The parent widget has posted a record selected event.
  # If this is a subgrid-type child, then send the new recordset based on the selection.
  # If this is a selector-type child, then set the selection to the linked field.
  # TODO: Note, this might go badly for widgets with paginators, since it does not at present jump to the right page.
  def _parent_selection
    if selector_for
      return select_record(selector_field_value) + js_choose_id(selector_field_value)
    else
      jump_to_state :_send_recordset
    end
  end

  # The parent widget has posted a record unselected event.
  # If this is a subgrid-type child, then clear the recordset.
  # If this is a selector-type child, then clear the selection and resend the recordset.
  # TODO: The resending of the recordset is generally superfluous except for the initial page load.
  def _parent_unselection
    if selector_for
      jump_to_state :_send_recordset
    else
      jump_to_state :_clear_recordset
    end
  end
  
  # State _clear_recordset
  # This is called from a state jump from _parent_unselection.
  # It pushes an empty recordset into the JSON cache, then reloads the grid.
  # It also triggers a recordUnselected event of its own to let its children know.
  def _clear_recordset
    trigger(:recordUnselected)
    return '>>' + js_push_json_to_cache(empty_json) + js_reload_jqgrid
  end
    
  # This is called in the parent by the child to pick up the choice from the child.
  # TODO: Put the Javascript somewhere better if I can
  def update_choice(source, subrecord)
    if selector = @selectors[source]
      field, custom = selector
      resource_field = resource + '_' + field.to_s
      # TODO: If there happens to be a record, but the edit panel is closed (canceled), it should create a new one.
      unless @record
        @record = scoped_model.new
      end
      @record[field] = subrecord.id
      display_value = escape_javascript(self.send(custom, @record.clone))
      # Because I don't have access to address_to_event here, I stored the cell click url in the jqgrid.data
      return <<-JS
        ensureTitlePanel("##{@jqgrid_id}",jQuery('##{@jqgrid_id}').data('cell_click_url'));
        var f = jQuery("##{@jqgrid_id}").closest('.ui-jqgrid-view').find('.jqgw-form');
        f.find('#display_#{resource_field}').html('#{display_value}').effect('highlight');
        f.find('##{resource_field}').val('#{subrecord.id}');
        JS
    else
      return ''
    end
  end
  
  # State _child_updated
  # This is triggered by a child's :recordUpdated event.
  # This is the handler for :recordUpdated, which a child sends to a parent to request a reload, since
  # sometimes the child's data might be reflected in the parent table.  It just calls _send_recordset, but
  # without the superfluous downward message-passing, and with a preservation of the selection.
  # I'd use jump_to_state, but I'd have to set a transient instance variable to pass along the parameter.
  def _child_updated(inject_js = '')
    _send_recordset(false, inject_js)
  end
  
  # State _cell_click
  # This is triggered by a widget firing an :cellClick event.
  # If you want to do something other than open a panel here, override act_on_cell_click
  def _cell_click
    # I am going to try presuming that the row click handled the creation/location of the @record.
    # @record = scoped_model.find_by_id(param(:id)) || scoped_model.new
    act_on_cell_click(param(:cell_column))
  end
  
  # This is the main action for the _cell_click, it opens an edit panel.
  # You could have it do something else depending on the column by overriding it.
  # actions 'panel' and 'title_panel' are expecting html, 'choice' is expecting Javascript.
  def act_on_cell_click(col)
    emit = ''
    if col == 'row'
      case @row_action
      when 'title_panel', 'panel'
        emit = render :view => @row_object
      end
    else
      puts @columns.inspect
      case @columns[col.to_i][:action]
      when 'title_panel', 'panel'
        emit = render :view => @columns[col.to_i][:object]
      when 'choice'
        emit = js_choose_id(@record.id) + parent.update_choice(self.name, @record)
      else
        puts "UNRECOGNIZED CELL CLICK TYPE: " + @columns[col.to_i][:action].to_s
      end
    end
    return emit
  end
    
  # State _edit_panel_submit
  # This is the target of the edit panel's form submission.
  def _edit_panel_submit
    @record.update_attributes(param(param(:resource).to_sym))
    @record.save
    @record.reload # Be sure we get the id if this was a new record
    trigger(:recordSelected)
    # TODO: add some kind of feedback
    inject_js = <<-JS
      closeEditPanel('##{@jqgrid_id}');
    JS
    _child_updated(inject_js) # reload as if we got an updated message from a hypothetical child
  end
  
  # State _set_filter
  # This is triggered by clicking on a filter
  # This receives changes in the filter and deals with them.
  # Relies on strategic naming of the filter id to have the filter key first, followed by __.
  def _set_filter
    if param(:catid)
      catsplit = param(:catid).split('__')
      filter = catsplit[0]
      category_not_clicked = false
    else
      filter = param(:filter)
      category_not_clicked = true
    end
    new_filter = @filters.assoc(filter) ? filter : @filters.first[0]
    filter_unchanged = (@filter == new_filter)
    if param(:init)
      filter_unchanged = false
    end
    @filter = new_filter
    @subfilter = param(:subfilter) ? param(:subfilter) : {}
    redraw_filter = filter_unchanged ? '' : <<-JS
      jQuery('##{@jqgrid_id}_filter_header').find('.ui-state-highlight').removeClass('ui-state-highlight').addClass('ui-state-default');
      jQuery('##{@filter}__#{@jqgrid_id}_filter_category').addClass('ui-state-highlight');
      jQuery('.jqgw-filter-open').removeClass('jqgw-filter-open').slideUp('normal');
      jQuery('##{@jqgrid_id}_#{@filter}_filter_form').addClass('jqgw-filter-open').slideDown('normal');
    JS
    clear_checkboxes = (filter_unchanged && category_not_clicked) ? '' : <<-JS
      jQuery('##{@jqgrid_id}_#{@filter}_filter_form').find('input[type=checkbox]').attr('checked',false);
    JS
    return(_send_recordset(false, redraw_filter + clear_checkboxes))
  end

  # State _filter_display
  # This is triggered when the page is initially drawn, to fill in the filter div.
  # It is used by wire_filters in jqgrid_widget_helper
  def _filter_display
    render :view => '_filters'
  end

  # State _filter_counts (returns Javascript, called with jQuery.getScript)
  # This is triggered after the filters have been initially drawn
  # It is used by wire_filters in jqgrid_widget_helper
  # This will count the number of hits under each filter and then fill in the filter count span with the result.
  # I separated this out because I wanted it to be asynchronous and not slow down other activities.
  def _filter_counts
    js_emit = ''
    @filters.each do |filter|
      filter[1][:subfilters].to_a.each do |sf|
        sf[1][:options].to_a.each do |sfop|
          f, s, i, c, total_records = filter_prepare(filter[0], {sf[0] => {sfop[0] => '1'}})
          js_emit += "jQuery('##{@jqgrid_id}_#{filter[0]}_#{sf[0]}_#{sfop[0]}_count').html(#{total_records});"
        end
      end
    end
    js_emit
  end

  # SUPPORTING METHODS
  
  # descendents_to_reload creates a list of all descendants that have the select_on_load property set and so
  # might wind up having a selection automatically set.  The _setup state puts this in an instance variable
  # that the views can then use.
  def descendants_to_reload
    d = []
    if children_to_render.size > 0
      children_to_render.each do |c|
        if c.select_on_load
          d += c.descendants_to_reload
        end
        d += [c.jqgrid_dom_id]
      end
    end
    return d
  end
  
  # eager_load is a helper for an otherwise kind of esoteric-looking modification you can make
  # to the 'all' filter to include other tables in load_records.  You can do things like
  # eager_load(:show_type) or eager_load({:employee => :person}).
  # TODO: I might want to add a more global eager_load, so it doesn't need to be included in every
  # TODO: ...filter.  Same for conditions.
  # TODO: In the quest to reduce instance variables, note that I need @filters to be modifiable for this to work.
  def eager_load(tables, filter = 'all')
    @filters.assoc(filter)[1][:include] = [tables]
  end
  
  # add_column is a helper for constructing the table with _setup.
  # See http://www.secondpersonplural.ca/jqgriddocs/index.htm for more complete docs on jqGrid
  # I have changed some of the defaults here from what jgGrid does natively.
  # field is required, other things will be guessed if not provided.
  # field should correspond to the name of a field in the model if you are going to be doing any sorting on it.
  # And, if it doesn't, you'd better define a :custom for determining what its output should be.
  # This corresponds to jqGrid's 'index' parameter. It is the field identifier that is passed back for sorting.
  # Among the jqGrid options that are dealt with here:
  # :name => 'field' (default: same as 'index'; it's not clear to me why these are differentiated)
  # :label => 'Column header' (default: humanized field)
  # :width => width in pixels of the column (default: 100)
  # :search => enable search (in principle) on the column (not implemented elsewhere yet) (default false)
  # :sortable => enable sorting on the column (default false)
  # There are also some others, which will be passed along if provided (e.g. editoptions), so long as they are
  # formatted as Javascript.
  # The jqGridWidget itself has a couple of internal column options as well.
  # :custom => :method_name (method in cell definition to provide output for the cell, via self.send :method_name)
  # :action => 'row_panel', 'title_panel', or 'event' (or nothing, for no cell select action)
  # :object => name of partial to render (row_panel, title_panel) or something about the event.
  def add_column(field, options = {})
    # jqGrid options
    options[:index] = field
    options[:name] ||= field
    options[:label] ||= field.humanize
    options[:width] ||= 100
    options[:search] = false unless options.has_key?(:search)
    options[:sortable] = false unless options.has_key?(:sortable)
    # jqGridWidget options
    options[:action] ||= 'event'
    options[:object] ||= ''
    # options[:panel_under_row] = false unless options.has_key?(:panel_under_row)
    @columns << options
  end
  
  # This is a special add_column variant for adding a choice column with the standard options.
  # Use in place of add_column with _setup, note that it does not need a field name
  def add_choice_column(options = {})
    add_column(choice_mark_column_name, {:custom => :row_choice, :label => choice_mark_column_icon,
      :action => 'choice'}.merge(options))
  end
  
  # Standard custom method for choice marking.
  # The idea is that you set a column's :custom => :row_choice, and 
  def row_choice(row)
    return (selector_field_value == row.id) ? chosen_icon : not_chosen_icon
  end
    
  # RECORDSET PROCESSING

  # State _send_recordset (returns Javascript, called with jQuery.getScript)
  # This is called by the jQGrid data source function (retrieveJSON, defined in jqgrid_widget.js) if there
  # is no data already in the cache.  It should result in Javascript code to push the recordset into the cache
  # and then reload the grid (to pull it back out again).
  # The way this works is a little bit magical, it relies on the bundling done by Apotomo.
  # It triggers events that the children are listening for, and the children will emit their own Javascript.
  # Apotomo will then bundle all of this together before sending it back to the browser.
  #
  # This is also the handler for :recordSelected events sent by a parent to its children.
  # The children_unaware parameter is set to false if the child itself has triggered this (used in _child_updated).
  # If there was a record selected before, try to maintain that selection. However if the record is no longer there,
  # communicate to the children than they should reset.
  # TODO: It should be possible to add an id=@record.id to the conditions load_record uses to determine whether
  # the selection meets the new criteria, and if so, jump to the page it is on.  I of course need to make it possible
  # to leave that page, but I think if you do leave the page, then the selection should be reset.
  # TODO: Figure out how I can make it jump if the search string is an exact match.
  def _send_recordset(children_unaware = true, inject_js = '')
    records = load_records
    inject_js += js_push_json_to_cache(json_for_jqgrid(records)) + js_reload_jqgrid
    # If the children are aware, that means we arrived here just to do a refresh, no change in the filter.
    # However, that could still affect the records included in the parent recordset (if the child's change
    # means that the parent no longer meets the criteria).
    # Check to see if the selected record is still there.  If it is, nothing particular needs to be done,
    # jqGrid will maintain the UI selection.  If it's gone, we need to alert the children.
    # If select on load is set, either the first record or the unique record will be loaded.
    # Jump also if the setting is 'unique' but the search string would return an exact match among the records.
    # TODO: This is kind of clumsy, got a lot of conditionals here.
    # TODO: This isn't quite the right behavior.  It should check for an exact match even if the selection survived.
    # TODO: This also doesn't work when the exact match is off the page.  E.g., searching for TV show "er".
    selection_survived = (@record && records.include?(@record))
    unless selection_survived
      if @select_on_load
        if @select_on_load == 'unique'
          if records.size > 1
            if @livesearch
              records.each do |r|
                if r.attributes[@livesearch_field].downcase == @livesearch.downcase
                  select_record(r.id)
                  selection_survived = true
                end
              end
            end
          else
            if records.size == 1
              select_record(records.first.id)
                selection_survived = true
              end
          end
        else
          if records.size > 0
            select_record(records.first.id)
            selection_survived = true
          end
        end
        #   ((@select_on_load == 'unique' && records.size == 1) || (@select_on_load != 'unique' && records.size > 0))
        # select_record(records.first.id) # This posts a :recordSelected event to the children
        # inject_js += "console.log('#{@jqgrid_id}: recordSelected: #{@record.id}.');"
        # selection_survived = true
      else
        @record = scoped_model.new
        inject_js += js_select_id(nil)
        trigger(:recordUnselected) # Tell the children that we lost our selection
      end
    end
    if selection_survived
      inject_js += js_select_id(@record.id)
    end
    unless children_unaware
      trigger(:recordUpdated) # But in any event tell the parent to refresh if needed
    end    
    return '>>' + inject_js
  end
    
  # This returns the JSON data for the recordset, assumes records and pagination parameters have already been loaded
  def json_for_jqgrid(records)
    json = {
      :page => @page,
      :total => @total_pages, 
      :records => @total_records,
      :rows => grid_rows(records)
    }.to_json
  end
  
  # Turn @records into something appropriate for the json_for_jqgrid method
  def grid_rows(records)
    records.collect do |r|
      {
        :id => r.id,
        :cell => @columns.collect do |c|
          c[:custom] ? self.send(c[:custom], r) : (r.attributes)[c[:index]]
        end
      }
    end
  end
  
  # Note that I don't reset @livesearch here, which allows it to persist
  def get_paging_parameters
    @page = (param(:page) || @page || 1).to_i
    @rows_per_page = (param(:rows) || @rows_per_page || 20).to_i
    @sidx = (param(:sidx) || @sidx || @default_sidx)
    @sord = (param(:sord) || @sord || 'asc')
    # @search = (param(:_search) || @search || '')
    livesearch = param(:livesearch)
    if livesearch
      if (livesearch_split = livesearch.split('@',3)).size > 1
        if livesearch_split[0][0..(@jqgrid_id.size-1)] == @jqgrid_id
          @livesearch_field = livesearch_split[1]
          @livesearch = livesearch_split[2]
        end
      end
    end
  end
  
  # This is the actual method that queries the database.
  def load_records
    get_paging_parameters
    @filter, @subfilter, find_include, find_conditions, @total_records = filter_prepare
    find_order = @sortable_columns.include?(@sidx) ? (@sidx + ' ' + ((@sord == 'desc') ? 'DESC' : 'ASC')) :
      (@default_sidx ? @default_sidx + ' ASC' : nil)
    if @rows_per_page > 0
      @total_pages = (@total_records > 0 && @rows_per_page > 0) ? 1 + (@total_records/@rows_per_page).ceil : 0
      @page = @total_pages if @page > @total_pages
      @page = 1 if @page < 1
      @start_offset = @rows_per_page*@page - @rows_per_page
    else
      @total_pages = 1
      @rows_per_page = @total_records
      @start_offset = 0
    end
    if @start_offset < 0
      puts "??Why is start_offset negative?"
      @start_offset = 0
    end
    if @livesearch
      # Allow several partial matches by splitting the search string
      @livesearch.split(' ').each do |substring|
        find_conditions[0] += " and #{@livesearch_field} LIKE ?"
        find_conditions << "%#{substring}%"
      end
    end
    puts "Rows per page #{@rows_per_page}, offset #{@start_offset}, find_order #{find_order}, find_conditions #{find_conditions}, find_include #{find_include}."
    scoped_model.find(:all, :include => find_include, :conditions => find_conditions,
      :limit => @rows_per_page, :offset => @start_offset, :order => find_order)
  end
  
  # Prepare the instance variables for load_record, using the filter, returns things
  # used by load_records (but is also used without load_records to retrieve the
  # record counts for the individual filters)
  def filter_prepare(current_filter = @filter, subfilter = @subfilter)
    verified_filter = @filters.assoc(current_filter) ? current_filter : @filters.first[0]
    subfilter ||= {}
    filter = @filters.assoc(verified_filter)[1]
    # I had to do this in this kind of funny way to avoid actually modifying @filters.
    find_conditions = filter.has_key?(:conditions) ? filter[:conditions] : ['1']
    find_include = []
    # find_conditions += filter[:conditions] if filter.has_key?(:conditions)
    find_include += filter[:include] if filter.has_key?(:include)
    subfilter.each do |key, sf|
      # TODO: Could use some error checking in here.
      fsf = filter[:subfilters].assoc(key)[1]
      find_conditions[0] += (' and ' + fsf[:conditions]) if fsf.has_key?(:conditions)
      find_conditions << sf.keys
      find_include << fsf[:include] if fsf.has_key?(:include)
    end
    total_records = scoped_model.count(:all, :include => find_include, :conditions => find_conditions)
    # puts "%%%%% FILTER INFO IN FILTER_PREPARE: include:[#{find_include.inspect}], conditions:[#{find_conditions.inspect}]."
    return[verified_filter, subfilter, find_include, find_conditions, total_records]
  end
  
  # Constants and utilities

  def resource
    param(:resource)
  end
  
  def resource_model
    Object.const_get param(:resource).classify
  end

  def jqgrid_dom_id
    param(:jqgrid_id)
  end

  # Overriding apotomo::stateful_widget's method
  # No frame generated by the widget, assuming that relevant divs are generated elsewhere
  def frame_content(content)
    content
  end

  # The following functions define the Javascript calls that the widget generates.
  # If need be these can be redefined.
  
  # empty_json is a JSON structure for an empty dataset, suitable for pushing into the cache.
  def empty_json
    '{"rows": [], "records": 0, "page": 0, "total": 0}'
  end
  
  # Javascript to explicitly trigger a grid reload (which will preferentially draw from the cache)
  def js_reload_jqgrid(jqgrid_id = @jqgrid_id)
    return <<-JS
    jQuery('##{jqgrid_id}').trigger('reloadGrid');
    JS
  end
  
  # Javascript to set (or reset if no id is passed in) the selection in the jqgrid.
  # The jqGrid docs suggest that setSelection is actually a TOGGLE.  If this ever misbehaves,
  # then it might be good to first resetSelection and then setSelection.
  def js_select_id(id = nil)
    if id
      return <<-JS
      jQuery('##{@jqgrid_id}').setSelection('#{id}', false);
      JS
    else
      return <<-JS
      jQuery('##{@jqgrid_id}').resetSelection();
      JS
    end
  end

  # Javascript to set the choice mark on the jqGrid (unset all others), then reset.
  def js_choose_id(id = nil)
    if id
      return <<-JS
        var g = jQuery('##{@jqgrid_id}'),
        ids = g.getDataIDs();
        if (ids.length > 0) {
          for (id in ids) {
            g.setRowData(id,{'#{choice_mark_column_name}':(id=='#{id}')?('#{chosen_icon}'):('#{not_chosen_icon}')});
          }
        }
      JS
    else
      return ''
    end
  end
      
  # Javascript to push a JSON dataset into the cache to be used on the next reload.
  def js_push_json_to_cache(raw_json_data)
    json_data = escape_javascript(raw_json_data)
    return <<-JS
    pushJSON('##{@jqgrid_id}', "#{json_data}");
    JS
  end

end

