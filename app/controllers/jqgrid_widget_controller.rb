class JqgridWidgetController < ApplicationController
  include Apotomo::ControllerMethods
  include JqueryApotomoControllerMethods
  include Apotomo::WidgetShortcuts
  require 'jquery_apotomo_helper_methods'
  
  protected
  
  # Create the widgets in a standard way, given the (underscored) name of the model on which the list is based.
  # There is a prefix option (anticipating the possibilty that there might be multiple widgets of the same class on a page)
  # Unless overridden with the :widget_id, :cell_class, :jqgrid_id options, it winds up as follows:
  # For resource 'person', and prefix 'per_', the widget id is 'per_person', of class PeopleCell,
  # and with the list given DOM id 'per_people_list'
  def listy_widget(resource, opts = {})
    cell_class = opts[:cell_class] || Object.const_get((resource.pluralize + '_cell').camelize.classify)
    pfx = opts[:prefix] || ''
    jqgrid_id = pfx + (opts[:jqgrid_id] || resource.pluralize + '_list')
    widget_id = pfx + (opts[:widget_id] || resource)
    top_widget = opts[:top_widget] || 'no'
    x = cell_class.new(controller, widget_id, :_setup, :resource => resource, :jqgrid_id => jqgrid_id,
      :prefix => pfx, :top_widget => top_widget)
    x.watch(:openEditPanel, x.name, :_edit_panel, x.name)
    x.watch(:editPanelCancel, x.name, :_edit_panel_cancel, x.name)
    return x
  end
  
  # Add a child widget to a parent widget (and do the necessary event wiring).
  def embed_widget(parent_cell, child_cell)
    parent_cell << child_cell
    # watch for parental updates and update the child when they happen
    # TODO: I don't need to watch for both events for things that can never receive a recordAutoChanged.  Is it worth checking?
    parent_cell.watch(:recordSelected, child_cell.name, :_send_recordset, parent_cell.name)
    parent_cell.watch(:recordUnselected, child_cell.name, :_clear_recordset, parent_cell.name)
    parent_cell.watch(:recordUpdated, parent_cell.name, :_reflect_child_update, child_cell.name)
  end
  
  # When a row is clicked, jqgrid is set to inquire here for some Javascripts to execute.
  # This causes the source widget to load its @record and announce :recordChanged
  # Its children will look for that, and will fire as needed.
  def handle_select(event)
    event.source.select_record(params[:id])
    ''
  end
      
end
