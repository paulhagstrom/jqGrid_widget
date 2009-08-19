module PatchApotomoEvents
  # Patch stores only the widget_id and its tree to allow it to be found again when needed
  # Commented out is a different patch that stripped out the source widget's ivars_to_forget.
  # Obsolete note about the other patch:
  # Also requires include PatchApotomoControllerIvars to have been mixed into the widget class

  # Currently, there is only one Event class which only differs in <tt>type</tt>.
  # An events' <tt>type</tt> defaults <tt>:invoke</tt>.
  class ::Event
    attr_accessor :type, :source, :data
    # attr_accessor :type, :data

    def initialize(type=nil, source=nil, data={})
      @type       = type
      @source     = source ? source.dup.remove_ivars_to_forget : nil
      # @source     = source
      @data       = data
      # self.source = source_widget

    end
    def widget_id; raise "wrong! you shouldn't use me like an event handler."; end

    # # Locates and returns the source widget
    # def source
    #   if @source
    #     puts "%%%%%%%%%%%%%%%%%%%%% retrieving " + @source
    #     return @source_root.find_by_path(@source)
    #  else
    #    puts "%%%%%%%%%%%%%%%%%%%%% retrieving nil"
    #    return nil
    #  end
    # end
    # 
    # # Sets the source by extracting the widget_id
    # def source=(source_widget)
    #   puts "%%%%%%%%%%%%%%%%%%%%% storing " + source_widget.name + " and " + source_widget.root.inspect
    #   @source = source_widget.name
    #   @source_root = source_widget.root
    # end
    
    # Return the event type, which is <em>always</em> a Symbol.
    def type
      (@type || :invoke).to_sym
    end
    
    ### FIXME: who keeps a stale reference to the event?
    def _dump(depth)
      ""
    end
    def self._load(str)
      Event.new
    end
  end

end
