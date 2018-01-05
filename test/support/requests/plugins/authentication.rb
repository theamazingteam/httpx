# frozen_string_literal: true

module Requests
  module Plugins
    module Authentication
      def test_plugin_basic_authentication
        no_auth_response = HTTPX.get(basic_auth_uri)
        verify_status(no_auth_response.status, 401)
        verify_header(no_auth_response.headers, "www-authenticate", "Basic realm=\"Fake Realm\"") 

        client = HTTPX.plugin(:basic_authentication)
        response = client.basic_authentication(user, pass).get(basic_auth_uri)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body, "authenticated", true)
        verify_header(body, "user", user)

        invalid_response = client.basic_authentication(user, "fake").get(basic_auth_uri)
        verify_status(invalid_response.status, 401)
      end

      def test_plugin_digest_authentication
        client = HTTPX.plugin(:digest_authentication).headers("cookie" => "fake=fake_value")
        response = client.digest_authentication(user, pass).get(digest_auth_uri)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body, "authenticated", true)
        verify_header(body, "user", user)
      end

      private

      def basic_auth_uri
        build_uri("/basic-auth/#{user}/#{pass}")
      end

      def digest_auth_uri(qop="auth")
        build_uri("/digest-auth/#{qop}/#{user}/#{pass}")
      end

      def user
        "user"
      end

      def pass
        "pass"
      end
    end
  end
end
