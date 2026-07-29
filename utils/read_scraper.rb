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
      data = data.merge(chapter_content(post_id, manga_id, normalized_chapter_id)) if Array(data[:images]).empty?

      raise ScrapeError.new("No chapter images found", status: 404) if Array(data[:images]).empty?

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
      prev_chapter_id: reader_chapter_id(doc.at_css('link[rel="prev"][href]')&.[]("href")),
      next_chapter_id: reader_chapter_id(doc.at_css('link[rel="next"][href]')&.[]("href")),
      images: chapter_images(doc)
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

  def chapter_images(doc)
    containers = doc.css(".comic-image-container")
    images = containers.filter_map { |container| image_url(container.at_css("img")) }
    images = doc.css("img.comic-image").filter_map { |image| image_url(image) } if images.empty?

    images.uniq
  end

  def chapter_content(post_id, manga_id, chapter_id)
    json = @client.get_json(CHAPTER_CONTENT_ENDPOINT, params: { chapter_id: post_id })

    {
      id: manga_id,
      chapter_id: chapter_id,
      images: Array(json["images"]).filter_map { |url| normalize_image_url(url) }.uniq
    }.reject { |_key, value| blank?(value) }
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

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
end
