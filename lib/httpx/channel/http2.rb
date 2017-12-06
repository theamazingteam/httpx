# frozen_string_literal: true
require "http/2"

module HTTPX
  class Channel::HTTP2
    include Callbacks

    def initialize(buffer)
      init_connection
      @pending = []
      @streams = {}
      @buffer = buffer
    end

    def close
      @connection.goaway
    end

    def empty?
      @streams.empty?
    end

    def <<(data)
      @connection << data
    end

    def send(request)
      # if @connection.active_stream_count >= @connection.remote_settings[:settings_max_concurrent_streams]
      #   @pending << request
      #   return
      # end
      stream = @connection.new_stream
      stream.on(:close) do |error|
        response = @streams.delete(stream.id) ||
                   ErrorResponse.new(error)
        emit(:response, request, response)

        send(@pending.shift) unless @pending.empty?
      end
      # stream.on(:half_close)
      # stream.on(:altsvc)
      stream.on(:headers) do |headers|
        _, status = headers.shift
        @streams[stream.id] = Response.new(status, headers)
      end
      stream.on(:data) do |data|
        @streams[stream.id] << data
      end
      join_headers(stream, request)
      join_body(stream, request)
    end

    def reenqueue!
      requests = @streams.values
      @streams.clear
      init_connection
      requests.each do |request|
        send(request)
      end
    end

    private

    def init_connection
      @connection = HTTP2::Client.new
      @connection.on(:frame, &method(:on_frame))
      @connection.on(:frame_sent, &method(:on_frame_sent))
      @connection.on(:frame_received, &method(:on_frame_received))
      @connection.on(:promise, &method(:on_promise))
      @connection.on(:altsvc, &method(:on_altsvc))
    end

    def join_headers(stream, request)
      headers = {}
      headers[":scheme"]    = request.scheme
      headers[":method"]    = request.verb.to_s.upcase
      headers[":path"]      = request.path 
      headers[":authority"] = request.authority 
      headers = headers.merge(request.headers)
      stream.headers(headers, end_stream: !request.body)
    end

    def join_body(stream, request)
      return unless request.body
      request.body.each do |chunk|
        stream.data(chunk, end_stream: false)
      end
      stream.data("", end_stream: true)
    end

    ######
    # HTTP/2 Callbacks
    ######

    def on_frame(bytes)
      @buffer << bytes
    end

    def on_frame_sent(frame)
      log { "frame was sent!" }
      log do
        case frame[:type]
        when :data
          frame.merge(payload: frame[:payload].bytesize).inspect
        when :headers
          "\e[33m#{frame.inspect}\e[0m"
        else
          frame.inspect
        end
      end
    end

    def on_frame_received(frame)
      log { "frame was received" }
      log do
        case frame[:type]
        when :data
          frame.merge(payload: frame[:payload].bytesize).inspect
        else
          frame.inspect
        end
      end
    end

    def on_altsvc(frame)
      log { "altsvc frame was received" }
      log { frame.inspect }
    end

    def on_promise(stream)
      stream.refuse
      # TODO: policy for handling promises
    end

    def log(&msg)
      return unless $HTTPX_DEBUG
      $stderr << (+"connection (HTTP/2): " << msg.call << "\n")
    end
  end
end
