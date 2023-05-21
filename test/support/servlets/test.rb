# frozen_string_literal: true

require "logger"

class TestServer < WEBrick::HTTPServer
  def initialize(options = {})
    super({
      :BindAddress => "127.0.0.1",
      :Port => 0,
      :AccessLog => File.new(File::NULL),
      :Logger => Logger.new(File::NULL),
    }.merge(options))
  end

  def origin
    sock = listeners.first
    _, sock, ip, _ = sock.addr
    "http://#{ip}:#{sock}"
  end
end

class TestHTTP2Server
  attr_reader :origin

  def initialize
    @port = 0
    @host = "localhost"

    @server = TCPServer.new(0)

    @origin = "https://localhost:#{@server.addr[1]}"

    ctx = OpenSSL::SSL::SSLContext.new

    certs_dir = File.expand_path(File.join("..", "..", "ci", "certs"), __FILE__)

    ctx.ca_file = File.join(certs_dir, "ca-bundle.crt")
    ctx.cert = OpenSSL::X509::Certificate.new(File.read(File.join(certs_dir, "server.crt")))
    ctx.key = OpenSSL::PKey.read(File.read(File.join(certs_dir, "server.key")))

    ctx.ssl_version = :TLSv1_2
    ctx.alpn_protocols = ["h2"]

    ctx.alpn_select_cb = lambda do |protocols|
      raise "Protocol h2 is required" unless protocols.include?("h2")

      "h2"
    end

    @server = OpenSSL::SSL::SSLServer.new(@server, ctx)
  end

  def shutdown
    @server.close
  end

  def start
    begin
      loop do
        sock = @server.accept

        conn = HTTP2Next::Server.new
        handle_connection(conn, sock)
        handle_socket(conn, sock)
      end
    rescue IOError
    end
  end

  private

  def handle_stream(_conn, stream)
    stream.on(:half_close) do
      response = "OK"
      stream.headers({
                       ":status" => "200",
                       "content-length" => response.bytesize.to_s,
                       "content-type" => "text/plain",
                     }, end_stream: false)
      stream.data(response, end_stream: true)
    end
  end

  def handle_connection(conn, sock)
    conn.on(:frame) do |bytes|
      # puts "Sending bytes: #{bytes.unpack("H*").first}"
      sock.print bytes
      sock.flush
    end

    conn.on(:goaway) do
      sock.close
    end
    conn.on(:stream) do |stream|
      handle_stream(conn, stream)
    end
  end

  def handle_socket(conn, sock)
    while !sock.closed? && !(sock.eof? rescue true) # rubocop:disable Style/RescueModifier
      data = sock.readpartial(1024)
      # puts "Received bytes: #{data.unpack("H*").first}"

      begin
        conn << data
      rescue StandardError => e
        puts "#{e.class} exception: #{e.message} - closing socket."
        puts e.backtrace
        sock.close
      end
    end
  end
end

class TestDNSResolver
  attr_reader :queries, :answers

  def initialize(timeout)
    @port = next_available_port
    @can_log = ENV.key?("HTTPX_DEBUG")
    @timeout = timeout
    @queries = 0
    @answers = 0
  end

  def nameserver
    ["127.0.0.1", @port]
  end

  def start
    Socket.udp_server_loop(@port) do |query, src|
      @queries += 1
      sleep(@timeout)
      src.reply(dns_response(query))
      @answers += 1
    end
  end

  private

  def extract_domain(data)
    domain = +""

    # Check "Opcode" of question header for valid question
    if (data[2].ord & 120).zero?
      # Read QNAME section of question section
      # DNS header section is 12 bytes long, so data starts at offset 12

      idx = 12
      len = data[idx].ord
      # Strings are rendered as a byte containing length, then text.. repeat until length of 0
      until len.zero?
        domain << "#{data[idx + 1, len]}."
        idx += len + 1
        len = data[idx].ord
      end
    end
    domain
  end

  def next_available_port
    udp = UDPSocket.new
    udp.bind("127.0.0.1", 0)
    udp.addr[1]
  ensure
    udp.close
  end
end
