class JqgridWidgetCell < Apotomo::JavaScriptWidget

  include JqgridWidgetUtilities
  include JqgridWidgetCommunication
  include JqgridWidgetGrid
  include JqgridWidgetPatch
    
  include ActionView::Helpers::JavaScriptHelper # for escape_javascript in js_push_json_to_cache

  helper JqgridWidget::JqgridWidgetHelper

  # Make some of the methods defined here available to the view as well
  helper_method :js_reload_grid, :js_select_id, :js_push_json_to_cache, :empty_json
  helper_method :param
  # helper_method :selector_field_id
  
  # Make selected record gettable from the outside
  attr_reader :record
  # Make jqgrid_id gettable from the outside, descendants_to_reload asks for this from children
  attr_reader :jqgrid_id
  # Make form_widget gettable from the outside, used when opening a title panel
  attr_reader :is_form_widget

  attr_reader :select_on_load
  attr_reader :selector_for
  attr_reader :records
  
  # Configuration
  #
  # There are basically three kinds of widgets: parents, children, and selectors
  # Regular children are the result of has_meny in the model, selectors are has_one.
  #
  # The initialize method is for setting things up that can be set up before the tree is assembled.
  # These are generally set in the controller method.  The important ones are
  # resource, jqgrid_id, selector_for, and top_widget
  #
  # The first state is _setup, where the majority of the setup happens, after which _setup.html.erb is rendered.
  # This should be defined in your subclassed cell.  _setup takes a block, so in combination with add_column and
  # add_choice_column, you can set up your table there.  _setup is also where you set up your filters, and grid options.
  #
  # For each widget you need a subclassed cell, a folder containing its views, and any of the partials that you need.
  # Minimally, you'll need _panel, which defines the edit record form.  You may also want _setup if you want to do anything
  # with the layout, wire in filters or livesearch.
  #
  # You'll need a controller and a controller index.html.erb view to control the layouts of the widgets.
  # For controllers with just one widget, this is pretty boring, but if you want to lay out several widgets on a page, this
  # is where it is done.
  #
  # In order to reduce the number of AJAX requests, I have implemented a data-caching mechanism that is consulted
  # first before an AJAX request is made.  Upon initial wiring of all of the child tables, an empty recordset is cached,
  # which is used instead of querying the server.  When the topmost widget loads its recordset, it retrieves
  # the data (via the _send_recordsets state) of the widget and all of its descendants, in the form of a series
  # of Javascript calls to push the JSON data into the caches of the parent widget and all of its descendants,
  # clear the rest, and then trigger reloads for everybody.
  #
  # In the controller, you pass information to initialize as below.  The super call is relevant because it will flush out the
  # widget tree before adding, which seems to be useful.  jqg_top_widget sets up the top widget, to which children can be added
  # in blocks.  The defaults are sensible (no options are generally needed past the resource name), but they can be set
  # explicitly.  Here, :cell_class defines a widget class to use (instead of resources_cell), :widget_id defines the widget's
  # id (instead of resource).  :selector_for is somewhat more important; if you have a selector, you want to set this here, naming
  # the field to which the selection applies.
  #
  # def index
  #   super
  #   use_widgets do |root|
  #     root << jqg_top_widget('degree', :cell_class => 'degrees_select', :widget_id => 'degrees_select') do |degwid|
  #       jqg_child_widget(degwid, 'program', :cell_class => 'program_lookup', :selector_for => :program_id)
  #     end
  #   end
  #   render
  # end
  #
  # If you are going to have two basically independent top widgets, it seems that they still need to be in a
  # parent-child relationship, just without the communication wiring.  So, to do something like that,
  # you would just attach one top widget to another.  I think you can have as many children of the top top widget
  # as you want, they just can't be children of root.  Then, in your _setup view for the topmost widget, set the
  # layout, use table_to_wire, etc., for that widget, and then use rendered_children['widget_id'] for the others.
  # In the view (for the controller, which presumably corresponds to your topmost widget) just render the topmost one.
  # use_widgets do |root|
  #   root << jqg_top_widget('profile_status') do |wid|
  #     wid << jqg_top_widget('profile_role')
  #   end
  # end
  #
  # In the subclassed widget, you set up the columns and grid as below.  This has a selector.  :program_name is the custom
  # display function (translates from id to name).  Because there is a selector, the custom display function needs to be
  # indicated as a helper_method, since there will be need to draw it in the view.  Selectors should also be listed in the
  # @selectors hash, which has members like 'resource' => [:parent_field, :custom_display_method].
  #
  # A custom display method can take a static parameter; if the custom field is defined as :custom => :handler__parm
  # then handler will be called with the record as the first parameter and 'parm' as the second.
  # 
  # helper_method :program_name
  # 
  # def _setup
  #   super do |col|
  #     col.add_column('name', :width => 100, :sortable => 'default')
  #     col.add_column('section_id', :width => 50, :sortable => false, :custom => :section_name)
  #   end
  #   @jqgrid_options.update({
  #     :rows_per_page => 20,
  #     :height => 350
  #   })
  #   @selectors = {'program' => [:progam_id, :program_name]}
  #   render
  # end
  # 
  # def section_name(degree)
  #   degree.section_id ? degree.section.name : '(??)'
  # end
  # 
  # def program_name(degree)
  #   degree.program_id ? degree.program.name : '(??)'
  # end
  
  # Live search fields are a little bit tricky.  They work like this:
  # @livesearch_fields is a hash where the key matches a search box (specified when wired into the view)
  # The value for this key is an array of fields in the database that will be searched.
  # So, for example {'name' => ['person.last_name', 'person.first_name']}
  # If somebody types "a x", then it is going to look for BOTH a and x.  It does this by looking for
  # a in any of the fields and x in any of the fields.
  
  # Other things one can define in _setup (I think, these two might be obsolete)
  # @children_to_hide (array of ids of the tables that will be collapsed upon a row select)
  # @children_to_trigger (array of ids of the tables that will be put into a 'loading...' state upon a row select)

  # @select_on_load determines whether the first item in a list should be selected.
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

  # initialize checks to see if thst start_state is set in order to avoid doing things when a temporary empty widget is created
  def initialize(id, start_state, opts={})
    # puts "Hello from initialize: " + id.to_s + ", " + start_state.to_s + ", opts: " + opts.inspect + "."
    if start_state == :_setup
      # important for parents, children, selectors
      @resource = opts[:resource]
      @jqgrid_id = opts[:jqgrid_id] || @resource.pluralize + '_list_grid'
      # is_top_widget is true for parents only, not children or selectors
      @is_top_widget = opts[:top_widget] || false
      @is_form_widget = opts[:form_widget] || false
      # for selectors, selector_for should hold the field (symbol) of the parent's record the selection depends on, nil for parents, child
      @selector_for = opts[:selector_for]
    end
    super(id, start_state, opts)
  end

  # TODO: See if @is_top_widget can be replaced by checking to see if (@)parent is nil
  def _setup
    # puts "Hello from setup: " + self.name.to_s + ", @opts is #{@opts.inspect}, @resource is #{@resource.inspect}."
    @filters = [['all', {:name => 'All'}]]
    @filter = @filters.first[0]
    @columns = []
    @livesearch_fields = {}
    @jqgrid_options = {
      :row_action => 'title_panel',
      :row_object => '_panel',
      :rows_per_page => 0, # unlimited
      :caption => @resource.pluralize.humanize #'Records'
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
    }
    # This is where the "flash updates" will go.  Should be a span.
    @feedback_span = 'nav_feedback'
    # Determines whether the first record should be automatically selected.
    # Can also be 'unique' (select iff there is only one record) or
    # 'exact' (select even if not unique if it is the exact match of the filter string)
    @select_on_load = false
    @record = scoped_model.new
          
    yield self if block_given?
  
    @sortable_columns = {}
    @columns.each {|c| @sortable_columns[c[:index]] = c[:field] if c[:sortable] }
    # @sortable_columns = (@columns.map {|c| c[:sortable] ? c[:index] : nil}).compact
    @default_sidx = (@columns.map {|c| c[:sortable] == 'default' ? c[:index] : nil}).compact.first
  end
  
  
  # Things you may want to override
  
  # To load a recordset or create a new record, a find or new call is passed to scoped_model.
  # In the top widget or in a selector, this is just the resource for the widget (no actual scoping)
  # You can override this, but it should work sensibly as-is for most uses.
  # TODO: This could be coded more elegantly, but this works.
  def scoped_model
    if @is_top_widget || @selector_for
      Object.const_get @resource.classify
    else
      parent.record.send(@resource.pluralize) rescue Object.const_get @resource.classify
    end
  end

  # If selector_for is set, selector_field_value is used to determine what the parent's
  # field is set to (the currently selected record).
  def selector_field_value
    parent.record[@selector_for] rescue nil
  end
    
  # Communications
    
  # The parent widget has posted a recordSelected event.
  # A standard subgrid will send a new recordset based on the parent's (new) selection.
  # A selector will set the selection based on the parent's newly selected record.
  # TODO: Selectors with paginators are a bad idea, because it won't jump to the right page.
  def _parent_selection
    if @selector_for
      render :js => select_record_js(selector_field_value) + js_choose_id(selector_field_value)
    else
      render :js => update_recordset_js
    end
  end

  # The parent widget has posted a recordUnselected event.
  # A standard subgrid will clear its recordset and reload its grid
  # A selector will clear its selection and resend the recordset.
  # TODO: The resending of the recordset for selectors is generally superfluous except for the initial page load.
  # TODO: In the future maybe I could check to see if the recordset is empty and resend only if it is?
  def _parent_unselection
    trigger(:recordUnselected)
    if @selector_for
      @record = scoped_model.new
      render :js => update_recordset_js
    else
      render :js => js_push_json_to_cache(empty_json) + js_reload_jqgrid
    end
  end
      
  # A child widget has updated a record (and posted a recordUpdated event)
  # This causes a reload (in case one of values is reflected in the parent table)
  # The reload is not re-propagated downward, because the child was aware of the change.
  def _child_updated
    render :js => update_recordset_js(false)
  end
  
  # This locates the record passed in by id and stores it in @record (if it wasn't already there)
  # When found, a recordSelected event is announced (will tell the children)
  # If not found, a recordUnselected event is announed (will tell the children)
  # Javascript return will set the selection in the table.
  def select_record_js(id)
    unless @record && @record.id == id #only announce if there was a change.
      if @record = scoped_model.find_by_id(id)
        trigger(:recordSelected)
        return js_select_id(id)
      else
        @record = scoped_model.new
        trigger(:recordUnselected)
        return js_select_id(nil)
      end
    end
    return ''
  end
    
  # A cellClick event (a cell was clicked on in this widget)
  # It should receive id (rowid), table (jqgrid id), cell_column (cell index)
  # TODO: The add function here doesn't make much sense in the context of column panels.
  # TODO: Are column panels really important?  Or maybe just for viewing?
  def _cell_click
    js_emit = select_record_js(param(:id).to_i)
    id = @record.id.to_i
    if id > 0
      panel_type = nil
      # Priority goes to actions defined by columns
      # I am preparing to remove column actions, and require that all panels just load _panel.
      # Maybe someday later I can bring back the complexity of column panels if they are really useful for something.
      case @columns[param(:cell_column).to_i][:action]
      when 'title_panel', 'panel'
        panel_type = @columns[param(:cell_column).to_i][:action]
        panel_object = @columns[col.to_i][:object]
      when 'choice'
          js_emit += js_choose_id(@record.id) + parent.update_choice_js(self.name, @record)
      else
        case @jqgrid_options[:row_action]
        when 'title_panel', 'panel'
          panel_type = @jqgrid_options[:row_action]
          panel_object = @jqgrid_options[:row_object]
        when 'choice'
          js_emit += js_choose_id(@record.id) + parent.update_choice_js(self.name, @record)
        end
      end
    else
      # Add
      panel_type = 'title_panel'
      panel_object = @jqgrid_options[:row_object]
    end
    if panel_type
      # specs = jqgrid_make_js({:id => param(:id), :table => param(:table),
      #   :cell_column => param(:cell_column), :table_view => param(:table_view)})
      specs = jqgrid_make_js({:id => param(:id), :table => param(:table), :panel => panel_object,
        :cell_column => param(:cell_column), :table_view => param(:table_view)})
    end
    # If the panel has any jqgrid widgets in it we need to remove them first before bringing in the new
    # edit panel.  So look for any child widgets for which form_widget is true.
    self.children.each do |c|
      js_emit += "if(jQuery('##{c.jqgrid_id}')){jQuery('##{c.name}').remove();}" if c.is_form_widget
    end
    case panel_type
    when 'title_panel'
      js_emit += "openTitlePanel(#{specs}, jQuery('##{@jqgrid_id}').data('draw_panel_url'), true);"
    when 'panel'
      js_emit += "openRowPanel(#{specs}, jQuery('##{@jqgrid_id}').data('draw_panel_url'), true);"
    end
    render :js => js_emit
  end
    
  # This returns the html for an edit panel
  # It is called by an event, but if I can get this directly, that would be better.  It's kind of slow now.
  # Note: I had to patch apotomo in order to keep this from spitting out a Javascript page update.
  def _draw_panel
    @apotomo_emit_raw_view = true
    render :view => param(:panel)
  end
    
  # put some feedback up. No quotation marks allowed.
  # TODO: Allow quotation marks
  def js_flash_feedback(message)
    <<-JS
    jQuery('##{@feedback_span}').hide().html("#{message}").fadeIn('slow', function()
        {jQuery(this).fadeOut('slow');});
    JS
  end
  
  # State _edit_panel_submit
  # This is the target of the edit panel's form submission.
  # Updates or adds the record, reselects it, and alerts children and parents.
  # Dangerously, perhaps, it relies on the stateful nature of these things.  It knows the id from @record.
  # If this is passed an argument it will be used instead of the request parameters
  # This is to allow a subclassed widget to inspect/modify them and then do super modified_params
  def _edit_panel_submit(req_parms = nil)
    request_params = req_parms || param(@resource.to_sym)      
    js_emit = ''
    # @record = scoped_model.find_by_id(param(:id)) || scoped_model.new
    puts 'REQUEST PARAMETERS IN EDIT PANEL SUBMIT: ' + request_params.inspect
    if @record.new_record?
      @record = scoped_model.create(request_params)
    else
      @record.update_attributes(request_params)
    end
    if @record.save
      @record.reload # Be sure we get the id if this was a new record
      trigger(:recordUpdated)
      js_emit += js_flash_feedback("Record updated.")
      js_emit += <<-JS
        closeEditPanel('##{@jqgrid_id}');
      JS
    else
      js_emit += js_flash_feedback('Some kind of error saving in edit_panel_submit')
    end
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
    js_emit += js_flash_feedback("Record deleted.")
    trigger(:recordUpdated)
    trigger(:recordUnselected)
    render :js => js_emit + update_recordset_js(false)
  end
  
  # State _send_recordset (returns Javascript, called with jQuery.getScript)
  # This is called by the jQGrid data source function (retrieveJSON, defined in jqgrid_widget.js) if there
  # is no data already in the cache.  It should result in Javascript code to push the recordset into the cache
  # and then reload the grid (to pull it back out again).
  def _send_recordset
    puts "Hello from send_recordset: " + self.name.to_s
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
    puts "Hello from update_recordset_js: " + self.name.to_s
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
      if @select_on_load
        if records.size > 1
          if @select_on_load == 'exact'
            if @livesearch
              records.each do |r|
                if r.attributes[@livesearch_field].downcase == @livesearch.downcase
                  js_emit += select_record_js(r.id)
                  selection_survived = true
                end
              end
            end
          else
            unless @select_on_load == 'unique'
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
    # puts "**with a js_emit of: " + js_emit
    return js_emit
  end
    
  # State _set_filter
  # This is triggered by clicking on a filter, which sets a parameter :catid
  # The catid parameter is named like filter.key__jqgrid.id_filter_category.
  # The filter key itself is derived from the beginning of this.
  # When the thing is first drawn, an :init parameter is passed.
  # With no :catid, the :filter parameter is presumed to hold the filter key.
  # Subfilters come in as additional parameters under subfilter.
  # Specifically subfilter[subfilter_key][id] = 1 (not mentioned, zero)
  # These are stored in @filter and @subfilter.
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
    # puts "FILTER FILTER FILTER UPDATED UPDATED UPDATED. filter " + @filter.inspect + ' ** SUBFILTER ** ' + @subfilter.inspect
    redraw_filter = filter_unchanged ? '' : js_redraw_filter
    clear_checkboxes = (filter_unchanged && category_not_clicked) ? '' : <<-JS
      jQuery('##{@jqgrid_id}_#{@filter}_filter_form').find('input[type=checkbox]').attr('checked',false);
    JS
    render :js => redraw_filter + clear_checkboxes + update_recordset_js(false)
  end

  # State _filter_display
  # This is triggered when the page is initially drawn, to fill in the filter div.
  # It is used by wire_filters in jqgrid_widget_helper
  # This also required the apotomo patch to allow rendering a raw view (see also the form display)
  def _filter_display
    @apotomo_emit_raw_view = true
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
  # TODO: Somehow make the dirty status of the choice evident visually, so you know you have to save.  Made an attempt with CSS
  def update_choice_js(source, subrecord)
    js_emit = ''
    if selector = @selectors[source]
      field, custom = selector
      resource_field = @resource + '_' + field.to_s
      # TODO: If there happens to be a record, but the edit panel is closed (canceled), it should create a new one.
      unless @record
        @record = scoped_model.new
      end
      @record[field] = subrecord.id
      display_value = escape_javascript(call_custom(custom,@record.clone))
      # Add a dirty class if this is a change that needs saving
      class_update = @record.send(field.to_s + '_changed?') ? ".addClass('dirty')" : ".removeClass('dirty')"
      # The cell click url was stored in the jqgrid.data
      js_emit = <<-JS
        /*ensureTitlePanel("##{@jqgrid_id}",jQuery('##{@jqgrid_id}').data('draw_panel_url')); */
        var f = jQuery("##{@jqgrid_id}").closest('.ui-jqgrid-view').find('.jqgw-form');
        f.find('#display_#{resource_field}')#{class_update}.html('#{display_value}').effect('highlight');
        f.find('##{resource_field}').val('#{subrecord.id}');
        JS
      js_emit += js_flash_feedback("Choice updated.")
    end
    return js_emit
  end
  
  # SUPPORTING METHODS
  
  # descendents_to_reload creates a list of all descendants that have the select_on_load property set and so
  # might wind up having a selection automatically set.  The _setup state puts this in an instance variable
  # that the views can then use.  visible_children is defined by apotomo.
  def descendants_to_reload
    d = []
    v = visible_children
    if v.size > 0
      v.each do |c|
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
  # TODO: I might want to add a more global eager_load, so it doesn't need to be included in every filter. Same for conditions.
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
  # JavaScript deals poorly with fields that have periods in them, so if you want something like 'people.last_name'
  # as the field (which will magically do what it is supposed to), you need to provide an undotted alias for jqGrid.
  # This can be accomplished by passing :index in explicitly, most everything is built off of that, and :field is a
  # jqGridWidget option that preserves the original intent.
  def add_column(field, options = {})
    # jqGrid options
    options[:index] ||= field
    options[:name] ||= options[:index]
    options[:label] ||= options[:index].humanize
    options[:width] ||= 100
    options[:search] = false unless options.has_key?(:search)
    options[:sortable] = false unless options.has_key?(:sortable)
    # jqGridWidget options
    options[:action] ||= 'event'
    options[:object] ||= ''
    options[:field] = field
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
  
  def call_custom(custom, record)
    if (custom_call = custom.to_s.split('__',2)).size > 1
      self.send(custom_call[0], record, custom_call[1])
    else
      self.send(custom, record)
    end
  end
  
  # Turn @records into something appropriate for the json_for_jqgrid method
  def grid_rows(records)
    records.collect do |r|
      {
        :id => r.id,
        :cell => @columns.collect do |c|
          c[:custom] ? call_custom(c[:custom], r) : (r.attributes)[c[:field]]
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
  # I am not certain about some of this paging stuff.  Maybe.
  def load_records
    get_paging_parameters
    @filter, @subfilter, find_include, find_conditions, @total_records = filter_prepare
    find_order = @sortable_columns.has_key?(@sidx) ? (@sortable_columns[@sidx] + ' ' + ((@sord == 'desc') ? 'DESC' : 'ASC')) :
      (@default_sidx ? @sortable_columns[@default_sidx] + ' ASC' : nil)
    # find_order = @sortable_columns.include?(@sidx) ? (@sidx + ' ' + ((@sord == 'desc') ? 'DESC' : 'ASC')) :
    #   (@default_sidx ? @default_sidx + ' ASC' : nil)
    rows_per_page = @rows_per_page
    if rows_per_page > 0
      @total_pages = (@total_records > 0 && rows_per_page > 0) ? 1 + (@total_records/rows_per_page).ceil : 0
      @page = @total_pages if @page > @total_pages
      @page = 1 if @page < 1
      @start_offset = rows_per_page*@page - rows_per_page
    else
      @total_pages = 1
      rows_per_page = @total_records
      @start_offset = 0
    end
    if @start_offset < 0
      puts "??Why is start_offset negative?"
      @start_offset = 0
    end
    if @livesearch && @livesearch.size > 0
      livesearch_fields = @livesearch_fields[@livesearch_field] rescue []
      if livesearch_fields.size > 0
        fields_conditions = []
        @livesearch.split(' ').each do |substring|
          live_conditions = []          
          livesearch_fields.each do |f|
            find_conditions << "%#{substring}%"
            live_conditions << "#{f} LIKE ?"          
          end
          fields_conditions << '(' + live_conditions.join(' or ') + ')'
        end
        find_conditions[0] += ' and (' + fields_conditions.join(' and ') + ')'
      end
    end
    puts "Rows per page #{@rows_per_page}, offset #{@start_offset}, find_order #{find_order}, find_conditions #{find_conditions}, find_include #{find_include}."
    scoped_model.find(:all, :include => find_include, :conditions => find_conditions,
      :limit => rows_per_page, :offset => @start_offset, :order => find_order)
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
    find_conditions = filter.has_key?(:conditions) ? filter[:conditions].dup : ['1']
    find_include = []
    # find_conditions += filter[:conditions] if filter.has_key?(:conditions)
    find_include += filter[:include] if filter.has_key?(:include)
    # If no subfilters have been checked, this should be skipped, accept all
    # If some subfilters have been checked, only the checked ones will be traversed.
    # Within a single key, two checks yields OR
    # Across keys, two checks yield AND
    # The idea is that the subfilter conditions will read "field in (?)"
    # And then the keys will provide the array of options
    subfilter.each do |key, sf|
      fsf = filter[:subfilters].assoc(key)[1].dup
      find_conditions[0] += (' and ' + fsf[:conditions])
      find_conditions << sf.keys
      find_include << fsf[:include] if fsf.has_key?(:include)
    end
    total_records = scoped_model.count(:all, :include => find_include, :conditions => find_conditions)
    # puts "%%%%% FILTER INFO IN FILTER_PREPARE: include:[#{find_include.inspect}], conditions:[#{find_conditions.inspect}]."
    return[verified_filter, subfilter, find_include, find_conditions, total_records]
  end
  
  # Constants and utilities

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

  # Javascript to set the choice mark on the jqGrid (unset all others)
  def js_choose_id(id = nil)
    if id
      return <<-JS
        var g = jQuery('##{@jqgrid_id}'),
        ids = g.jqGrid('getDataIDs'),
        i = 0;
        if (ids.length > 0) {
          for (i=0;i<ids.length;i=i+1)
          {
            g.setRowData(ids[i],{'#{choice_mark_column_name}':(ids[i]=='#{id}')?('#{chosen_icon}'):('#{not_chosen_icon}')});
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

  # Javascript to redraw a filter
  # Again, the slideUp and slideDown actions don't seem to work, so I will animate the height.
  def js_redraw_filter
    return <<-JS
    jQuery('##{@jqgrid_id}_filter_header').find('.ui-state-highlight').removeClass('ui-state-highlight').addClass('ui-state-default');
    jQuery('##{@filter}__#{@jqgrid_id}_filter_category').addClass('ui-state-highlight');
    jQuery('.jqgw-filter-open').removeClass('jqgw-filter-open').animate({height:'hide'},'fast');
    jQuery('##{@jqgrid_id}_#{@filter}_filter_form').addClass('jqgw-filter-open').animate({height:'show'},'fast');
    JS
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
end

