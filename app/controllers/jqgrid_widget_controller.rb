class JqgridWidgetController < ApplicationController
  unloadable
  
  # JqgridWidgetController takes Apotomo::Controller methods and applies a couple of
  # patches, and adds two shortcuts for standardizing/simplifying the addition of
  # jqgrid_widgets to the widget tree with proper communication channels open between them.
  
  # Bring in Apotomo's controller methods, but redefine render_page_update_for to
  # a) avoid reliance on Prototype, b) allow direct Javascript emission.
  # Update: apotomo now has an official way to output js, so I can maybe avoid this.
  include Apotomo::ControllerMethods
  # include JqueryApotomoControllerMethods
  # Bring in a couple of things from jRails.  Probably it would be better to simply attach jRails in full,
  # but for the moment there are only a couple of things that are needed for this to operate in jQuery alone.
  # require 'jquery_apotomo_helper_methods'
  
  # The index method here is intended to be called via 'super' from the subclass.
  # This sets a global event handler on row clicks to call the #handle_select method defined later
  # in this file.
  # I'm trying to get rid of this global method.  Please work.
  # It is possible that the super calls can be removed at this point, since clearly they aren't doing anything.
  # Assuming that this actually works.
  def index
    # respond_to_event :rowClick, :with => :handle_select  
    # respond_to_event :recordChosen, :with => :handle_choice
  end
  
  protected
  
  # Call jqg_widget to create a widget.
  # This guesses most of the options to be used, although they can be overridden.
  # The resource is required, it is the name of the model from which the data will be drawn.
  # For example, if the model is Person, send 'person' in as the resource.
  # The simplest call (using all default options) can be simply w = jgq_widget('person')
  # This should suffice for most situations.
  # Note: If the widget you are creating will have children but no parents, you should
  # create the widget with jgq_top_widget (or use :top_widget => 'yes').
  #
  # By default, the widget will be an instance of the class derived by pluralizing the resource and adding 'Cell',
  # (e.g., PeopleCell).  If you need the cell class to be something other than this, you can pass in one of
  # two things.  To completely specify the cell class, send in :cell_class => Person.  Passing :cell_class will
  # not affect anything else.
  #
  # Alternatively, if you want to add a second widget that shares the same resource as an existing widget,
  # you can send :resource_alias => 'something'.  This will be used in place of the resource for generating
  # the default DOM ID, cell class name, and widget id.
  #
  # If :prefix is set, the widget_id and jqgrid_id will have the prefix prepended.
  # The :prefix can be used to differentiate two widgets of the same kind that appear on the same screen.
  #
  # :jqgrid_id can be passed in if a special DOM id is needed, but it will otherwise default to
  # prefix + resources + _list, as in 'pfx_people_list' for :prefix => 'pfx_' and resource = 'person'.
  # If a resource alias is set, it will be based on that instead.
  #
  # :widget_id is derived from the resource and prefix, e.g., 'pfx_person'.  This should be unique on the page,
  # but I can't think of a good reason to override the default option.  If you want to, pass :widget_id.
  # If a resource alias is set, it will be based on that instead.
  #
  # You can pass :top_widget => 'yes' to specify that this widget is at the top of its branch of the
  # widget tree, which bounds message passing between the widgets.  But it's better to use #jqg_top_widget.
  # :top_widget is a special bit of magic that should be set to 'yes' for the highest parent in a
  # tree of widgets.  This is used to bound communication between the widgets.
  #
  # When the widget is created, it will also be told to watch for :openEditPanel and :editPanelCancel events
  # originating in its own list, and sets the handlers.
  def jqg_widget(resource, opts = {})
    # cell_class is now just a string
    # top_widget is passed along if provided
    # jqgrid_id and resource are required by the widget
    pfx = opts[:prefix] || ''
    resource_alias = opts[:resource_alias] || resource
    widget_id = pfx + (opts[:widget_id] || resource_alias)
    cell_class = opts[:cell_class] || (resource_alias.pluralize + '_cell').camelize
    jqgrid_id = opts[:jqgrid_id] || (pfx + resource_alias.pluralize + '_list')
    x = widget(cell_class, :_setup, widget_id, opts.merge({:resource => resource, :jqgrid_id => jqgrid_id}))
    # All widgets watch themselves for cellClick, drawPanel, and deleteRecord events
    x.watch(:cellClick, x.name, :_cell_click, x.name)
    # x.watch(:rowClick, x.name, :_row_click, x.name) # should be obsolete
    x.watch(:drawPanel, x.name, :_draw_panel, x.name)
    x.watch(:deleteRecord, x.name, :_delete_record, x.name)
    # Return the widget
    return x
  end

  # A relatively non-magical version of jqg_widget(resource, :top_widget => true, ...).  Everything else
  # is as above for jqg_widget
  def jqg_top_widget(resource, opts = {})
    return jqg_widget(resource, {:top_widget => true}.merge(opts))
  end
  
  # Add a child widget to a parent widget (and do the necessary event wiring).
  # In most cases, it's simpler to use jqg_child_widget.
  def embed_widget(parent_cell, child_cell)
    parent_cell << child_cell
    # Parents watch themselves for record selects and unselects, and send children into appropriate states.
    parent_cell.watch(:recordSelected, child_cell.name, :_parent_selection, parent_cell.name)
    parent_cell.watch(:recordUnselected, child_cell.name, :_parent_unselection, parent_cell.name)
    # Parents also watch children for record updates, and update themselves if one occurs.
    parent_cell.watch(:recordUpdated, parent_cell.name, :_child_updated, child_cell.name)
    # Children watch themselves for recordChosen events
    # That's weird no?
    # Why don't the parents watch the children?
    child_cell.watch(:recordChosen, child_cell.name, :_child_choice, child_cell.name)
  end
    
  # A shortcut for embed_widget(parent, child = jqgrid_widget('resource', opts...))
  # Use like jqgrid_widget, except insert the parent widget as the first argument
  # Returns the child widget
  def jqg_child_widget(parent_cell, resource, opts = {})
    embed_widget(parent_cell, child_cell = jqg_widget(resource, opts))
    return child_cell
  end
  
end
