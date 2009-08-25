# This is now obsolete, I decided not to use it.
# TODO: Remove this from the source.

module PatchApotomoWidgetIvars
  # This is now obsolete.  I think.
  # Mix into the widget with include PatchApotomoWidgetIvars
  # This deletes instance variables that shouldn't be frozen,
  # in preparation for storing this widget as an event source
  # I had to rescue a couple, though, to avoid problems.
  def remove_ivars_to_forget
    @apotomo_root = nil
    ivars_to_remove = ivars_to_forget - ['@parent', '@cell']
    # ivars_to_rescue = [
    #   '@parent',
    #   '@cell',
    #   ]
    (ivars_to_remove).each do |var|
      remove_instance_variable(var)
    end
    self
  end
end
