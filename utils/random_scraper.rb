# frozen_string_literal: true

require "nokogiri"
require "uri"

require_relative "cache_store"
require_relative "config"
require_relative "http_client"

class RandomScraper
  class ScrapeError < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  RANDOM_POOL_ENDPOINT = "/wp-json/manga/v1/popular"
  RANDOM_POOL_SIZE = 50
  RANDOM_LIMIT = 4

  def initialize(client: HttpClient.new, cache: CacheStore.new(ttl: Config::CACHE_TTL))
    @client = client
    @cache = cache
  end

  def random
    random_pool.sample(RANDOM_LIMIT)
  rescue HttpClient::Error => e
    raise ScrapeError.new(e.message, status: e.status)
  end

  def parse_random_html(html)
    doc = Nokogiri::HTML(html)
    doc.css("#mangaGrid a[href]").first(RANDOM_LIMIT).filter_map { |card| random_card(card) }
  end

  private

  def random_pool
    @cache.fetch("random:pool:v1") do
      json = @client.get_json(RANDOM_POOL_ENDPOINT, params: { period: "all", number: RANDOM_POOL_SIZE })
      Array(json).filter_map { |item| random_item(item) }
    end
  end

  def random_item(item)
    {
      id: id_from_url(item["permalink"] || item["url"]),
      title: normalize_text(item["title"]),
      image: item["cover"],
      type: normalize_text(item["manga_type"] || item["type"]),
      status: normalize_text(item["status"]),
      score: normalize_text(item["score"])
    }.reject { |_key, value| blank?(value) }
  end

  def random_card(card)
    image = card.at_css("img[src]")
    metadata = card.css("span").map { |node| normalize_text(node) }.reject(&:empty?)

    {
      id: id_from_url(card["href"]),
      title: normalize_text(card.at_css("h3") || image&.[]("alt")),
      image: image&.[]("src"),
      type: metadata[0],
      score: metadata[1]
    }.reject { |_key, value| blank?(value) }
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

  def normalize_text(value)
    text = value.respond_to?(:text) ? value.text : value.to_s
    text.gsub(/\u00a0/, " ").gsub(/\s+/, " ").strip
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
end
