# frozen_string_literal: true

require "forwardable"

module HTTPX::Channel
  PROTOCOLS = {
    "h2" => HTTP2,
    "http/1.1" => HTTP1
  }

  class TCP
    extend Forwardable
    include HTTPX::Callbacks

    BUFFER_SIZE = 1 << 16 

    attr_reader :remote_ip, :remote_port, :protocol

    def_delegator :@io, :to_io
    
    def initialize(uri, options)
      @uri = uri
      @options = HTTPX::Options.new(options)
      @timeout = options.timeout
      @timeout.connect do
        @io = TCPSocket.new(uri.host, uri.port)
      end
      @read_buffer = +""
      @write_buffer = +""
      @protocol = "http/1.1"
    end

    def close
      @processor.close if @processor
      @io.close
    end

    def empty?
      @write_buffer.empty?
    end

    def send(request, &block)
      if @processor.nil?
        @processor = PROTOCOLS[protocol].new(@write_buffer)
        @processor.on(:response, &block)
      end
      @processor.send(request)
    end

    if RUBY_VERSION < "2.3"
      def dread(size = BUFFER_SIZE)
        begin
          loop do
            @io.read_nonblock(size, @read_buffer)
            @processor << @read_buffer
          end
        rescue IO::WaitReadable
          # wait read/write
        rescue EOFError
          # EOF
          throw(:close, self)
        end
      end

      def dwrite
        begin
          loop do
            return if @write_buffer.empty?
            siz = @io.write_nonblock(@write_buffer)
            @write_buffer.slice!(0, siz)
          end
        rescue IO::WaitWritable
          # wait read/write
        rescue EOFError
          # EOF
          throw(:close, self)
        end
      end
    else
      def dread(size = BUFFER_SIZE)
        loop do
          buf = @io.read_nonblock(size, @read_buffer, exception: false)
          case buf
          when :wait_readable
            return
          when nil
            throw(:close, self)
          else
            @processor << @read_buffer
          end
        end
      end

      def dwrite
        loop do
          return if @write_buffer.empty?
          siz = @io.write_nonblock(@write_buffer, exception: false)
          case siz
          when :wait_writable
            return
          when nil
            throw(:close, self)
          else
            @write_buffer.slice!(0, siz)
          end
        end
      end
    end

    private

    def perform_io
      yield
    rescue IO::WaitReadable, IO::WaitWritable
    # wait read/write
    rescue EOFError
      # EOF
      @io.close
    end

  end
end
