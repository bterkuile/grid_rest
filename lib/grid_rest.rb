require 'rest_client'
require 'active_support/all'
require 'grid_rest/engine'
module GridRest 
  RESERVED_REQUEST_PARAMETERS = %w[accept content_type headers method url payload timeout open_timeout raw_response verify_ssl ssl_client_cert ssl_client_key ssl_ca_file cookie cookies accept_encoding]
  mattr_accessor :grid_config, :log_file, :additional_parameters
  self.additional_parameters = { :default => {:global => {}, :get => {}, :post => {}, :put => {}, :delete => {}} }
  class GridConfig < HashWithIndifferentAccess
    # This allows for method like calling of the configuration. For example:
    #   GridRest.grid_config.host
    # or
    #   GridRest.grid_config.namespaces 
    def method_missing(m, *args)
      return self.send('[]=', m.to_s.chop, args.first) if m.to_s.last == '=' && args.size == 1
      return self.send('[]', m)
    end
  end
  self.grid_config = GridConfig.new

  def self.include_in(klass)
    klass.send(:include, GridRestExtensions)
    self.grid_config.namespaces.keys.each do |k|
      klass.send(:class_eval, namespace_methods(k))
    end
  end

  def self.default_parameters(params, type = :global, namespace = :default)
    additional_parameters[namespace][type].update(params)
  end

  def self.extend_class(klass)
    klass.send(:extend, GridRestExtensions)
    self.grid_config.namespaces.keys.each do |k|
      klass.send(:class_eval, "class << self; #{namespace_methods(k)}; end")
    end
  end
  def self.namespace_methods(namespace)
    expand_str = <<-END
      def #{namespace}_get(url, rparams = {})
        grid_rest_get(url, rparams.merge(:grid_rest_namespace => '#{namespace}'))
      end
      def #{namespace}_post(url, rparams = {})
        grid_rest_post(url, rparams.merge(:grid_rest_namespace => '#{namespace}'))
      end
      def #{namespace}_put(url, rparams = {})
        grid_rest_put(url, rparams.merge(:grid_rest_namespace => '#{namespace}'))
      end
      def #{namespace}_delete(url, rparams = {})
        grid_rest_delete(url, rparams.merge(:grid_rest_namespace => '#{namespace}'))
      end
      def #{namespace}_default_parameters(params, request_types = :global)
        set_namespaced_default_grid_rest_parameters(:#{namespace}, params, request_types)
      end
      alias_method :set_#{namespace}_default_parameters, :#{namespace}_default_parameters
    END
  end

  # Very important method. This will set the appropriate settings for the current
  # rails environment and appends this system to the specified classes
  def self.load_config!
    config_path = File.join(Rails.root, 'config', 'grid_rest.yml')
    raise "File #{config_path} does not exist" unless File.exist?(config_path)
    h = YAML::load_file(config_path) rescue nil
    raise "Config file #{config_path} could not be parsed" unless h
    raise "Config file #{config_path} needs an environment" unless h[Rails.env]
    self.grid_config.namespaces = HashWithIndifferentAccess.new unless self.grid_config.namespaces.is_a?(Hash)
    h[Rails.env].each do |k, v|
      if v.is_a?(Hash)
        self.grid_config.namespaces[k.to_sym] = HashWithIndifferentAccess.new(v)
      else
        self.grid_config[k.to_sym] = v
      end
    end

    # Now extend/include in configured classes
    for inclusion in Array.wrap(h['include_in'])
      self.include_in inclusion.constantize
    end
    for extension in Array.wrap(h['extend'])
      self.extend_class extension.constantize
    end
  end
  module GridRestExtensions
    include ActiveSupport::Benchmarkable
    unless respond_to?(:logger)
      def logger
        Rails.logger
      end
    end
    # This one is on the deprication list
    def grid_rest?(rparams = {})
      ns = rparams[:grid_rest_namespace].present? ? "grid_rest_#{rparams[:grid_rest_namespace]}" : 'grid_rest'
      raise "APP_CONFIG not available, make sure that config/config.yml and config/initializers/load_config.rb are available" unless defined?(APP_CONFIG)
      raise "Namespace #{ns} not available in config/config.yml" unless APP_CONFIG[ns]
      @grid_rest_active ||= Net::HTTP.new(APP_CONFIG[ns]['host'], APP_CONFIG[ns]['port']).start rescue nil
    end

    # This will get the current namespace or nil during grid_rest_request processing
    def current_namespace
      @current_namespace
    end

    # Global setter valid for all request/namespaces
    def default_grid_rest_parameters(params, request_types = :global)
      set_namespaced_default_grid_rest_parameters(:default, params, request_types)
    end
    alias_method :set_default_grid_rest_parameters, :default_grid_rest_parameters

    # Return an array of additional parameters. This request is namespace aware
    # It will return an array given the additional default parameters for:
    #  ALL, GET, POST, PUT and DELETE
    # requests in that order
    def get_additional_grid_rest_parameters
      globals = get_request_specific_additional_grid_rest_parameters(:global)
      return [
        globals,
        globals.merge(get_request_specific_additional_grid_rest_parameters(:get)),
        globals.merge(get_request_specific_additional_grid_rest_parameters(:post)),
        globals.merge(get_request_specific_additional_grid_rest_parameters(:put)),
        globals.merge(get_request_specific_additional_grid_rest_parameters(:delete))
      ]
    end

    # Get all the global parameters. The defaults, extended/overwritten by the
    # namespace specific ones
    def get_request_specific_additional_grid_rest_parameters(request = :global)
      if current_namespace
        additional_grid_rest_parameters[:default][request].merge(additional_grid_rest_parameters[current_namespace.to_sym][request] || {})
      else
        additional_grid_rest_parameters[:default][request]
      end
    end

    # Getter of additional parameters. Contains defaults and namespace specific versions
    def additional_grid_rest_parameters
      GridRest.additional_parameters
    end
    
    def set_namespaced_default_grid_rest_parameters(ns, params, request_types = :global)
      additional_grid_rest_parameters[ns] ||= {}
      for request_type in Array.wrap(request_types).map(&:to_sym)
        additional_grid_rest_parameters[ns][request_type] ||= {}
        additional_grid_rest_parameters[ns][request_type].update(params)
      end
    end

    # Wrapper for grid_rest_log_message to write a log message in a consitant manner given the request parameters
    def grid_rest_log(method, url, rparams = {}, emsg = "")
      if current_namespace
        return unless GridRest.grid_config.namespaces[current_namespace]['logging']
      else
        return unless GridRest.grid_config['logging']
      end
      grid_rest_log_message(rparams.any? ? "#{Time.now.to_s(:db)} #{method.to_s.upcase} #{url} with #{rparams.inspect} #{emsg}" : "#{Time.now.to_s(:db)} #{method.to_s.upcase} #{url} #{emsg}")
    end

    # Write msg to the log file. Should only be called from grid_rest_log unless you know what you are doing
    def grid_rest_log_message(msg)
      GridRest.log_file ||= File.open(File.join(Rails.root, 'log', "#{Rails.env}_grid_rest.log"), 'a+')
      GridRest.log_file.puts msg
      GridRest.log_file.flush unless Rails.env == 'production'
    end

    def grid_rest_request(method, relative_url, rparams = {})
      #return DummyResponse.new # test return
      rest_url = generate_url(relative_url, rparams) 
      #return Error.new('unavailable', :url => rest_url) unless grid_rest?(rparams)
      # Specify defaults per method for format
      format = rparams.delete(:format) || {:get => :json, :post => :json, :put => :json}[method]
      accept = get_accept_header(format)
      @current_namespace = rparams.delete(:grid_rest_namespace) # Remove this setting from request parameters
      additional_get_parameters, additional_post_parameters, additional_put_parameters, additional_delete_parameters = get_additional_grid_rest_parameters
      begin
        r = benchmark "Fetching #{method.to_s.upcase} #{relative_url} #{rparams.inspect}", :level => :debug do
          case method
            when :get then RestClient.get rest_url, :params => rparams.update(additional_get_parameters), :accept => accept
            when :post then
              if rparams[:json_data]
                rparams[:json_data] = rparams[:json_data].merge(additional_post_parameters).to_json if rparams[:json_data].is_a?(Hash)
                RestClient.post rest_url, rparams[:json_data], :content_type => :json, :accept => :json
              elsif rparams[:xml_data]
                rparams[:xml_data] = rparams[:xml_data].merge(additional_post_parameters).to_xml if rparams[:xml_data].is_a?(Hash)
                RestClient.post rest_url, rparams[:xml_data], :content_type => :xml, :accept => :xml
              elsif rparams[:binary]
                RestClient.post rest_url, rparams[:binary], :content_type => 'binary/octet-stream'
              else
                rparams[:headers] ||= {}
                rparams[:headers][:accept] = accept
                rparams[:multipart] = true
                RestClient.post rest_url, rparams.update(additional_post_parameters)
              end
            when :put then
              if rparams[:json_data]
                rparams[:json_data] = rparams[:json_data].merge(additional_put_parameters).to_json if rparams[:json_data].is_a?(Hash)
                RestClient.put rest_url, rparams[:json_data], :content_type => :json, :accept => :json
              elsif rparams[:xml_data]
                rparams[:xml_data] = rparams[:xml_data].merge(additional_put_parameters).to_xml if rparams[:xml_data].is_a?(Hash)
                RestClient.put rest_url, rparams[:xml_data], :content_type => :xml, :accept => :xml
              elsif rparams[:binary]
                RestClient.put rest_url, rparams[:binary], :content_type => 'binary/octet-stream'
              else
                rparams[:headers] ||= {}
                rparams[:headers][:accept] = accept
                rparams[:multipart] = true
                RestClient.put rest_url, rparams.update(additional_put_parameters)
              end
            when :delete then
              rparams[:headers] ||= {}
              rparams[:headers][:accept] = accept
              new_uri = add_parameters_to_uri(rest_url, rparams.update(additional_delete_parameters))
              RestClient.delete(new_uri, rparams)
            else
              raise "No proper method (#{method}) for a grid_rest_request call"
            end
          end
        grid_rest_log method, rest_url, rparams, "response code: #{r.code}"
        if format == :json
          #r = benchmark("decoding response JSON", :level => :debug ){ ActiveSupport::JSON.decode(r.body) rescue r } # Slow
          r = benchmark("decoding response JSON", :level => :debug ){ JSON.parse(r.body) rescue r }
        end
        # Singleton class extensions
        r = "" if r == false # RestClient problem giving false on empty 204
        def r.valid?
          true
        end
      rescue RestClient::ResourceNotFound => e
        r = Error.new(e, :url => rest_url, :method => method)
        grid_rest_log method, rest_url, rparams, "resource not found response"
      rescue Errno::ECONNREFUSED => e
        r = Error.new(e, :url => rest_url, :method => method)
        grid_rest_log method, rest_url, rparams, "connection refused response"
      rescue => e
        r = Error.new e, :url => rest_url, :method => method 
        grid_rest_log method, rest_url, rparams, "error in request"
      end
      r
    end

    def add_parameters_to_uri(uri, params)
      uri << '?' unless uri.include?('?')
      uri << '&' unless ['?', '&'].include?(uri.last)
      uri_params = params.reject{|k, v| RESERVED_REQUEST_PARAMETERS.include?(k.to_s)}
      uri << uri_params.map{|k, v| URI.encode("#{k}=#{v}")}.join('&')
      uri_params.each{|k, v| params.delete(k)} # Remove added get parameters from the header params
      uri
    end

    def generate_url(url, rparams = {})
      host = GridRest.grid_config.namespaces[rparams[:grid_rest_namespace]].try('[]', 'host') || GridRest.grid_config['host']
      port = GridRest.grid_config.namespaces[rparams[:grid_rest_namespace]].try('[]', 'port') || GridRest.grid_config['port'] || 80
      url_prefix = GridRest.grid_config.namespaces[rparams[:grid_rest_namespace]].try('[]', 'url_prefix') || GridRest.grid_config['url_prefix'] || ''
      raise "No host specified for GridRest" unless host
      gurl = File.join( "#{host}:#{port}", url_prefix, URI.encode(url) )
      gurl = "http://#{gurl}" unless gurl =~ /^http/
      gurl
    end

    def grid_rest_get(url, rparams = {})
      return grid_rest_request(:get, url, rparams)
    end

    def grid_rest_put(url, rparams = {})
      grid_rest_request(:put, url, rparams)
    end

    def grid_rest_delete(url, rparams = {})
      grid_rest_request(:delete, url, rparams)
    end
    def grid_rest_post(url, rparams={})
      return grid_rest_request(:post, url, rparams)
    end
    def get_accept_header(f)
      case f
      when :json then :json #'application/json'
      when :xml then :xml #'application/xml'
      else :json #'application/json'
      end
    end
  end

  # Error class for a rest request. Has some nice features like
  # internationalisation of messages, and basic methods to correspond
  # with a normal request, but most importantly returns false on the 
  # valid? question.
  class Error
    attr_reader :message, :code, :url, :request_method, :response, :type
    def initialize(e, rparams)
      @request_method = rparams.delete(:request_method) || rparams.delete(:method)
      @code = e.respond_to?(:http_code) ? e.http_code : (rparams.delete(:code) || 500)
      @response = e.response if e.respond_to?(:response)
      @type = e.class.name.split('::').last
      @message = I18n.t(@type, :scope => [:grid_rest, :message], :default => nil)
      @url = rparams.delete(:url)
    end

    def code
      @code || 500
    end
    def to_s
      ''
    end
    alias to_str to_s

    def valid?
      false
    end

    def try(m, *args)
      return send(m, *args) if respond_to?(m)
      # Behave like a nil object otherwise
      nil
    end

    # Call this on error if the result should be an empty array, but wit the
    # invalid metadata
    def array
      ErrorArray.new(self)
    end
  end

  class ErrorArray < Array
    attr_reader :message, :code, :url, :request_method, :response
    def initialize(e)
      @message = e.message
      @code = e.code
      @url = e.url
      @request_method = e.request_method
      @response = e.response
    end
    def to_s
      ''
    end
    alias to_str to_s
    def valid?
      false
    end
    def try(m, *args)
      return send(m, *args) if respond_to?(m)
      # Behave like a nil object otherwise
      nil
    end
  end

  # This class can be used in testing environments. It will always be valid and behaves a 
  # bit like a normal response when this is a json hash.
  class DummyResponse < Hash
    def code
      200
    end
    def valid?
      true
    end
  end
end

# Arrays are valid, unless defined otherwise
class Object
  def valid?
    true
  end
  def invalid?
    !valid?
  end
end

class NilClass
  def valid?
    false
  end
end

class FalseClass
  def valid?
    false
  end
end
