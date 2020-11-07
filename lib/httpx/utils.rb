# frozen_string_literal: true

module HTTPX
  module Utils
    using URIExtensions

    module_function

    # The value of this field can be either an HTTP-date or a number of
    # seconds to delay after the response is received.
    def parse_retry_after(retry_after)
      # first: bet on it being an integer
      Integer(retry_after)
    rescue ArgumentError
      # Then it's a datetime
      time = Time.httpdate(retry_after)
      time - Time.now
    end

    if RUBY_VERSION < "2.3"
      def uri(*args)
        URI(*args)
      end
    else

      URIParser = URI::RFC2396_Parser.new

      def uri(uri)
        return Kernel.URI(uri) unless uri.is_a?(String) && !uri.ascii_only?

        uri = Kernel.URI(URIParser.escape(uri))

        non_ascii_hostname = URIParser.unescape(uri.host)

        non_ascii_hostname.force_encoding(Encoding::UTF8) if RUBY_ENGINE == "jruby"

        idna_hostname = DomainName.new(non_ascii_hostname).hostname

        uri.host = idna_hostname
        uri.non_ascii_hostname = non_ascii_hostname
        uri
      end
    end
  end
end
