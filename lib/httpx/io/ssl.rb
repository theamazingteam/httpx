# frozen_string_literal: true

require "openssl"

module HTTPX
  TLSError = OpenSSL::SSL::SSLError
  IPRegex = Regexp.union(Resolv::IPv4::Regex, Resolv::IPv6::Regex)

  class SSL < TCP
    using RegexpExtensions unless Regexp.method_defined?(:match?)

    TLS_OPTIONS = if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
      { alpn_protocols: %w[h2 http/1.1].freeze }
    else
      {}
    end
    # https://github.com/jruby/jruby-openssl/issues/284
    TLS_OPTIONS[:verify_hostname] = true if RUBY_ENGINE == "jruby"
    TLS_OPTIONS.freeze

    attr_writer :ssl_session

    def initialize(_, _, options)
      super

      ctx_options = TLS_OPTIONS.merge(options.ssl)
      @sni_hostname = ctx_options.delete(:hostname) || @hostname

      if @keep_open && @io.is_a?(OpenSSL::SSL::SSLSocket)
        # externally initiated ssl socket
        @ctx = @io.context
        @state = :negotiated
      else
        @ctx = OpenSSL::SSL::SSLContext.new
        @ctx.set_params(ctx_options) unless ctx_options.empty?
        unless @ctx.session_cache_mode.nil? # a dummy method on JRuby
          @ctx.session_cache_mode =
            OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT | OpenSSL::SSL::SSLContext::SESSION_CACHE_NO_INTERNAL_STORE
        end

        yield(self) if block_given?
      end

      @hostname_is_ip = IPRegex.match?(@sni_hostname)
      @verify_hostname = @ctx.verify_hostname
    end

    if OpenSSL::SSL::SSLContext.method_defined?(:session_new_cb=)
      def session_new_cb(&pr)
        @ctx.session_new_cb = proc { |_, sess| pr.call(sess) }
      end
    else
      # session_new_cb not implemented under JRuby
      def session_new_cb; end
    end

    def protocol
      @io.alpn_protocol || super
    rescue StandardError
      super
    end

    def can_verify_peer?
      @ctx.verify_mode == OpenSSL::SSL::VERIFY_PEER
    end

    def verify_hostname(host)
      return false if @ctx.verify_mode == OpenSSL::SSL::VERIFY_NONE
      return false if !@io.respond_to?(:peer_cert) || @io.peer_cert.nil?

      OpenSSL::SSL.verify_certificate_identity(@io.peer_cert, host)
    end

    def connected?
      @state == :negotiated
    end

    def expired?
      super || ssl_session_expired?
    end

    def ssl_session_expired?
      @ssl_session.nil? || Process.clock_gettime(Process::CLOCK_REALTIME) >= (@ssl_session.time.to_f + @ssl_session.timeout)
    end

    def connect
      super
      return if @state == :negotiated ||
                @state != :connected

      unless @io.is_a?(OpenSSL::SSL::SSLSocket)
        if @hostname_is_ip
          # IP addresses in SNI is not valid per RFC 6066, section 3.
          @ctx.verify_hostname = false
        end

        @io = OpenSSL::SSL::SSLSocket.new(@io, @ctx)

        @io.hostname = @sni_hostname unless @hostname_is_ip
        @io.session = @ssl_session unless ssl_session_expired?
        @io.sync_close = true
      end
      try_ssl_connect
    end

    if RUBY_VERSION < "2.3"
      # :nocov:
      def try_ssl_connect
        @io.connect_nonblock
        @io.post_connection_check(@sni_hostname) if @ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE && @verify_hostname
        transition(:negotiated)
        @interests = :w
      rescue ::IO::WaitReadable
        @interests = :r
      rescue ::IO::WaitWritable
        @interests = :w
      end

      def read(_, buffer)
        super
      rescue ::IO::WaitWritable
        buffer.clear
        0
      end

      def write(*)
        super
      rescue ::IO::WaitReadable
        0
      end
      # :nocov:
    else
      def try_ssl_connect
        case @io.connect_nonblock(exception: false)
        when :wait_readable
          @interests = :r
          return
        when :wait_writable
          @interests = :w
          return
        end
        @io.post_connection_check(@sni_hostname) if @ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE && @verify_hostname
        transition(:negotiated)
        @interests = :w
      end

      # :nocov:
      if OpenSSL::VERSION < "2.0.6"
        def read(size, buffer)
          @io.read_nonblock(size, buffer)
          buffer.bytesize
        rescue ::IO::WaitReadable,
               ::IO::WaitWritable
          buffer.clear
          0
        rescue EOFError
          nil
        end
      end
      # :nocov:
    end

    private

    def transition(nextstate)
      case nextstate
      when :negotiated
        return unless @state == :connected

      when :closed
        return unless @state == :negotiated ||
                      @state == :connected
      end
      do_transition(nextstate)
    end

    def log_transition_state(nextstate)
      return super unless nextstate == :negotiated

      server_cert = @io.peer_cert

      "#{super}\n\n" \
        "SSL connection using #{@io.ssl_version} / #{Array(@io.cipher).first}\n" \
        "ALPN, server accepted to use #{protocol}\n" \
        "Server certificate:\n " \
        "subject: #{server_cert.subject}\n " \
        "start date: #{server_cert.not_before}\n " \
        "expire date: #{server_cert.not_after}\n " \
        "issuer: #{server_cert.issuer}\n " \
        "SSL certificate verify ok."
    end
  end
end
