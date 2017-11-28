# frozen_string_literal: true

require_relative "test_helper"

class RequestTest < Minitest::Test
  include HTTPX

  def test_request_verb
    r1 = Request.new(:get, "/")
    assert r1.verb == :get, "unexpected verb (#{r1.verb})"
    r2 = Request.new("GET", "/")
    assert r2.verb == :get, "unexpected verb (#{r1.verb})"
  end

  def test_request_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced" 
  end

  def test_request_body_concat
    assert resource.body.nil?, "body should be nil after init"
    resource << "data"
    assert resource.body == "data", "body should have been updated"
  end

  def test_request_scheme
    r1 = Request.new(:get, "http://google.com/path")
    assert r1.scheme == "http", "unexpected scheme (#{r1.scheme}"
    r2 = Request.new(:get, "https://google.com/path")
    assert r2.scheme == "https", "unexpected scheme (#{r2.scheme}"
  end

  def test_request_authority
    r1 = Request.new(:get, "http://google.com/path")
    assert r1.authority == "google.com", "unexpected authority (#{r1.authority})"
    r2 = Request.new(:get, "http://google.com:80/path")
    assert r2.authority == "google.com", "unexpected authority (#{r2.authority})"
    r3 = Request.new(:get, "http://app.dev:8080/path")
    assert r3.authority == "app.dev:8080", "unexpected authority (#{r3.authority})"
  end

  def test_request_path
    r1 = Request.new(:get, "http://google.com/")
    assert r1.path == "/", "unexpected path (#{r1.path})"
    r2 = Request.new(:get, "http://google.com/path")
    assert r2.path == "/path", "unexpected path (#{r2.path})"
    r3 = Request.new(:get, "http://google.com/path?q=bang&region=eu-west-1")
    assert r3.path == "/path?q=bang&region=eu-west-1", "unexpected path (#{r3.path})"
  end

  private

  def resource
    @resource ||= Request.new(:get, "http://localhost:3000")
  end
end
