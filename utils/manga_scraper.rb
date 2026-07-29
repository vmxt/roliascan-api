# frozen_string_literal: true

require "nokogiri"
require "digest"
require "time"
require "uri"

require_relative "cache_store"
require_relative "config"
require_relative "http_client"

class MangaScraper
  class ScrapeError < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  CHAPTERS_ENDPOINT = "/auth/manga-chapters"
  CHAPTERS_LIMIT = 500
  TOKEN_SECRET_PREFIX = "mng_ch_"

  def initialize(client: HttpClient.new, cache: CacheStore.new(ttl: Config::CACHE_TTL))
    @client = client
    @cache = cache
  end

  def manga(id)
    manga_id = normalize_id(id)

    @cache.fetch("manga:v1:#{manga_id}") do
      path = "/manga/#{manga_id}/"
      html = @client.get(path)
      doc = Nokogiri::HTML(html)

      {
        id: manga_id,
        about: about(doc),
        chapters: chapters_for(doc),
        similar: similar(doc)
      }
    end
  rescue HttpClient::Error => e
    raise ScrapeError.new(e.message, status: e.status)
  end

  def parse_manga_html(html, id: nil)
    doc = Nokogiri::HTML(html)

    {
      id: id || id_from_url(doc.at_css("#share-manga-btn")&.[]("data-manga-url")),
      about: about(doc),
      chapters: chapters(doc),
      similar: similar(doc)
    }
  end

  private

  def normalize_id(id)
    value = id.to_s.strip.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    raise ScrapeError.new("Invalid manga id", status: 400) unless value.match?(/\A[a-zA-Z0-9._-]+\z/)

    value
  end

  def about(doc)
    {
      manga_id: doc.at_css("[data-manga-id]")&.[]("data-manga-id"),
      title: manga_title(doc),
      alternative_titles: alternative_titles(doc),
      image: manga_image(doc),
      type: manga_badges(doc)[0],
      status: manga_badges(doc)[1],
      released: manga_badges(doc)[2],
      rating: normalize_text(doc.at_css(".rating-badge span.font-semibold")),
      views: normalize_text(doc.at_css(".view-info")),
      chapter_count: chapter_count(doc),
      last_updated: last_updated(doc),
      author: author(doc),
      genres: genres(doc),
      description: description(doc)
    }.reject { |_key, value| blank?(value) }
  end

  def manga_title(doc)
    doc.at_css("#share-manga-btn")&.[]("data-manga-title") ||
      normalize_text(doc.at_css("h1"))
  end

  def manga_image(doc)
    doc.at_css("[data-manga-cover]")&.[]("data-manga-cover") ||
      doc.at_css("img[title][src]")&.[]("src") ||
      doc.at_xpath("//img[contains(@alt, 'Cover for') and @src]")&.[]("src")
  end

  def alternative_titles(doc)
    text = normalize_text(doc.at_xpath("(//h1/following-sibling::p[string-length(normalize-space()) > 0])[1]"))
    text.split("|").map { |title| normalize_text(title) }.reject(&:empty?)
  end

  def manga_badges(doc)
    doc.xpath("//div[contains(@class, 'md:hidden')]//span[contains(@class, 'bg-neutral-800/70')]")
       .map { |node| normalize_text(node) }
       .reject(&:empty?)
       .first(3)
  end

  def chapter_count(doc)
    text = normalize_text(doc.at_css("#start-reading-btn .button-text"))
    count = text[/\(([^)]+)\)/, 1]
    return "#{count} chapters" if count

    stats = doc.xpath("//span[contains(@class, 'text-neutral-400')][normalize-space()='chapters']")
    value = stats.first&.previous_sibling&.text
    count = normalize_text(value)
    count.empty? ? nil : "#{count} chapters"
  end

  def last_updated(doc)
    candidates = doc.xpath("//div[contains(@class, 'text-sm') and contains(@class, 'text-neutral-300')]//span[contains(@class, 'text-neutral-300')]")
                    .map { |node| normalize_text(node) }
                    .reject(&:empty?)
    candidates.find { |value| value.match?(/ago\z|yesterday|today/i) }
  end

  def author(doc)
    labels = doc.xpath("//div[normalize-space()='Author & Artist']")
    node = labels.first&.previous_element
    normalize_text(node)
  end

  def genres(doc)
    doc.css('a[href*="/tag/"]')
       .map { |node| normalize_text(node) }
       .reject(&:empty?)
       .uniq
  end

  def description(doc)
    node = doc.at_css("#description-content-tab")
    return nil unless node

    paragraphs = node.css("p").map { |paragraph| normalize_text(paragraph) }.reject(&:empty?)
    return paragraphs.join("\n\n") unless paragraphs.empty?

    normalize_text(node)
  end

  def chapters(doc)
    doc.css(".chapter-list > a[href]").filter_map do |link|
      chapter_link(link)
    end
  end

  def chapters_for(doc)
    static_chapters = chapters(doc)
    return static_chapters unless static_chapters.empty?

    manga_numeric_id = doc.at_css(".chapter-list[data-manga-id]")&.[]("data-manga-id") ||
                       doc.at_css("[data-manga-id]")&.[]("data-manga-id")
    return [] if blank?(manga_numeric_id)

    chapter_api_items(manga_numeric_id)
  end

  def chapter_api_items(manga_numeric_id)
    offset = 0
    items = []

    loop do
      json = @client.get_json(CHAPTERS_ENDPOINT, params: chapter_api_params(manga_numeric_id, offset))
      batch = Array(json["chapters"])
      items.concat(batch.filter_map { |item| chapter_api_item(item) })

      break unless json["has_more"] && !batch.empty?

      offset += batch.length
    end

    items
  rescue StandardError => e
    warn "[manga_scraper] chapter fallback: #{e.message}"
    []
  end

  def chapter_api_params(manga_numeric_id, offset)
    timestamp = Time.now.to_i
    hour = Time.now.utc.strftime("%Y%m%d%H")
    token = Digest::MD5.hexdigest("#{timestamp}#{TOKEN_SECRET_PREFIX}#{hour}")[0, 16]

    {
      manga_id: manga_numeric_id,
      offset: offset,
      limit: CHAPTERS_LIMIT,
      order: "DESC",
      _t: token,
      _ts: timestamp
    }
  end

  def chapter_api_item(item)
    chapter = normalize_text(item["chapter"])

    {
      id: integer_or_string(item["id"]),
      chapter: chapter,
      chapter_label: chapter.empty? ? nil : "Ch. #{chapter}",
      title: normalize_text(item["title"]),
      group_id: integer_or_string(item["group_id"]),
      group_name: normalize_text(item["group_name"]),
      date: normalize_text(item["date"])
    }.reject { |_key, value| blank?(value) }
  end

  def chapter_link(link)
    chapter_label = normalize_text(
      link.at_css(".chapter-info-desktop span.font-medium") ||
      link.at_css(".chapter-info span.font-medium")
    )
    chapter_title = normalize_text(
      link.at_css(".chapter-info-desktop span.truncate") ||
      link.at_css("p.truncate")
    )
    group = normalize_text(link["data-group-name"])
    group_id = normalize_text(link["data-group-id"])
    chapter = chapter_label.sub(/\ACh\.?\s*/i, "")

    item = {
      id: integer_or_string(link["data-chapter-id"] || chapter_id_from_url(link["href"])),
      chapter: chapter,
      chapter_label: chapter_label,
      title: chapter_title,
      group_id: integer_or_string(group_id),
      group_name: group,
      date: normalize_text(link.at_xpath(".//div[contains(@class, 'hidden sm:flex')]//div[contains(@class, 'w-28')]//span"))
    }

    item.reject { |_key, value| blank?(value) }
  end

  def similar(doc)
    doc.xpath("//h2[.//span[normalize-space()='Similar']]/following-sibling::div[1]//div[contains(@class, 'group')]")
       .filter_map { |card| similar_card(card) }
  end

  def similar_card(card)
    title_link = card.css('a[href*="/manga/"]').reverse.find { |link| !normalize_text(link).empty? } ||
                 card.at_css('a[href*="/manga/"]')
    metadata = card.xpath(".//div[contains(@class, 'text-neutral-400')]//span")
                   .map { |node| normalize_text(node) }
                   .reject(&:empty?)

    {
      id: id_from_url(title_link&.[]("href")),
      title: clean_title(title_link&.[]("title") || title_link&.text),
      type: metadata[0],
      status: metadata[1]
    }.reject { |_key, value| blank?(value) }
  end

  def id_from_url(url)
    segments = path_segments(url)
    manga_index = segments.index("manga")
    return nil unless manga_index

    segments[manga_index + 1]
  end

  def chapter_id_from_url(url)
    slug = path_segments(url).last
    return nil if blank?(slug)

    match = slug.match(/-(\d+)\z/)
    match ? match[1] : slug
  end

  def path_segments(url)
    return [] if blank?(url)

    URI.parse(url).path.split("/").reject(&:empty?)
  rescue URI::InvalidURIError
    []
  end

  def absolute_url(url)
    return nil if blank?(url)

    uri = URI.parse(url)
    return url if uri.absolute?

    URI.join("#{Config::BASE_URL}/", url).to_s
  rescue URI::InvalidURIError
    nil
  end

  def clean_title(value)
    normalize_text(value).sub(/\ARead\s+/i, "")
  end

  def integer_or_string(value)
    text = value.to_s
    text.match?(/\A\d+\z/) ? text.to_i : value
  end

  def normalize_text(value)
    text = value.respond_to?(:text) ? value.text : value.to_s
    text.gsub(/\u00a0/, " ").gsub(/\s+/, " ").strip
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
end
