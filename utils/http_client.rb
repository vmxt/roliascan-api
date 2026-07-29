# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "config"

class HttpClient
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  DEFAULT_HEADERS = {
    "Accept" => "text/html,application/json;q=0.9,*/*;q=0.8",
    "User-Agent" => "Roliascans-API/1.0"
  }.freeze

  MAX_REDIRECTS = 4

  def get(path_or_url, headers: {}, redirects: MAX_REDIRECTS)
    raise Error.new("Too many redirects while requesting Roliascan") if redirects.negative?

    uri = uri_for(path_or_url)
    request = Net::HTTP::Get.new(uri)
    DEFAULT_HEADERS.merge(headers).each { |key, value| request[key] = value }

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: Config::CONNECT_TIMEOUT,
      read_timeout: Config::REQUEST_TIMEOUT
    ) { |http| http.request(request) }

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      get(response.fetch("location"), headers: headers, redirects: redirects - 1)
    else
      raise Error.new("Roliascan upstream returned HTTP #{response.code}", status: 502)
    end
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    raise Error.new("Could not reach Roliascan: #{e.message}", status: 502)
  end

  def get_json(path_or_url, params: {})
    body = get(url_with_query(path_or_url, params), headers: { "Accept" => "application/json" })
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error.new("Roliascan returned invalid JSON: #{e.message}", status: 502)
  end

  def post_form_json(path_or_url, form: {})
    body = post_form(path_or_url, form: form, headers: { "Accept" => "application/json" })
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error.new("Roliascan returned invalid JSON: #{e.message}", status: 502)
  end

  def post_json(path_or_url, json: {}, headers: {}, redirects: MAX_REDIRECTS)
    raise Error.new("Too many redirects while requesting Roliascan") if redirects.negative?

    uri = uri_for(path_or_url)
    request = Net::HTTP::Post.new(uri)
    request.body = JSON.generate(json)
    DEFAULT_HEADERS
      .merge("Content-Type" => "application/json", "Accept" => "application/json")
      .merge(headers)
      .each { |key, value| request[key] = value }

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: Config::CONNECT_TIMEOUT,
      read_timeout: Config::REQUEST_TIMEOUT
    ) { |http| http.request(request) }

    case response
    when Net::HTTPSuccess
      JSON.parse(response.body)
    when Net::HTTPRedirection
      post_json(response.fetch("location"), json: json, headers: headers, redirects: redirects - 1)
    else
      raise Error.new("Roliascan upstream returned HTTP #{response.code}", status: 502)
    end
  rescue JSON::ParserError => e
    raise Error.new("Roliascan returned invalid JSON: #{e.message}", status: 502)
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    raise Error.new("Could not reach Roliascan: #{e.message}", status: 502)
  end

  def post_form(path_or_url, form: {}, headers: {}, redirects: MAX_REDIRECTS)
    raise Error.new("Too many redirects while requesting Roliascan") if redirects.negative?

    uri = uri_for(path_or_url)
    request = Net::HTTP::Post.new(uri)
    request.body = URI.encode_www_form(form)
    DEFAULT_HEADERS.merge("Content-Type" => "application/x-www-form-urlencoded").merge(headers).each do |key, value|
      request[key] = value
    end

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: Config::CONNECT_TIMEOUT,
      read_timeout: Config::REQUEST_TIMEOUT
    ) { |http| http.request(request) }

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      post_form(response.fetch("location"), form: form, headers: headers, redirects: redirects - 1)
    else
      raise Error.new("Roliascan upstream returned HTTP #{response.code}", status: 502)
    end
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    raise Error.new("Could not reach Roliascan: #{e.message}", status: 502)
  end

  private

  def uri_for(path_or_url)
    uri = URI.parse(path_or_url)
    return uri if uri.absolute?

    URI.join("#{Config::BASE_URL}/", path_or_url)
  end

  def url_with_query(path_or_url, params)
    uri = uri_for(path_or_url)
    query = URI.decode_www_form(uri.query.to_s)

    params.each do |key, value|
      next if value.nil?

      query << [key.to_s, value.to_s]
    end

    uri.query = query.empty? ? nil : URI.encode_www_form(query)
    uri.to_s
  end
end
