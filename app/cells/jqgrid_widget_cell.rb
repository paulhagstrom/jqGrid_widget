# TODO: One bug that remains is that the add button does not necessarily clear out the record.
# If something is selected, you wind up just editing that thing and not adding something.
class JqgridWidgetCell < Apotomo::StatefulWidget
  # JqgridWidgetCell is the heart of the jQGrid widget, an extension of Apotomo's StatefulWidget
  # TODO: Some documentation here.
  
  # In order to be able to do urlencoding, I bring in the Javascript helpers here.
  # TODO: I forget where I use this.  Is it really urlencoding?  Do I really still use it?  Check.
  include ActionView::Helpers::JavaScriptHelper 
  # Bring in address_to_event, since I use it here (though I might like to put it somewhere else)
  include Apotomo::ViewHelper
  
  helper :all
  # Make some of the methods defined here available to the view as well
  helper_method :js_reload_grid, :js_select_id, :js_push_json_to_cache, :empty_json
  helper_method :param
  # helper_method :selector_field_id
  # Make the JqgridWidgetHelper methods available to the view; these appear not to be noticed by helper :all
  helper JqgridWidget::JqgridWidgetHelper
  
  attr_reader :record  
  attr_reader :jqgrid_id  # descendants_to_reload asks for this from children

  # SETUP
  # Note: You might think that it would be sensible to put various things into an initialize method.
  # However, I found that initialize is called quite a lot, for some reason.  _setup is called once at
  # the beginning, so that seems to be the best place to do the real initialization.  See for yourself, if you'd like:
  # def initialize(*args)
  #   super(*args)
  #   puts "Hello from initialize: " + self.name.to_s
  # end
  
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
  #   render
  # end
  # TODO: Perhaps later I may want to be able to make the default filter not be the first one?
  def _setup
    # puts "Hello from setup: " + self.name.to_s
    @jqgrid_id = @opts[:jqgrid_id]
    @is_top_widget = @opts[:top_widget] || false
    # jqgrid_options can include:
    # :caption => printable plural form of resource (default 'Records')
    # :pager
    # :pager_id
    # :height
    # :collapsed
    # :url
    # :initial_sort
    # :add_button (default false)
    # :collapse_if_empty => true (default false)
    # :single_record_caption => <js> (default false) 
    #  This is a small Javascript snipped with 'row' available.  E.g.,
    #  :single_record_caption => "'Degree track: ' + row.name"
    # :row_action (default title_panel) determines where the edit panel appears. panel for under row.
    # :row_object (default _panel) is the partial to render when a row is clicked
    @jqgrid_options = {
      :row_action => 'title_panel',
      :row_object => '_panel',
      :caption => resource.pluralize.humanize #'Records'
    }

    # The default filter is 'all'.
    @filters = [['all', {:name => 'All'}]]
        
    @record = scoped_model.new
    
    @columns  = []
    
    yield self if block_given?
    
    @sortable_columns = (@columns.map {|c| c[:sortable] ? c[:index] : nil}).compact
    @default_sidx = (@columns.map {|c| c[:sortable] == 'default' ? c[:index] : nil}).compact.first
  end
  
  # Things you may want to override
  
  # To load a recordset for the table in this widget, a find call is passed to the scoped_model.
  # If this is a top widget, it is appropriate to leave it as resource_model.  If this is a
  # child widget, this can be something like parent.records.contacts (or, you have defined a named scope,
  # that could also go here).  You can rely on records being an attribute of parent.
  def scoped_model
    resource_model
  end

  # select_on_load determines whether the first item in a list should be selected.
  # There are a couple of situations in which this might be desired.  One is for a one-to-many relationship
  # where it is relatively unusual for the relationship to exceed one-to-one.  In this case, you might
  # prefer to just display the value rather than have all of the screen real estate taken by table overhead.
  # In this case, see also the @jqgrid_options[:single_record_caption], where the display can be configured.
  # Tne automatic selection is accomplished by setting select_on_load to true.
  # The other case is when the recordset is being narrowed by a search field.  If select_on_load is 'unique'
  # then the single record left matching the search string will be selected (as soon as it is unique).
  # If select_on_load is `exact' then if an exact match is found (unique or not), it will be selected.
  # To imagine the difference, suppose you are searching for the television show "ER".  Good luck.  You
  # won't get a unique match, but you could get an exact one in there.  Probably most of the time the
  # desired behavior is going to be 'exact'.  'Exact' does imply 'unique' (exact match will be selected
  # when non-unique, but if the list goes down to one member, the one member will be selected).
  def select_on_load
    false
  end

  # If a child widget is serving as a glorified popup menu, where the selection in the child table
  # determines the value of a field in the parent, then set selector_for for the child table to be
  # the field (of the child) from which the id is drawn.  As a symbol.  Like :thingie_id.
  # Returning nil means that the child is showing something like a one-to-many relation.
  # TODO: This could potentially be drawn from information about has_many or belongs_to settings in
  # the model.  But setting it explicitly is ok for now.
  def selector_for
    nil
  end

  # If selector_for is set, selector_field_value is used to determine what the parent's
  # field is set to (the currently selected record).
  def selector_field_value
    parent.record[selector_for] rescue nil
  end
      
  # UI definitions.  Can be overridden if desired.
  
  # Chosen and not chosen.
  def chosen_icon
    '<span class="ui-icon ui-icon-check" />'
  end

  def not_chosen_icon
    '<span class="ui-icon ui-icon-circle-arrow-w" />'
  end
  
  # This is the name of the choice mark column, can be overridden if needed.
  # (The choice mark column is the place where the choice_mark_column_icon, below, goes.
  # The idea is that this indicates which is currently chosen.  It might be different
  # from what is actually selected in the table.)
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
  # As far as I know, a transition can only be made if it is on the map, which is why I want to be able
  # to go to anywhere from anywhere.  Limiting this doesn't seem like it will add much.
  # TODO: Once this is all better defined, I should tighten this up probably, though it works as-is.
  def transitions_all
    [:_cell_click, :_edit_panel_submit, :_row_click, :_child_choice, :_delete_record,
      :_child_updated, :_send_recordset, :_set_filter,
      :_filter_display, :_filter_counts, :_setup, :_parent_selection, :_parent_unselection]
  end
  
  def transition_map
    {
      :_setup => ([:_setup] + transitions_all).uniq,
      :_send_recordset => ([:_send_recordset] + transitions_all).uniq,
      :_cell_click => ([:_cell_click] + transitions_all).uniq,
      :_row_click => ([:_row_click] + transitions_all).uniq,
      :_edit_panel_submit => ([:_edit_panel_submit] + transitions_all).uniq,
      :_delete_record => ([:_delete_record] + transitions_all).uniq,
      :_child_updated => ([:_child_updated] + transitions_all).uniq,
      :_set_filter => ([:_set_filter] + transitions_all).uniq,
      :_filter_display => ([:_filter_display] + transitions_all).uniq,
      :_filter_counts => ([:_filter_counts] + transitions_all).uniq,
      :_parent_selection => ([:_parent_selection] + transitions_all).uniq,
      :_parent_unselection => ([:_parent_unselection] + transitions_all).uniq,
      :_child_choice => ([:_child_choice] + transitions_all).uniq,
    }
  end
  
  # Communications
  
  # State _row_click
  # This is triggered by a widget firing an :rowClick event.
  # The row click is intended to handle record selection in a list, only.
  # For actions that occur when a row is clicked on, refer to the :cellClick handler, which also fires.
  def _row_click
    render :js => select_record_js(param(:id))
  end
  
  # When a row is clicked, the controller's row selection handler gets the notification and sends it here.
  # This announces to the children that a record was selected, much as _send_recordsets does.
  # This returns Javascript suitable for rendering (and depends on render :js => '' to be harmless).
  def select_record_js(id)
    unless @record && @record.id == id #only announce if there was a change.
      if @record = scoped_model.find_by_id(id)
        trigger(:recordSelected)
        return js_select_id(id)
      else
        @record = scoped_model.new
        trigger(:recordUnselected)
      end
    end
    return ''
  end
    
  # The parent widget has posted a record selected event.
  # If this is a subgrid-type child, then send the new recordset based on the selection.
  # If this is a selector-type child, then set the selection to the linked field.
  # TODO: Note, this might go badly for widgets with paginators, since it does not at present jump to the right page.
  # TODO: For the moment, consider this to be only compatible with selector-type children that have no paginator.
  def _parent_selection
    if selector_for
      render :js => select_record_js(selector_field_value) + js_choose_id(selector_field_value)
    else
      render :js => update_recordset_js
    end
  end

  # The parent widget has posted a record unselected event.
  # If this is a subgrid-type child, then clear the recordset.
  # If this is a selector-type child, then clear the selection and resend the recordset.
  # TODO: The resending of the recordset is generally superfluous except for the initial page load.
  # TODO: In the future maybe I could check to see if the recordset is empty and resend only if it is?
  def _parent_unselection
    trigger(:recordUnselected)
    if selector_for
      @record = scoped_model.new
      render :js => update_recordset_js
    else
      render :js => js_push_json_to_cache(empty_json) + js_reload_jqgrid
    end
  end
      
  # State _child_updated
  # This is triggered by a child's :recordUpdated event.
  # This is the handler for :recordUpdated, which a child sends to a parent to request a reload, since
  # sometimes the child's data might be reflected in the parent table.
  def _child_updated
    render :js => update_recordset_js(false)
  end
  
  # State _cell_click
  # This is triggered by a widget firing an :cellClick event.
  # You could have it do something else depending on the column by overriding it.
  # actions 'panel' and 'title_panel' are expecting html, 'choice' is expecting Javascript.
  def _cell_click
    # I am going to try presuming that the row click handled the creation/location of the @record.
    # @record = scoped_model.find_by_id(param(:id)) || scoped_model.new
    col = param(:cell_column)
    if col == 'row'
      case @jqgrid_options[:row_action]
      when 'title_panel', 'panel'
        render :view => @jqgrid_options[:row_object]
      else
        puts "CELL CLICK FOR ROW, BUT NO ROW ACTION."
        render :nothing => true
      end
    else
      # puts @columns.inspect
      case @columns[col.to_i][:action]
      when 'title_panel', 'panel'
        render :view => @columns[col.to_i][:object]
      when 'choice'
        render :js => js_choose_id(@record.id) + parent.update_choice_js(self.name, @record)
      else
        puts "UNRECOGNIZED CELL CLICK TYPE: " + @columns[col.to_i][:action].to_s
        render :nothing => true
      end
    end
  end
      
  # State _edit_panel_submit
  # This is the target of the edit panel's form submission.
  # Updates or adds the record, reselects it, and alerts children and parents.
  def _edit_panel_submit
    @record.update_attributes(param(@opts[:resource].to_sym))
    @record.save
    @record.reload # Be sure we get the id if this was a new record
    trigger(:recordUpdated)
    trigger(:recordSelected)
    # TODO: add some kind of feedback
    # Perhaps do this in the form of triggering a feedback event that a feedback widget watches.
    # Alternatively, I can inject js to replace a feedback div's content.
    js_emit = <<-JS
      closeEditPanel('##{@jqgrid_id}');
    JS
    # reload as if we got an updated message from a hypothetical child
    render :js => js_emit + update_recordset_js(false)
  end

  # State _delete_record
  # We arrive here from an event triggered by the delete button
  def _delete_record
    @record.destroy
    @record = scoped_model.new
    js_emit = <<-JS
      closeEditPanel('##{@jqgrid_id}');
    JS
    js_emit += js_select_id(nil)
    trigger(:recordUpdated)
    trigger(:recordUnselected)
    render :js => js_emit + update_recordset_js(false)
  end
  
  # State _send_recordset (returns Javascript, called with jQuery.getScript)
  # This is called by the jQGrid data source function (retrieveJSON, defined in jqgrid_widget.js) if there
  # is no data already in the cache.  It should result in Javascript code to push the recordset into the cache
  # and then reload the grid (to pull it back out again).
  def _send_recordset
    render :js => update_recordset_js
  end

  # Provide Javascript code to push the recordset into the cache
  # and then reload the grid (to pull it back out again).
  #
  # This is also the handler for :recordSelected events sent by a parent to its children.
  # The children_unaware parameter is set to false if the child itself has triggered this (used in _child_updated).
  # If there was a record selected before, try to maintain that selection. However if the record is no longer there,
  # communicate to the children than they should reset.
  # TODO: It should be possible to add an id=@record.id to the conditions load_record uses to determine whether
  # the selection meets the new criteria, and if so, jump to the page it is on.  I of course need to make it possible
  # to leave that page, but I think if you do leave the page, then the selection should be reset.
  # TODO: Figure out how I can make it jump if the search string is an exact match.
  def update_recordset_js(children_unaware = true)
    records = load_records
    js_emit = js_push_json_to_cache(json_for_jqgrid(records)) + js_reload_jqgrid
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
    if selection_survived
      js_emit += js_select_id(@record.id)
      # if children_unaware
      #   trigger(:recordSelected) 
      # end
    else
      if select_on_load
        if records.size > 1
          if select_on_load == 'exact'
            if @livesearch
              records.each do |r|
                if r.attributes[@livesearch_field].downcase == @livesearch.downcase
                  js_emit += select_record_js(r.id)
                  selection_survived = true
                end
              end
            end
          else
            unless select_on_load == 'unique'
              # select first
              js_emit += select_record_js(records.first.id)
              selection_survived = true
            end
          end
        else
          if records.size == 1
            js_emit += select_record_js(records.first.id)
            selection_survived = true
          end
        end
      end
      if selection_survived
        trigger(:recordSelected)
      else
        @record = scoped_model.new
        js_emit += js_select_id(nil)
        trigger(:recordUnselected) # Tell the children that we lost our selection
      end
    end
    return js_emit
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
    redraw_filter = filter_unchanged ? '' : js_redraw_filter
    clear_checkboxes = (filter_unchanged && category_not_clicked) ? '' : <<-JS
      jQuery('##{@jqgrid_id}_#{@filter}_filter_form').find('input[type=checkbox]').attr('checked',false);
    JS
    render :js => redraw_filter + clear_checkboxes + update_recordset_js(false)
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
    render :js => js_emit
  end

  # This is called in the parent by the child to pick up the choice from the child.
  # TODO: Put the Javascript somewhere better if I can
  def update_choice_js(source, subrecord)
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
        d += [c.jqgrid_id]
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
    @filters.assoc(filter)[1][:include] = (tables.is_a?(Array) ? tables : [tables])
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
  # The idea is that you set a column's :custom => :row_choice, and you're done.  That's done by add_choice_column.
  def row_choice(row)
    return (selector_field_value == row.id) ? chosen_icon : not_chosen_icon
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
    @rows_per_page = (param(:rows) || @rows_per_page || @jqgrid_options[:rows_per_page] || 20).to_i
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
  # TODO: Subfilter includes are not working.  Decide whether they should be fixed or support removed.
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
    @opts[:resource]
  end
  
  def resource_model
    Object.const_get @opts[:resource].classify
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

  # Javeascript to redraw a filter
  def js_redraw_filter
    return <<-JS
    jQuery('##{@jqgrid_id}_filter_header').find('.ui-state-highlight').removeClass('ui-state-highlight').addClass('ui-state-default');
    jQuery('##{@filter}__#{@jqgrid_id}_filter_category').addClass('ui-state-highlight');
    jQuery('.jqgw-filter-open').removeClass('jqgw-filter-open').slideUp('normal');
    jQuery('##{@jqgrid_id}_#{@filter}_filter_form').addClass('jqgw-filter-open').slideDown('normal');
    JS
  end
    
end

