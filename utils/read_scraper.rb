# frozen_string_literal: true

require "nokogiri"
require "uri"

require_relative "cache_store"
require_relative "config"
require_relative "http_client"

class ReadScraper
  class ScrapeError < StandardError
    attr_reader :status

    def initialize(message, status: 502)
      @status = status
      super(message)
    end
  end

  CHAPTER_CONTENT_ENDPOINT = "/auth/chapter-content"

  def initialize(client: HttpClient.new, cache: CacheStore.new(ttl: Config::CACHE_TTL))
    @client = client
    @cache = cache
  end

  def read(id, chapter_id)
    manga_id = normalize_id(id)
    normalized_chapter_id = normalize_chapter_id(chapter_id)
    post_id = post_id_from_chapter_id(normalized_chapter_id)

    @cache.fetch("read:v2:#{manga_id}:#{normalized_chapter_id}") do
      html = @client.get("/?p=#{post_id}")
      data = parse_read_html(html, id: manga_id, chapter_id: normalized_chapter_id)
      data = data.merge(chapter_content(post_id, manga_id, normalized_chapter_id)) unless readable_content?(data)

      raise ScrapeError.new("No chapter content found", status: 404) unless readable_content?(data)

      data
    end
  rescue HttpClient::Error => e
    raise ScrapeError.new(e.message, status: e.status)
  end

  def parse_read_html(html, id: nil, chapter_id: nil)
    doc = Nokogiri::HTML(html)

    {
      id: id,
      chapter_id: chapter_id,
      prev_chapter_id: prev_chapter_id(doc),
      next_chapter_id: next_chapter_id(doc),
      images: chapter_images(doc),
      content: chapter_text(doc)
    }.reject { |_key, value| blank?(value) }
  end

  private

  def normalize_id(id)
    value = id.to_s.strip.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    raise ScrapeError.new("Invalid manga id", status: 400) unless value.match?(/\A[a-zA-Z0-9._-]+\z/)

    value
  end

  def normalize_chapter_id(chapter_id)
    value = chapter_id.to_s.strip.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    unless value.match?(/\A[a-zA-Z0-9._-]+\z/) && post_id_from_chapter_id(value)
      raise ScrapeError.new("Invalid chapter id", status: 400)
    end

    value
  end

  def post_id_from_chapter_id(chapter_id)
    return chapter_id if chapter_id.match?(/\A\d+\z/)

    chapter_id[/-(\d+)\z/, 1]
  end

  def reader_chapter_id(url)
    return nil if blank?(url)

    URI.parse(url).path.split("/").reject(&:empty?).last
  rescue URI::InvalidURIError
    nil
  end

  def prev_chapter_id(doc)
    reader_chapter_id(doc.at_css('link[rel="prev"][href]')&.[]("href")) ||
      reader_chapter_id(doc.at_xpath("//a[contains(@href, '/read/') and contains(@title, 'Previous')]")&.[]("href")) ||
      reader_chapter_id(doc.at_xpath("//a[contains(@href, '/read/') and .//*[normalize-space()='Prev Chapter']]")&.[]("href"))
  end

  def next_chapter_id(doc)
    reader_chapter_id(doc.at_css('link[rel="next"][href]')&.[]("href")) ||
      reader_chapter_id(doc.at_xpath("//a[contains(@href, '/read/') and contains(@title, 'Next')]")&.[]("href")) ||
      reader_chapter_id(doc.at_xpath("//a[contains(@href, '/read/') and .//*[normalize-space()='Next Chapter']]")&.[]("href"))
  end

  def chapter_images(doc)
    containers = doc.css(".comic-image-container")
    images = containers.filter_map { |container| image_url(container.at_css("img")) }
    images = doc.css("img.comic-image").filter_map { |image| image_url(image) } if images.empty?

    images.uniq
  end

  def chapter_text(doc, fragment: false)
    paragraphs = doc.css(".reader-text p").map { |paragraph| normalize_text(paragraph) }.reject(&:empty?)
    paragraphs = doc.css("p").map { |paragraph| normalize_text(paragraph) }.reject(&:empty?) if paragraphs.empty? && fragment
    return novel_text(paragraphs) unless paragraphs.empty?

    text = normalize_text(doc.at_css(".reader-text"))
    text.empty? ? nil : text
  end

  def chapter_content(post_id, manga_id, chapter_id)
    json = @client.get_json(CHAPTER_CONTENT_ENDPOINT, params: { chapter_id: post_id })
    content_doc = Nokogiri::HTML.fragment(json["content"].to_s)

    {
      id: manga_id,
      chapter_id: chapter_id,
      images: Array(json["images"]).filter_map { |url| normalize_image_url(url) }.uniq,
      content: chapter_text(content_doc, fragment: true)
    }.reject { |_key, value| blank?(value) }
  end

  def readable_content?(data)
    !Array(data[:images]).empty? || !blank?(data[:content])
  end

  def image_url(image)
    return nil unless image

    url = image["data-src"] || image["data-lazy-src"] || image["src"]
    normalize_image_url(url)
  end

  def normalize_image_url(url)
    return nil if blank?(url) || url.start_with?("data:")

    absolute_url(url)
  end

  def absolute_url(url)
    uri = URI.parse(url)
    return url if uri.absolute?

    URI.join("#{Config::BASE_URL}/", url).to_s
  rescue URI::InvalidURIError
    nil
  end

  def normalize_text(value)
    text = value.respond_to?(:text) ? value.text : value.to_s
    text.gsub(/\u00a0/, " ").gsub(/\s+/, " ").strip
  end

  def novel_text(paragraphs)
    paragraphs.join("\n\n")
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
end
