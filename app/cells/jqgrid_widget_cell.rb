class JqgridWidgetCell < Apotomo::StatefulWidget
  include ActionView::Helpers::JavaScriptHelper 
  helper JqgridWidget::JqgridWidgetHelper
  require 'jquery_apotomo_helper_methods'

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
    [:_json_for_jqgrid, :_new_parent_record, :_new_parent_record_prepare, :_edit_panel, :_edit_panel_submit,
      :_reflect_child_update, :_send_recordset, :_send_recordset_bundle, :_clear_recordset, :_set_filter,
      :_filter_display, :_filter_counts]
  end
  
  def transition_map
    {
      :_setup => ([:_json_for_jqgrid] + transitions_all).uniq,
      :_send_recordset => ([:_send_recordset] + transitions_all).uniq,
      :_send_recordset_bundle => ([:_send_recordset_bundle] + transitions_all).uniq,
      :_clear_recordset => ([:_clear_recordset] + transitions_all).uniq,
      :_json_for_jqgrid => ([:_json_for_jqgrid] + transitions_all).uniq,
      :_new_parent_record => ([:_new_parent_record_prepare] + transitions_all).uniq,
      :_new_parent_record_prepare => ([:_new_parent_record_prepare] + transitions_all).uniq,
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
    resource_model
  end

  # If this widget is supposed to immediately select the first item in a list, set this to true
  # (This is useful for lists that are not that likely to have multiple entries, but for which there are children)
  def select_first_on_load
    false
  end
  
  def descendants_to_reload
    d = []
    if children_to_render.size > 0
      children_to_render.each do |c|
        if c.select_first_on_load
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
    @jqgrid_id = jqgrid_dom_id
    @descendants_to_reload = descendants_to_reload
    @select_first_on_load = select_first_on_load
    @prefix = param(:prefix)
    @is_top_widget = param(:top_widget)
    @column_indices = @columns.map {|c| c[:index]}
    
    @record = resource_model.new
    
    yield self if block_given?
    
    nil
  end
  
  # add_column is a helper for constructing the table with _setup.
  # field is required
  # I'm not actually certain at the moment about what all the jqgrid options do.
  # It will try to guess reasonable things based on the name, but you can override them.
  # :label => 'Column header' (default: humanized field)
  # :custom => :method_name (method in cell definition to provide output for the cell, via self.send :method_name)
  # :panel => name of partial to render for a cell_select form, or '' for no trigger there.
  # :row_panel => true if the partial is supposed to render under the row (otherwise will render in the title area)
  def add_column(field, opts = {})
    opts[:field] = field
    opts[:name] = "'#{field}'"
    opts[:label] ||= field.humanize
    opts[:index] ||= "'#{field}'"
    opts[:label] = "'#{opts[:label]}'"
    opts[:width] ||= 100
    opts[:search] = (opts[:search] && opts[:search] != 'false') ? 'true' : 'false'
    opts[:sortable] = (opts[:sortable] && opts[:sortable] != 'false') ? 'true' : 'false'
    opts[:panel] ||= ''
    opts[:panel_under_row] = false
    @columns << opts
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
  def _send_recordset(children_unaware = true, inject_js = '')
    inject_js += js_push_json_to_cache(_json_for_jqgrid) + js_reload_jqgrid
    # inject_js += js_push_json_to_cache(_json_for_jqgrid) + js_reload_jqgrid
    # If the children are aware, that means we arrived here just to do a refresh, no change in the filter.
    # However, that could still affect the records included in the parent recordset (if the child's change
    # means that the parent no longer meets the criteria).
    # Check to see if the selected record is still there.  If it is, nothing particular needs to be done,
    # jqGrid will maintain the UI selection.  If it's gone, we need to alert the children.
    selection_survived = (@record && @records.include?(@record))
    unless selection_survived
      if @select_first_on_load && @records.size > 0
        select_record(@records.first.id) # This posts a :recordSelected event to the children
        # inject_js += "console.log('#{@jqgrid_id}: recordSelected: #{@record.id}.');"
        selection_survived = true
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
  # The way I have it set up right now, this is never called directly from outside, though it in principle
  # could be if for some reason one wanted to bypass the cache.
  def _json_for_jqgrid
    @page = (param(:page) || @page || 1).to_i
    @rows_per_page = (param(:rows) || @rows_per_page || 20).to_i
    @sidx = (param(:sidx) || @sidx || 'name')
    @sord = (param(:sord) || @sord || 'asc')
    @search = (param(:_search) || @search || '')
    @livesearch = (param(:_livesearch) || @livesearch || '')
    load_records
    json = {
      :page => @page,
      :total => @total_pages, 
      :records => @total_records,
      :rows => @grid_rows
    }.to_json
  end
  
  # This is the actual method that queries the database.
  # TODO: This is not working, it seems to be returning too many results.
  def load_records
    @filter, @subfilter, find_include, find_conditions, @total_records = filter_prepare
    sord = (@sord == 'desc') ? 'DESC' : 'ASC'
    sidx = (@column_indices.include?(@sidx) ? @sidx : @columns[0][:field])
    find_order = "#{sidx} #{sord}"
    if @rows_per_page > 0
      @total_pages = (@total_records > 0 && @rows_per_page > 0) ? @total_records/@rows_per_page : 0
      @page = @total_pages if @page > @total_pages
      @start_offset = @rows_per_page*@page - @rows_per_page
    else
      @total_pages = 1
      @rows_per_page = @total_records
      @start_offset = 0
    end
    # if @livesearch
    #   find_conditions[0] += ' and name LIKE ?'
    #   find_conditions << "%#{param(:name)}%"
    # end
    @records = scoped_model.find(:all, :include => find_include, :conditions => find_conditions,
      :limit => @rows_per_page, :offset => @start_offset, :order => find_order)
    @grid_rows = @records.collect do |r|
      {
        :id => r.id,
        :cell => @columns.collect do |c|
          c[:custom] ? self.send(c[:custom], r) : (r.attributes)[c[:field]]
        end
      }
    end
  end
  
  # Prepare the instance variables for load_record, using the filter, returns things
  # used by load_records (but is also used without load_records to retrieve the
  # record counts for the individual filters)
  def filter_prepare(current_filter = @filter, subfilter = @subfilter)
    verified_filter = @filters.assoc(current_filter) ? current_filter : @filters.first[0]
    subfilter ||= {}
    filter = @filters.assoc(verified_filter)[1]
    # I had to do this in this kind of funny way to avoid actually modifying @filters.
    find_conditions = []
    find_include = []
    find_conditions += filter[:conditions] if filter.has_key?(:conditions)
    find_include += filter[:include] if filter.has_key?(:include)
    subfilter.each do |key, sf|
      # TODO: Could use some error checking in here.
      fsf = filter[:subfilters].assoc(key)[1]
      find_conditions[0] += ' and ' + fsf[:conditions]
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
    state_view! panel
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
    state_view! '_filters'
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

#   
#   # override this to construct the list out of the passed-in records
#   
#   def construct_list(records = [])
#     records_formatted = []
#     return records_formatted
#   end
#   
#   # This should be called when a loadList event is posted
#   def _load_list
#     page, limit, sidx, sord, search, livesearch = 
#       params[:page].to_i, params[:rows].to_i, params[:sidx], params[:sord], params[:_search], params[:_livesearch]
#     sidx ||= '1'
#     sord ||= 'asc'
#     if (search == 'true' || livesearch == 'true')
#       records = Person.find(:all, :order => sidx + ' ' + sord, :conditions => ['name LIKE ?', "%#{params[:name]}%"])      
#     else
#       records = Person.find(:all, :order => sidx + ' ' + sord)
#     end
#     count = records.size
#     total_pages = (count > 0 and limit > 0) ? count/limit : 0
#     page = total_pages if page > total_pages
#     start = limit*page - limit
#     records_formatted = construct_list(records)
#     @json_out = {:page => page, :total => total_pages, :records => count, :rows => records_formatted}
#     # $SQL = "SELECT a.id, a.invdate, b.name, a.amount,a.tax,a.total,a.note FROM invheader a, clients b WHERE a.client_id=b.client_id ORDER BY $sidx $sord LIMIT $start , $limit";
#     # respond_to do |format|
#     #   format.json {render :json => @json_out}
#     # end
#     # How am I going to get this to render json?  I'll hope it is asking for it.
#     return @json_out.to_json
#   end
#   
#   # # If this widget has another of this type of widget in its detail panel, some things can be dealt with
#   # # automatically if they are listed here.  Format: {'author' => :author_id, 'publisher' => :publisher_id}
#   # # TODO: Maybe I can get it to actually use the models and associations, that would be better than hardwiring it.
#   # def child_panels
#   #   {}
#   # end
# 
#   # # The filters have the form key => {:name => 'Display Name', :conditions => conditions clause for find}
#   # def filters_available
#   #   {
#   #     'all' => {:name => 'All', :conditions => nil},
#   #   }
#   # end
# 
#   # # The filter default is the key of the filter to use if none has been specifically selected
#   # def filter_default
#   #   'all'
#   # end
# 
#   # This is the :include parameter for the find that loads the recordset if using load_records below
#   # If you have related subtables of author and publisher, for example, then you can do this:
#   # def resources_include
#   #   [:author, :publisher]
#   # end
#   # def resources_include
#   #   nil
#   # end
# 
#   # This is the :order parameter for the find that loads the recordset if using load_records below
#   # def resources_default_order
#   #   'authors.name, books.title'
#   # end
#   # def resources_default_order
#   #   nil
#   # end
# 
#   # This loads the records in order to display the list, uses parameters set above
#   def load_records(conditions = nil)
#     find_params = {:conditions => conditions}
#     find_params.merge!({:include => resources_include}) if resources_include
#     find_params.merge!({:order => resources_default_order}) if resources_default_order
#     @records = resource_model.find(:all, find_params)
#   end
# 
#   # This should be a list of fields in the table that will be updated from the form fields
#   # Format: [:title, :author_id, :publisher_id]
#   # def attributes_to_update
#   #   []
#   # end
# 
#   # The set of things that reveal and hide themselves depending on demand.  Default is that all start and stay visible.
#   # But if the detail panel starts hidden and should pop out, set, e.g., :detail => ['div_containing', false]
#   # def hud_panels
#   #   {}
#   # end
# 
#   # These Javascript calls reveal and dismiss HUD panels.
#   # They are collected together here in case something other than Prototype/Scriptalicious is desired
#   # def js_reveal(element = 'div_' + self.name, duration = 0.3, queue = nil)
#   #   queue_parm = queue ? ", queue: {position: '" + queue + "', scope: '" + element + "'}" : ''
#   #   "Effect.SlideDown('#{element}', {duration: #{duration}#{queue_parm}});"
#   # end
#   # 
#   # def js_dismiss(element = 'div_' + self.name, duration = 0.3, queue = nil)
#   #   queue_parm = queue ? ", queue: {position: '" + queue + "', scope: '" + element + "'}" : ''
#   #   "Effect.SlideUp('#{element}', {duration: #{duration}#{queue_parm}});"
#   # end
# 
#   # These are the standard transitions, but you can add to them by calling
#   # super.merge!({:other => [:transitions]}).
#   # def transition_map
#   #   frame_transitions.merge(
#   #   list_panel_transitions.merge(
#   #   detail_panel_transitions.merge(
#   #   filter_panel_transitions.merge(
#   #   selected_panel_transitions.merge(
#   #   message_panel_transitions
#   #   )))))
#   # end
# 
#   # def transition_map
#   #   {
#   #     :index => [:index, :_load_list],
#   #     :_load_list => [:index, :_load_list]
#   #   }
#   # end
#   
#   # Basic start state
#   
#   def index
#     load_records
#     nil
#   end
# 
#   # Containing frame states.
# 
#   # def frame_transitions
#   #   {
#   #     :_frame_start => [:_frame],
#   #     :_frame => [:_frame, :_frame_start],
#   #   }
#   # end
#   # 
#   # def _frame_start
#   #   @editing_mode = false
#   #   @hud_state = hud_panels
#   #   jump_to_state :_frame
#   # end
#   # 
#   # def _frame
#   #   nil
#   # end
# 
# 
#   # List panel states
#   # The list panel displays a recordset based on the currently selected filter
# 
#   # def list_panel_transitions
#   #   {
#   #     :_list_start => [:_list],
#   #     :_list_reveal => [:_list],
#   #     :_list_dismiss => [:_list],
#   #     :_list => [:_list, :_list_start, :_list_reveal, :_list_dismiss],
#   #   }
#   # end
#   # 
#   # def _list_start
#   #   jump_to_state :_list
#   # end
# 
#   # def _list
#   #   # Consult the filter panel to find what the current filter is, then load records accordingly
#   #   filter_panel = parent[parent.name + '_filter']
#   #   load_records(filter_panel.filters[filter_panel.filter][:conditions])
#   #   nil
#   # end
# 
#   # def _list_reveal
#   #   hud_reveal(:list)
#   #   jump_to_state :_list
#   # end
#   # 
#   # def _list_dismiss
#   #   hud_dismiss(:list)
#   #   jump_to_state :_list
#   # end
# 
# 
#   # Selected panel states
#   # The selected panel is a specialized display panel used within a detail panel of a parent.
#   # When the parent calls load_record, the selected panel's :id_from_parent parameter is set.
#   # When a select link is clicked on a subordinate list, this passes (as :id) to _selected_change
# 
#   # def selected_panel_transitions
#   #   {
#   #     :_selected_start => [:_selected],
#   #     :_selected_update => [:_selected],
#   #     :_selected_change => [:_selected_update],
#   #     :_selected => [:_selected, :_selected_start, :_selected_update, :_selected_change],
#   #   }
#   # end
#   # 
#   # def _selected_start
#   #   @original = nil
#   #   jump_to_state :_selected_update
#   # end
#   # 
#   # def _selected
#   #   @dirty = (@original && @original.id != @record.id)
#   #   nil
#   # end
#   # 
#   # def _selected_update
#   #   load_record(@selected_id)
#   #   @original ||= @record
#   #   jump_to_state :_selected
#   # end
#   # 
#   # def _selected_change
#   #   @selected_id = param(:id)
#   #   jump_to_state :_selected_update
#   # end
# 
# 
#   # Filter panel states
#   # The filter panel shows the filter options and current filter.
# 
#   # def filter_panel_transitions
#   #   {
#   #     :_filter_start => [:_filter],
#   #     :_filter_update => [:_filter],
#   #     :_filter => [:_filter, :_filter_start, :_filter_update],
#   #   }
#   # end
#   # 
#   # def _filter_start
#   #   @filters = filters_available
#   #   @filter = filter_default
#   #   jump_to_state :_filter
#   # end
#   # 
#   # def _filter
#   #   nil
#   # end
#   # 
#   # def _filter_update
#   #   @filter = param(:new_filter) || filter_default
#   #   trigger(:filterChanged)
#   #   jump_to_state :_filter
#   # end
# 
#   # Message panel states
#   # The message panel is just for showing result messages in a way that doesn't rely on any other panel being visible.
#   # The message is stored in the frame (using post_message below), and once displayed, it is erased.
# 
#   # def message_panel_transitions
#   #   {
#   #     :_message_start => [:_message],
#   #     :_message => [:_message, :message_start],
#   #   }
#   # end
#   # 
#   # def _message_start
#   #   @message = ''
#   #   jump_to_state :_message
#   # end
#   # 
#   # def _message
#   #   @message_to_display = @message
#   #   @message = ''
#   #   hud_reveal(:message, 0.3, 'front')
#   #   hud_dismiss(:message, 1.0, 'end')
#   #   nil
#   # end
# 
# 
#   # Detail panel states
#   # The detail panel is the most complicated one, it handles the bulk of the action here.
#   # The frame holds the current id and whether we are in editing mode.
# 
#   # def detail_panel_transitions
#   #   {
#   #     :_detail_start => [:_detail],
#   #     :_show => [:_detail],
#   #     :_edit => [:_detail],
#   #     :_update => [:_detail_dismiss, :_show],
#   #     :_new => [:_detail], 
#   #     :_delete => [:_detail],
#   #     :_detail_dismiss => [:_detail],
#   #     :_detail => [:_detail, :_detail_start, :_show, :_edit, :_update, :_new, :_delete, :_detail_dismiss],
#   #   }
#   # end
#   # 
#   # def _detail_start
#   #   new_record
#   #   parent.editing_mode = false
#   #   jump_to_state :_detail
#   # end
#   # 
#   # def _detail
#   #   @editing = parent.editing_mode
#   #   nil
#   # end
#   # 
#   # def _show
#   #   load_record(param(:id))
#   #   hud_reveal(:detail)
#   #   parent.editing_mode = false
#   #   show_child_panels
#   #   jump_to_state :_detail
#   # end
# 
#   # Tell the child panels to move to their record matching the one specified by the just-shown parent
#   # def show_child_panels
#   #   child_panels.each do |cp, field_id|
#   #     parent[cp][cp + '_detail'].set_local_param(:id, @record[field_id])
#   #     parent[cp][cp + '_detail'].trigger(:redraw)
#   #     parent[cp][cp + '_detail'].trigger(:dismissList)
#   #   end
#   # end
#   # 
#   # def _edit
#   #   load_record(parent.param(:id))
#   #   hud_reveal(:detail)
#   #   parent.editing_mode = true
#   #   @return_to_show = parent.param(:from_show)
#   #   edit_child_panels
#   #   jump_to_state :_detail
#   # end
#   # 
#   # def edit_child_panels  
#   #   child_panels.keys.each do |cp|
#   #     parent[cp][cp + '_detail'].trigger(:revealList)
#   #     parent[cp][cp + '_detail'].trigger(:dismissPanel)
#   #   end
#   # end
#   # 
#   # def _update
#   #   update_from_children
#   #   @record.update_attributes(self.update_attributes_hash)
#   #   @record.save
#   #   @record.reload
#   #   post_message "Changes saved."
#   #   trigger(:recordChanged)
#   #   jump_to_state :_show if @return_to_show
#   #   jump_to_state :_detail_dismiss
#   # end
# 
#   # When an update occurs, we need to fetch the values from the children
#   # def update_from_children
#   #   child_panels.each do |cp, field_id|
#   #     @record[field_id] = self[cp + '_selected'].record.id
#   #   end
#   # end
#   # 
#   # def _new
#   #   new_record
#   #   hud_reveal(:detail)
#   #   parent.editing_mode = true
#   #   edit_child_panels
#   #   jump_to_state :_detail
#   # end
#   # 
#   # def _delete
#   #   if (doomed = find_record(parent.param(:id)))
#   #     if doomed.id == @record.id
#   #       new_record
#   #       hud_dismiss(:detail)
#   #     end
#   #     doomed.destroy
#   #     post_message "Record deleted."
#   #     trigger(:recordChanged)
#   #   end
#   #   jump_to_state :_detail
#   # end
#   # 
#   # def _detail_dismiss
#   #   hud_dismiss(:detail)
#   #   jump_to_state :_detail
#   # end
# 
# 
#   # Other helpers
# 
#   def find_record(id = nil)
#     resource_model.find_by_id(id)
#   end
# 
#   def load_record(id = nil)
#     if @record = find_record(id)
#       load_child_selected_records
#     else
#       new_record
#     end
#   end
# 
#   def load_child_selected_records
#     child_panels.each do |cp, id_field|
#       self[cp + '_selected'].selected_id = @record[id_field]
#     end
#   end
# 
#   def new_record
#     @record = resource_model.new
#     load_child_selected_records
#   end
# 
#   def update_attributes_hash
#     attrs = {}
#     self.attributes_to_update.each do |att|
#       attrs[att] = param(att)
#     end
#     attrs
#   end
# 
#   def resource_model
#     Object.const_get param(:resource).classify
#   end
# 
#   def resource_name
#     param(:resource)
#   end
#   
#   # def js_emit
#   #   js_emit = @js_emit || ''
#   #   @js_emit = ''
#   #   js_emit
#   # end
#   # 
#   # def set_js_emit(to_emit)
#   #   set_local_param(:js_emit, (local_param(:js_emit) || '') + to_emit)
#   # end
#   # 
#   # def get_js_emit
#   #   js_emit = local_param(:js_emit)
#   #   set_local_param(:js_emit, nil)
#   #   js_emit
#   # end
#   # 
#   # def post_message(message = '')
#   #   parent[parent.name + '_message'].message = message
#   #   trigger(:messagePosted)
#   # end
# 
#   # The HUD reveal and dismiss helpers will set up Javascript to hide or reveal certain panels.
#   # The state of each panel is remembered, so that re-revealing or re-dismissing won't do anything.
#   # The frame keeps track of the state of each panel, and they are assumed to be called by the child panels.
#   # If there is no entry for the panel in the HUD array, it will also do nothing.
# 
#   # def hud_reveal(panel, duration = 0.3, queue = nil)
#   #   hud_control(panel, false, duration, queue)
#   # end
#   # 
#   # def hud_dismiss(panel, duration = 0.3, queue = nil)
#   #   hud_control(panel, true, duration, queue)
#   # end
#   # 
#   # def hud_control(panel, dismiss = false, duration = 0.3, queue = nil)
#   #   @js_emit ||= ''
#   #   if hud = parent.hud_state[panel]
#   #     if hud[1] == dismiss
#   #       @js_emit = @js_emit + (dismiss ? js_dismiss(hud[0], duration, queue) : js_reveal(hud[0], duration, queue))
#   #       hud[1] = !dismiss
#   #       parent.hud_state.merge!({panel => hud})
#   #     end
#   #   end
#   # end
# end

