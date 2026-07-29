# frozen_string_literal: true

require "cgi"
require "uri"

require_relative "cache_store"
require_relative "config"
require_relative "http_client"

class SearchScraper
  class ScrapeError < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  SEARCH_ENDPOINT = "/auth/search"
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 50

  def initialize(client: HttpClient.new, cache: CacheStore.new(ttl: Config::CACHE_TTL))
    @client = client
    @cache = cache
  end

  def search(keyword, limit: nil)
    query = normalize_text(decode_keyword(keyword))
    raise ScrapeError.new("Search keyword is required", status: 400) if query.empty?

    result_limit = limit_for(limit)

    @cache.fetch("search:v1:#{query.downcase}:#{result_limit}") do
      json = @client.post_json(
        SEARCH_ENDPOINT,
        json: { query: query, limit: result_limit },
        headers: { "Referer" => "#{Config::BASE_URL}/" }
      )

      parse_search_json(json, query)
    end
  rescue HttpClient::Error => e
    raise ScrapeError.new(e.message, status: e.status)
  end

  def parse_search_json(json, keyword = nil)
    return empty_results(keyword) unless json.is_a?(Hash)

    results = Array(json["results"]).filter_map { |item| search_item(item) }

    {
      keyword: normalize_text(json["query"] || keyword),
      count: results.length,
      results: results
    }
  end

  private

  def empty_results(keyword)
    {
      keyword: normalize_text(keyword),
      count: 0,
      results: []
    }
  end

  def search_item(item)
    return nil unless item.respond_to?(:[])

    slug = normalize_text(item["slug"])

    result = {
      id: slug.empty? ? id_from_url(item["permalink"]) : slug,
      title: normalize_text(item["title"]),
      image: normalize_text(item["thumbnail"] || item["cover"] || item["image"]),
      alternative_titles: text_array(item["alt_titles"] || item["alternative_titles"]),
      authors: text_array(item["authors"] || item["author"]),
      description: normalize_text(item["description"] || item["synopsis"]),
      type: normalize_text(item["type"] || item["manga_type"]),
      status: normalize_text(item["status"])
    }.reject { |_key, value| blank?(value) }

    return nil if blank?(result[:id]) && blank?(result[:title])

    result
  end

  def decode_keyword(value)
    URI.decode_www_form_component(value.to_s)
  rescue ArgumentError
    value.to_s
  end

  def limit_for(value)
    parsed = Integer(value || DEFAULT_LIMIT, exception: false) || DEFAULT_LIMIT
    [[parsed, 1].max, MAX_LIMIT].min
  end

  def text_array(value)
    Array(value).map { |item| normalize_text(item) }.reject(&:empty?)
  end

  def id_from_url(url)
    return nil if blank?(url)

    segments = URI.parse(url.to_s).path.split("/").reject(&:empty?)
    manga_index = segments.index("manga")
    return nil unless manga_index

    segments[manga_index + 1]
  rescue URI::InvalidURIError
    nil
  end

  def normalize_text(value)
    text = value.respond_to?(:text) ? value.text : value.to_s
    CGI.unescapeHTML(text).gsub(/\u00a0/, " ").gsub(/\s+/, " ").strip
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
end
