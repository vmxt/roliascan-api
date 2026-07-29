# frozen_string_literal: true

require "cgi"
require "digest"
require "json"
require "uri"

require_relative "cache_store"
require_relative "config"
require_relative "http_client"

class BrowseScraper
  class ScrapeError < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  LOAD_ENDPOINT = "/wp-json/manga/v1/load"
  DEFAULT_PAGE = 1
  PAGE_SIZE = 24
  GENRE_MATCH_MODES = %w[any all].freeze
  TYPES = %w[Manga Manhwa Manhua Novel].freeze
  STATUSES = %w[Cancelled Completed Hiatus Ongoing].freeze
  ORDER_MAP = {
    "latest" => "post_desc",
    "oldest" => "post_asc",
    "a-z" => "title_asc",
    "z-a" => "title_desc",
    "title" => "title_asc",
    "popular" => "popular_desc",
    "release" => "release_desc",
    "release-asc" => "release_asc"
  }.freeze
  VALID_SORTS = %w[
    post_desc
    post_asc
    release_desc
    release_asc
    title_desc
    title_asc
    popular_desc
    popular_asc
  ].freeze

  def initialize(client: HttpClient.new, cache: CacheStore.new(ttl: Config::CACHE_TTL))
    @client = client
    @cache = cache
  end

  def browse(params = {})
    filters = filters_for(params)
    payload = upstream_payload(filters)

    @cache.fetch("browse:v2:#{cache_digest(payload)}") do
      json = @client.post_json(
        LOAD_ENDPOINT,
        json: payload,
        headers: { "Referer" => "#{Config::BASE_URL}/browse/" }
      )

      build_response(json, filters)
    end
  rescue HttpClient::Error => e
    raise ScrapeError.new(e.message, status: e.status)
  end

  def parse_browse_json(json)
    return [] unless json.is_a?(Array)

    Array(json).filter_map { |item| browse_item(item) }
  end

  private

  def filters_for(params)
    params = stringify_keys(params)

    {
      page: positive_integer(params["page"], default: DEFAULT_PAGE),
      search: normalize_text(first_present(params, "title", "search", "keyword", "q")),
      years: integer_list(first_present(params, "year", "years")),
      genres: integer_list(first_present(params, "genre", "genres", "tags")),
      types: enum_list(first_present(params, "type", "types"), TYPES),
      statuses: enum_list(first_present(params, "status", "statuses"), STATUSES),
      sort: sort_for(first_present(params, "order", "sort")),
      genre_match_mode: genre_match_mode_for(first_present(params, "match", "genre_match_mode", "genreMatchMode"))
    }
  end

  def upstream_payload(filters)
    {
      page: filters[:page],
      search: filters[:search],
      years: JSON.generate(filters[:years]),
      genres: JSON.generate(filters[:genres]),
      types: JSON.generate(filters[:types]),
      statuses: JSON.generate(filters[:statuses]),
      sort: filters[:sort],
      genreMatchMode: filters[:genre_match_mode]
    }
  end

  def build_response(json, filters)
    results = parse_browse_json(json)
    has_next_page = results.length >= PAGE_SIZE

    {
      page: filters[:page],
      next_page: has_next_page ? filters[:page] + 1 : nil,
      has_next_page: has_next_page,
      count: results.length,
      filters: filters.reject { |_key, value| blank?(value) },
      results: results
    }
  end

  def browse_item(item)
    return nil unless item.is_a?(Hash)

    url = normalize_text(item["url"] || item["permalink"])
    slug = first_nonblank(id_from_url(url), item["slug"], item["id"])

    result = {
      id: slug,
      title: normalize_text(item["title"]),
      image: normalize_text(item["cover"] || item["thumbnail"] || item["image"]),
      type: normalize_text(item["type"] || item["manga_type"]),
      year: normalize_text(item["year"]),
      status: normalize_text(item["status"]),
      chapter_count: normalize_text(item["chapters"] || item["chapter_count"]),
      description: normalize_text(item["description"] || item["synopsis"]),
      updated_at: normalize_text(item["time_ago"] || item["updated_at"] || item["updated"])
    }.reject { |_key, value| blank?(value) }

    return nil if blank?(result[:id]) && blank?(result[:title])

    result
  end

  def first_nonblank(*values)
    values.each do |value|
      text = normalize_text(value)
      return text unless text.empty?
    end

    nil
  end

  def stringify_keys(hash)
    hash.to_h.transform_keys(&:to_s)
  end

  def first_present(params, *keys)
    keys.each do |key|
      value = params[key]
      return value unless blank?(value)
    end

    nil
  end

  def positive_integer(value, default:)
    parsed = Integer(value, exception: false)
    return default unless parsed && parsed.positive?

    parsed
  end

  def integer_list(value)
    raw_values(value).filter_map { |item| Integer(item, exception: false) }
  end

  def enum_list(value, allowed_values)
    allowed_by_key = allowed_values.to_h { |allowed| [allowed.downcase, allowed] }

    raw_values(value).filter_map do |item|
      allowed_by_key[normalize_text(item).downcase]
    end
  end

  def raw_values(value)
    return [] if blank?(value)
    return value.flat_map { |item| raw_values(item) } if value.is_a?(Array)

    text = decode_value(value)
    parsed_json_values(text) || text.split(",").map(&:strip).reject(&:empty?)
  end

  def parsed_json_values(text)
    return nil unless text.start_with?("[")

    parsed = JSON.parse(text)
    return raw_values(parsed) if parsed.is_a?(Array)

    nil
  rescue JSON::ParserError
    nil
  end

  def sort_for(value)
    sort = normalize_text(value).downcase
    mapped = ORDER_MAP.fetch(sort, sort)

    VALID_SORTS.include?(mapped) ? mapped : "post_desc"
  end

  def genre_match_mode_for(value)
    mode = normalize_text(value).downcase
    GENRE_MATCH_MODES.include?(mode) ? mode : "any"
  end

  def cache_digest(payload)
    Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  def id_from_url(url)
    return nil if blank?(url)

    segments = URI.parse(url).path.split("/").reject(&:empty?)
    manga_index = segments.index("manga")
    return nil unless manga_index

    segments[manga_index + 1]
  rescue URI::InvalidURIError
    nil
  end

  def decode_value(value)
    URI.decode_www_form_component(value.to_s)
  rescue ArgumentError
    value.to_s
  end

  def normalize_text(value)
    text = value.respond_to?(:text) ? value.text : value.to_s
    CGI.unescapeHTML(text).gsub(/\u00a0/, " ").gsub(/\s+/, " ").strip
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
end
