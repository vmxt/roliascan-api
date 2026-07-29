# frozen_string_literal: true

require "nokogiri"
require "time"
require "uri"

require_relative "cache_store"
require_relative "config"
require_relative "http_client"

class HomeScraper
  class ScrapeError < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  HOME_PATH = "/home/"
  POPULAR_CHAPTER_PERIODS = { today: "today", week: "week", month: "month" }.freeze
  MANGA_STATUS_FILTERS = {
    reading: "reading",
    completed: "completed",
    plan_to_read: "plan_to_read",
    dropped: "dropped"
  }.freeze
  FOLLOWED_NEW_PERIODS = { seven_days: "7d", one_month: "1m", three_months: "3m" }.freeze
  FOLLOWED_PERIODS = { today: "today", week: "week", month: "month" }.freeze
  POPULAR_MANGA_PERIODS = { today: "day", week: "week", month: "month", all: "all" }.freeze
  HIGH_SCORE_TYPES = { all: "all", manga: "Manga", manhwa: "Manhwa", manhua: "Manhua" }.freeze

  def initialize(client: HttpClient.new, cache: CacheStore.new(ttl: Config::CACHE_TTL), limit: Config::HOME_LIMIT)
    @client = client
    @cache = cache
    @limit = limit
  end

  def home
    @cache.fetch("home:v1:#{@limit}") do
      html = @client.get(HOME_PATH)
      static_sections = parse_home_html(html)

      static_sections.merge(
        source: "#{Config::BASE_URL}#{HOME_PATH}",
        fetched_at: Time.now.utc.iso8601,
        popular_chapters: popular_chapters,
        manga_by_status: manga_by_status,
        most_followed_new_manga: most_followed_new_manga,
        most_followed_manga: most_followed_manga,
        popular_manga: popular_manga,
        high_score_manga: high_score_manga
      )
    end
  rescue HttpClient::Error => e
    raise ScrapeError.new(e.message, status: e.status)
  end

  def parse_home_html(html)
    doc = Nokogiri::HTML(html)

    {
      spotlight_carousel: spotlight_carousel(doc),
      recently_added: recently_added(doc),
      completed_hot: completed_hot(doc),
      recently_added_novels: recently_added_novels(doc)
    }
  end

  private

  def spotlight_carousel(doc)
    doc.css("#featured-carousel .carousel-slide").filter_map do |slide|
      link = slide.at_css('h2 a[href*="/manga/"]') || slide.at_css('a[href*="/manga/"]')
      image = slide.css('a[href*="/manga/"] img[src]').last || slide.at_css("img[src]")
      title = normalize_text(link).empty? ? image&.[]("alt") : link&.text
      genres = slide.xpath(".//div[contains(@class, 'flex-wrap')]//span").map { |node| normalize_text(node) }.reject(&:empty?)

      compact_item(
        id: id_from_url(link&.[]("href")),
        title: clean_title(title),
        image: image&.[]("src"),
        genre: genres
      )
    end
  end

  def recently_added(doc)
    doc.css("#manga-grid > .group").filter_map { |card| chapter_card(card) }
  end

  def recently_added_novels(doc)
    doc.css("#novels-slider-container .slider > .group").filter_map { |card| chapter_card(card) }
  end

  def completed_hot(doc)
    {
      completed: doc.css("#sidebar-completed > a").filter_map { |card| sidebar_card(card) },
      hot: doc.css("#sidebar-hot > a").filter_map { |card| sidebar_card(card) }
    }
  end

  def popular_chapters
    fetch_grouped(
      POPULAR_CHAPTER_PERIODS,
      "/auth/popular-chapters",
      collection_key: "chapters",
      param: "period",
      limit_key: "limit"
    ) { |item| popular_chapter_item(item) }
  end

  def manga_by_status
    fetch_grouped(
      MANGA_STATUS_FILTERS,
      "/auth/manga-status-slider",
      collection_key: "manga",
      param: "status",
      limit_key: "limit"
    ) { |item| status_manga_item(item) }
  end

  def most_followed_new_manga
    fetch_grouped(
      FOLLOWED_NEW_PERIODS,
      "/auth/most-followed-new-manga",
      collection_key: "manga",
      param: "period",
      limit_key: "limit"
    ) { |item| followed_manga_item(item) }
  end

  def most_followed_manga
    fetch_grouped(
      FOLLOWED_PERIODS,
      "/auth/most-followed-manga",
      collection_key: "manga",
      param: "period",
      limit_key: "limit"
    ) { |item| followed_manga_item(item) }
  end

  def popular_manga
    fetch_grouped(
      POPULAR_MANGA_PERIODS,
      "/wp-json/manga/v1/popular",
      collection_key: nil,
      param: "period",
      limit_key: "number"
    ) { |item| typed_manga_item(item) }
  end

  def high_score_manga
    fetch_grouped(
      HIGH_SCORE_TYPES,
      "/wp-json/manga/v1/highscore",
      collection_key: nil,
      param: "type",
      limit_key: "number"
    ) { |item| high_score_item(item) }
  end

  def fetch_grouped(groups, endpoint, collection_key:, param:, limit_key:)
    threads = groups.map do |label, value|
      Thread.new do
        params = { param => value, limit_key => @limit }
        json = @client.get_json(endpoint, params: params)
        collection = collection_key ? json.fetch(collection_key, []) : json
        [label, Array(collection).filter_map { |item| yield(item) }]
      rescue StandardError => e
        warn "[home_scraper] #{endpoint} #{label}: #{e.message}"
        [label, []]
      end
    end

    threads.each_with_object({}) do |thread, result|
      label, items = thread.value
      result[label] = items
    end
  end

  def chapter_card(card)
    manga_link = card.css('a[href*="/manga/"]').find { |link| link.at_css("img[src]") } ||
                 card.css('a[href*="/manga/"]').last
    title_link = card.css('a[href*="/manga/"]').reverse.find { |link| !normalize_text(link).empty? } || manga_link
    image = card.at_css("img[src]")
    chapter_link = card.at_css('a[href*="/read/"]') || card.css("a").find { |link| normalize_text(link).match?(/Ch\.?/i) }
    chapter_date = chapter_link&.parent&.css("span")&.first

    compact_item(
      id: id_from_url(manga_link&.[]("href")),
      title: clean_title(title_link&.[]("title") || image&.[]("alt") || title_link&.text),
      image: image&.[]("src"),
      chapter_id: chapter_id_from_url(chapter_link&.[]("href")) || chapter_number_from_text(chapter_link&.text),
      chapter_date: normalize_text(chapter_date)
    )
  end

  def sidebar_card(card)
    image = card.at_css("img[src]")
    metadata = card.xpath(".//div[contains(@class, 'text-neutral-500')]//span")
    chapter_text = metadata.map { |node| normalize_text(node) }.find { |text| text.match?(/Ch\.?/i) }
    date_text = metadata.map { |node| normalize_text(node) }.reject { |text| text.empty? || text == "|" || text.match?(/Ch\.?/i) }.last

    compact_item(
      id: id_from_url(card["href"]),
      title: clean_title(card.at_css("h3")&.text || image&.[]("alt")),
      image: image&.[]("src"),
      chapter_id: chapter_number_from_text(chapter_text),
      chapter_date: date_text
    )
  end

  def popular_chapter_item(item)
    compact_item(
      id: item["manga_id"] || item["manga_slug"],
      title: clean_title(item["manga_title"]),
      image: item["cover"],
      chapter_id: item["chapter_id"] || chapter_id_from_url(item["chapter_url"])
    )
  end

  def status_manga_item(item)
    compact_item(
      id: item["manga_id"] || id_from_url(item["permalink"]),
      title: clean_title(item["title"]),
      image: item["cover"],
      status_count: item["status_count"]
    )
  end

  def followed_manga_item(item)
    compact_item(
      id: item["manga_id"] || id_from_url(item["permalink"]),
      title: clean_title(item["title"]),
      image: item["cover"],
      follow_count: item["bookmark_count"]
    )
  end

  def typed_manga_item(item)
    compact_item(
      id: id_from_url(item["permalink"]),
      title: clean_title(item["title"]),
      image: item["cover"],
      type: item["manga_type"]
    )
  end

  def high_score_item(item)
    compact_item(
      id: id_from_url(item["permalink"]),
      title: clean_title(item["title"]),
      image: item["cover"],
      type: item["manga_type"]
    )
  end

  def compact_item(item)
    return nil if blank?(item[:id]) || blank?(item[:title])

    item
  end

  def id_from_url(url)
    segments = path_segments(url)
    manga_index = segments.index("manga")
    return segments[manga_index + 1] if manga_index && segments[manga_index + 1]

    read_index = segments.index("read")
    segments[read_index + 1] if read_index && segments[read_index + 1]
  end

  def chapter_id_from_url(url)
    segments = path_segments(url)
    return nil unless segments.include?("read")

    slug = segments.last
    return nil if blank?(slug)

    match = slug.match(/-(\d+)\z/)
    match ? match[1].to_i : slug
  end

  def path_segments(url)
    return [] if blank?(url)

    URI.parse(url).path.split("/").reject(&:empty?)
  rescue URI::InvalidURIError
    []
  end

  def chapter_number_from_text(text)
    match = normalize_text(text).match(/Ch\.?\s*([0-9A-Za-z._-]+)/i)
    match && match[1]
  end

  def clean_title(value)
    normalize_text(value).sub(/\ARead\s+/i, "")
  end

  def normalize_text(value)
    text = value.respond_to?(:text) ? value.text : value.to_s
    text.gsub(/\u00a0/, " ").gsub(/\s+/, " ").strip
  end

  def blank?(value)
    value.nil? || value.respond_to?(:empty?) && value.empty?
  end
end
