class JqgridWidgetCell < Apotomo::StatefulWidget
  include ActionView::Helpers::JavaScriptHelper 
  helper JqgridWidget::JqgridWidgetHelper
  require 'jquery_apotomo_helper_methods'
  # include PatchApotomoWidgetIvars

  # Current state: There is now an advisor panel.  It has some quirks, and I don't think it can save yet.
  # Certinaly it doesn't show the kinds of information one might want, like counts of the advisor assignments for different advisors.
  # TODO: Clicking on the panel on employee_section only brings up an Add panel (not Edit)
  # TODO: Lots of stuff wrt the filters is working.  One thing that seems not to is that the selection is preserved when the filter is
  # TODO: ...chosen, and so if the selected record is no longer in the list, it becomes sad and throws an innerHTML error.
  # TODO: Meanwhile the selection is not preserved when the list is sorted.
  # TODO: This could use some cleanup again.  I've now phased out all non-bundled data, which means I don't need to refer to it anymore.
  # TODO: Figure out some more elegant way to handle record associations.  Include everything by default?
  # TODO: Allow deleting of records.  The icon is there and perhaps all I need to do is set the jqgrid url.
  # TODO: Bring live search back.
  # TODO: The person add button doesn't do anything.
  
  helper :all
  helper_method :js_reload_grid, :js_select_id, :js_push_json_to_cache, :empty_json
  
  attr_reader :record
  attr_reader :jqgrid_id
    
  # TODO: I'm not certain I'm using this correctly. In particular, I'm not sure about automatic advancement of
  # TODO: states.  I think the states may auto-advance to the first in the list if there is no explicit jump,
  # TODO: and that may not be what I'm after.  Maybe I should introduce a "resting state"?
  # For the moment I'll leave it open like this, but I might want to pare it down.  (Though, why?)
  def transitions_all
    [:_json_for_jqgrid, :_edit_panel, :_edit_panel_submit,
      :_reflect_child_update, :_send_recordset, :_clear_recordset, :_set_filter,
      :_filter_display, :_filter_counts, :_setup]
  end
  
  def transition_map
    {
      :_setup => ([:_json_for_jqgrid] + transitions_all).uniq,
      :_send_recordset => ([:_send_recordset] + transitions_all).uniq,
      :_clear_recordset => ([:_clear_recordset] + transitions_all).uniq,
      :_json_for_jqgrid => ([:_json_for_jqgrid] + transitions_all).uniq,
      :_edit_panel => ([:_edit_panel] + transitions_all).uniq,
      :_edit_panel_submit => ([:_edit_panel] + transitions_all).uniq,
      :_reflect_child_update => ([:_reflect_child_update] + transitions_all).uniq,
      :_set_filter => ([:_set_filter] + transitions_all).uniq,
      :_filter_display => ([:_filter_display] + transitions_all).uniq,
      :_filter_counts => ([:_filter_counts] + transitions_all).uniq,
    }
  end
  
  def scoped_model
    # just resource_model for the top widget; for children, use something like parent.records.contacts
    # or, if you have a named scope, you can put that here.
    resource_model
  end

  # If this widget is supposed to immediately select the first item in a list, set this to true
  # (This is useful for lists that are not that likely to have multiple entries, but for which there are children)
  # This should be false if nothing should be selected automatically, 'unique' if only a unique record should be
  # selected, 'exact' if an exact match to the search string should be selected, or just anything non-false
  # if the first available record should be selected.
  def select_on_load
    false
  end
  
  # descendents_to_reload will reload all descendants if there is even a chance that a record could be selected.
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
  
  def empty_json
    '{"rows": [], "records": 0, "page": 0, "total": 0}'
  end
  
  def js_reload_jqgrid(jqgrid_id = @jqgrid_id)
    return <<-JS
    jQuery('##{jqgrid_id}').trigger('reloadGrid');
    JS
  end
  
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
  
  def js_push_json_to_cache(raw_json_data)
    json_data = escape_javascript(raw_json_data)
    return <<-JS
    pushJSON('##{@jqgrid_id}', "#{json_data}");
    JS
  end
  
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
  # @records_per_page (in principle the number of records per page when using paginator, not tested)
  # @row_panel (partial to render when a row is clicked, defaults to 'panel')
  # @row_panel_under_row (true if the panel should render under the row clicked on, defaults to false)
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
    @caption = 'Records'
    @collapse_if_empty = false
    @single_record_caption = false
    # @single_record_caption is a small Javascript snippet, can make use of 'row' variable.
    # for example: @single_record_caption = "'Degree track: ' + row.name"
    @find_include = nil
    
    @filters = [['all', {:name => 'All'}]]
    
    @columns  = []
    @row_panel = '_panel'
    @row_panel_under_row = false
    
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
    @column_indices = @columns.map {|c| c[:index]}
    
    @record = resource_model.new
    
    yield self if block_given?
    
    nil
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
  # :panel => name of partial to render for a cell_select form, or '' for no trigger there.
  # :panel_under_row => true if the edit panel should render under the row (otherwise it will be in the title area)
  def add_column(field, options = {})
    # jqGrid options
    options[:index] = field
    options[:name] ||= field
    options[:label] ||= field.humanize
    options[:width] ||= 100
    options[:search] = false unless options.has_key?(:search)
    options[:sortable] = false unless options.has_key?(:sortable)
    # jqGridWidget options
    options[:panel] ||= ''
    options[:panel_under_row] = false unless options.has_key?(:panel_under_row)
    @columns << options
  end
    
  # This is the state called as the jQGrid data source.  The data of this widget and its children are bundled together
  # in a series of Javascript commands that put the data in the cache and then tell the jqgrid to reload.
  # The way this works is by triggering events that the children are listening for, each of whom will return
  # their own Javascript.
  # This is also the handler for :recordSelected events sent by a parent to its children.
  # The children_unaware parameter is set to false if the child itself has triggered this (used in _reflect_child_update).
  # If there was a record selected before, try to maintain that selection. However if the record is no longer there,
  # communicate to the children than they should reset.
  # TODO: It should be possible to add an id=@record.id to the conditions load_record uses to determine whether
  # the selection meets the new criteria, and if so, jump to the page it is on.  I of course need to make it possible
  # to leave that page, but I think if you do leave the page, then the selection should be reset.
  # TODO: Figure out how I can make it jump if the search string is an exact match.
  def _send_recordset(children_unaware = true, inject_js = '')
    records = load_records
    inject_js += js_push_json_to_cache(_json_for_jqgrid(records)) + js_reload_jqgrid
    # inject_js += js_push_json_to_cache(_json_for_jqgrid) + js_reload_jqgrid
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
              # puts "%%%%%%%%%%%%%% Unique check for exact match. Match to [#{@livesearch}] on [#{@livesearch_field}]"
              records.each do |r|
                # puts "%% record #{r.id}, attributes: #{r.attributes.inspect}"
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
        @record = resource_model.new
        # inject_js += "console.log('#{@jqgrid_id}: recordUnselected.');"
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
    
  # When a row is clicked, the controller's row selection handler gets the notification and sends it here.
  # This announces to the children that a record was selected, much as _send_recordsets does.
  # TODO: This is redundantly checked for in the Javascript, perhaps it is not worth also checking here for a change.
  def select_record(id)
    unless @record && @record.id == id #only announce if there was a change.
      @record = resource_model.find_by_id(id)
      trigger(:recordSelected)
    end
  end
  
  # This is the handler for :recordUnselected events sent by parents to children, it stuffs an empty recordset into
  # the cache and then reloads.
  def _clear_recordset
    trigger(:recordUnselected) # Keep passing the word down the tree
    return '>>' + js_push_json_to_cache(empty_json) + js_reload_jqgrid
  end
  
  # This is the handler for :recordUpdated, which a child sends to a parent to request a reload, since
  # sometimes the child's data might be reflected in the parent table.  It just calls _send_recordset, but
  # without the superfluous downward message-passing, and with a preservation of the selection.
  # I'd use jump_to_state, but I'd have to set a transient instance variable to pass along the parameter.
  def _reflect_child_update(inject_js = '')
    _send_recordset(false, inject_js)
  end
  
  # This is a state that returns the JSON data for the recordset.
  # It is no longer suitable for serving as a jqGrid data source because it requires the records to
  # have been loaded first (as well as the pagination parameters)
  def _json_for_jqgrid(records)
    # @page = (param(:page) || @page || 1).to_i
    # @rows_per_page = (param(:rows) || @rows_per_page || 20).to_i
    # @sidx = (param(:sidx) || @sidx || 'name')
    # @sord = (param(:sord) || @sord || 'asc')
    # @search = (param(:_search) || @search || '')
    # @livesearch = (param(:_livesearch) || @livesearch || '')
    # records = load_records
    json = {
      :page => @page,
      :total => @total_pages, 
      :records => @total_records,
      :rows => grid_rows(records)
    }.to_json
  end
  
  # Turn @records into something appropriate for the _json_for_jqgrid method
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
    @sidx = (param(:sidx) || @sidx || 'name')
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
  # TODO: This is not working, it seems to be returning too many results.
  def load_records
    get_paging_parameters
    @filter, @subfilter, find_include, find_conditions, @total_records = filter_prepare
    sord = (@sord == 'desc') ? 'DESC' : 'ASC'
    sidx = (@column_indices.include?(@sidx) ? @sidx : @columns[0][:index])
    find_order = "#{sidx} #{sord}"
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
  
  # This is the state that is invoked when an edit panel is to be displayed.
  def _edit_panel
    @record = scoped_model.find_by_id(param(:id)) || scoped_model.new
    if param(:panel) == 'row'
      panel = @row_panel
    else
      panel = @columns[param(:panel).to_i][:panel]
    end
    render :view => panel
    # state_view! panel
  end

  def _edit_panel_submit
    @record.update_attributes(param(param(:resource).to_sym))
    @record.save
    @record.reload # Be sure we get the id if this was a new record
    trigger(:recordSelected)
    # TODO: add some kind of feedback
    inject_js = <<-JS
      closeEditPanel('##{@jqgrid_id}');
    JS
    _reflect_child_update(inject_js) # reload as if we got an updated message from a hypothetical child
  end
  
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

  # This redraws the whole filter div
  def _filter_display
    render :view => '_filters'
    # state_view! '_filters'
  end
  
  # Return counts for all of the filter options
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

end

