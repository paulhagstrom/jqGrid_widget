# Just cherry-picking a couple of things from jRails, in order to avoid reliance on Prototype
module ActionView
  module Helpers
    module PrototypeHelper

      unless const_defined? :JQUERY_VAR
        JQUERY_VAR = 'jQuery'
      end
          
      unless const_defined? :JQCALLBACKS
        JQCALLBACKS = Set.new([ :beforeSend, :complete, :error, :success ] + (100..599).to_a)
        AJAX_OPTIONS = Set.new([ :before, :after, :condition, :url,
                         :asynchronous, :method, :insertion, :position,
                         :form, :with, :update, :script ]).merge(JQCALLBACKS)
      end

      def remote_function(options)
        javascript_options = options_for_ajax(options)

        update = ''
        if options[:update] && options[:update].is_a?(Hash)
          update  = []
          update << "success:'#{options[:update][:success]}'" if options[:update][:success]
          update << "failure:'#{options[:update][:failure]}'" if options[:update][:failure]
          update  = '{' + update.join(',') + '}'
        elsif options[:update]
          update << "'#{options[:update]}'"
        end

        function = "#{JQUERY_VAR}.ajax(#{javascript_options})"

        function = "#{options[:before]}; #{function}" if options[:before]
        function = "#{function}; #{options[:after]}"  if options[:after]
        function = "if (#{options[:condition]}) { #{function}; }" if options[:condition]
        function = "if (confirm('#{escape_javascript(options[:confirm])}')) { #{function}; }" if options[:confirm]
        return function
      end
    end
  protected
    def options_for_ajax(options)
      js_options = build_callbacks(options)
      
      url_options = options[:url]
      url_options = url_options.merge(:escape => false) if url_options.is_a?(Hash)
      js_options['url'] = "'#{url_for(url_options)}'"
      js_options['async'] = false if options[:type] == :synchronous
      js_options['type'] = options[:method] ? method_option_to_s(options[:method]) : ( options[:form] ? "'post'" : nil )
      js_options['dataType'] = options[:datatype] ? "'#{options[:datatype]}'" : (options[:update] ? nil : "'script'")
      
      if options[:form]
        js_options['data'] = "#{JQUERY_VAR}.param(#{JQUERY_VAR}(this).serializeArray())"
      elsif options[:submit]
        js_options['data'] = "#{JQUERY_VAR}(\"##{options[:submit]} :input\").serialize()"
      elsif options[:with]
        js_options['data'] = options[:with].gsub("Form.serialize(this.form)","#{JQUERY_VAR}.param(#{JQUERY_VAR}(this.form).serializeArray())")
      end
      
      js_options['type'] ||= "'post'"
      if options[:method]
        if method_option_to_s(options[:method]) == "'put'" || method_option_to_s(options[:method]) == "'delete'"
          js_options['type'] = "'post'"
          if js_options['data']
            js_options['data'] << " + '&"
          else
            js_options['data'] = "'"
          end
          js_options['data'] << "_method=#{options[:method]}'"
        end
      end
      
      if respond_to?('protect_against_forgery?') && protect_against_forgery?
        if js_options['data']
          js_options['data'] << " + '&"
        else
          js_options['data'] = "'"
        end
        js_options['data'] << "#{request_forgery_protection_token}=' + encodeURIComponent('#{escape_javascript form_authenticity_token}')"
      end
      js_options['data'] = "''" if js_options['type'] == "'post'" && js_options['data'].nil?
      options_for_javascript(js_options.reject {|key, value| value.nil?})
    end
    
    def build_update_for_success(html_id, insertion=nil)
      insertion = build_insertion(insertion)
      "#{JQUERY_VAR}('#{jquery_id(html_id)}').#{insertion}(request);"
    end

    def build_update_for_error(html_id, insertion=nil)
      insertion = build_insertion(insertion)
      "#{JQUERY_VAR}('#{jquery_id(html_id)}').#{insertion}(request.responseText);"
    end

    def build_insertion(insertion)
      insertion = insertion ? insertion.to_s.downcase : 'html'
      insertion = 'append' if insertion == 'bottom'
      insertion = 'prepend' if insertion == 'top'
      insertion
    end
    
    def build_callbacks(options)
      callbacks = {}
      options[:beforeSend] = '';
      [:uninitialized,:loading,:loaded].each do |key|
        options[:beforeSend] << (options[key].last == ';' ? options.delete(key) : options.delete(key) << ';') if options[key]
      end
      options.delete(:beforeSend) if options[:beforeSend].blank?
      options[:error] = options.delete(:failure) if options[:failure]
      if options[:update]
        if options[:update].is_a?(Hash)
          options[:update][:error] = options[:update].delete(:failure) if options[:update][:failure]
          if options[:update][:success]
            options[:success] = build_update_for_success(options[:update][:success], options[:position]) << (options[:success] ? options[:success] : '')
          end
          if options[:update][:error]
            options[:error] = build_update_for_error(options[:update][:error], options[:position]) << (options[:error] ? options[:error] : '')
          end
        else
          options[:success] = build_update_for_success(options[:update], options[:position]) << (options[:success] ? options[:success] : '')
        end
      end
      options.each do |callback, code|
        if JQCALLBACKS.include?(callback)
          callbacks[callback] = "function(request){#{code}}"
        end
      end
      callbacks
    end
      
  end
end

