# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Proxy
      class Parameters
        extend Registry

        attr_reader :uri, :type, :username, :password

        def initialize(uri: , username: nil, password: nil, type: nil)
          @uri = uri.is_a?(URI::Generic) ? uri : URI(uri)
          @type = type || @uri.scheme
          @username = username || @uri.user
          @password = password || @uri.password
        end

        def authenticated?
          @username && @password 
        end

        def token_authentication
          Base64.strict_encode64("#{user}:#{password}") 
        end
      end

      module InstanceMethods
        def with_proxy(*args)
          branch(default_options.with_proxy(*args))
        end

        private
        
        def proxy_params(uri)
          return @default_options.proxy if @default_options.proxy
          uri = URI(uri).find_proxy
          return unless uri
          { uri: uri }
        end

        def find_channel(request)
          uri = URI(request.uri)
          proxy = proxy_params(uri)
          return super unless proxy 
          @connection.find_channel(proxy) ||
          build_proxy_channel(proxy) 
        end

        def build_proxy_channel(proxy)
          parameters = Parameters.new(**proxy)
          uri = parameters.uri
          io = TCP.new(uri.host, uri.port, @default_options)
          proxy_type = Parameters.registry(parameters.type)
          channel = proxy_type.new(io, parameters, @default_options, &@connection.method(:on_response))
          @connection.__send__(:register_channel, channel)
          channel
        end
      end

      module OptionsMethods
        def self.included(klass)
          super
          klass.def_option(:proxy) do |pr|
            Hash[pr]
          end
        end
      end
 
      def self.configure(klass, *)
        klass.plugin(:"proxy/http")
        klass.plugin(:"proxy/socks")
      end
    end
    register_plugin :proxy, Proxy
  end

  class ProxyChannel < Channel
    def initialize(io, parameters, options)
      super(io, options)
      @parameters = parameters
    end

    def match?(*)
      true
    end
  end

  class ProxySSL < SSL
    def initialize(tcp, request_uri, options)
      @io = tcp.to_io
      super(tcp.ip, tcp.port, options)
      @hostname = request_uri.host
      @state = :connected
    end
  end
end 
