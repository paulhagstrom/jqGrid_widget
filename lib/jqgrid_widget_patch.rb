module JqgridWidgetPatch
  # Patches to apotomo
  # Mixed into the jqgrid_widget_cell via:
  # include JqgridWidgetPatch
  
  # Redefine page_update_for because it is providing page updates in _draw_panel when I don't want them.
  def page_update_for(content, update)
    if @apotomo_emit_raw_view
      @apotomo_emit_raw_view = nil
      ::Apotomo::Content::Raw.new(content)
    else
      # The following is what page_update_for used to do
      mode = update ? :update : :replace
      ::Apotomo::Content::PageUpdate.new(mode => name, :with => content)
    end
  end
  
end