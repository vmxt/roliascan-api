# Roliascans API

Ruby JSON API for scraping Roliascan

Built with:

- Ruby
- Roda
- Nokogiri
- Puma
- Rack CORS

The API currently exposes an index endpoint, a homepage aggregation endpoint, a paginated browse endpoint, a manga detail endpoint, a chapter reader endpoint, a random suggestion endpoint, and a keyword search endpoint.

## Project Structure

```text
.
|-- app.rb
|-- config.ru
|-- controllers
|   |-- browse_controller.rb
|   |-- home_controller.rb
|   |-- manga_controller.rb
|   |-- random_controller.rb
|   |-- read_controller.rb
|   `-- search_controller.rb
|-- router
|   `-- router.rb
|-- utils
|   |-- browse_scraper.rb
|   |-- cache_store.rb
|   |-- config.rb
|   |-- home_scraper.rb
|   |-- http_client.rb
|   |-- manga_scraper.rb
|   |-- random_scraper.rb
|   |-- read_scraper.rb
|   |-- search_scraper.rb
|   `-- json_response.rb
|-- Gemfile
|-- Gemfile.lock
`-- README.md
```

## Setup

Install dependencies:

```bash
bundle install
```

Run the API with Puma:

```bash
bundle exec puma config.ru
```

Run on a specific host and port:

```bash
bundle exec puma config.ru -b tcp://127.0.0.1:9292
```

Open:

```text
http://127.0.0.1:9292
```

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `ROLIASCAN_BASE_URL` | `https://roliascan.com` | Source site base URL. |
| `CACHE_TTL_SECONDS` | `300` | In-memory cache duration for scraper responses. |
| `CONNECT_TIMEOUT_SECONDS` | `8` | Upstream connection timeout. |
| `REQUEST_TIMEOUT_SECONDS` | `12` | Upstream read timeout. |
| `HOME_LIMIT` | `15` | Number of items requested from JSON-backed homepage widgets. |
| `CORS_ORIGINS` | `*` | Comma-separated allowed CORS origins. |

Example:

```bash
HOME_LIMIT=10 CACHE_TTL_SECONDS=120 bundle exec puma config.ru
```

## Endpoints

### `GET /`

Health/index endpoint.

Response:

```text
{
  "success": boolean,
  "message": "string"
}
```

### `GET /home`

Scrapes and aggregates the Roliascan homepage.

Response shape:

```text
{
  "success": boolean,
  "data": {
    "spotlight_carousel": [],
    "recently_added": [],
    "completed_hot": {
      "completed": [],
      "hot": []
    },
    "recently_added_novels": [],
    "source": "string",
    "fetched_at": "string",
    "popular_chapters": {},
    "manga_by_status": {},
    "most_followed_new_manga": {},
    "most_followed_manga": {},
    "popular_manga": {},
    "high_score_manga": {}
  }
}
```

#### `spotlight_carousel`

Scraped from the homepage carousel.

Completed item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "genre": ["string"]
}
```

#### `recently_added`

Scraped from the Recently Added grid.

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "chapter_id": number,
  "chapter_date": "string"
}
```

#### `completed_hot`

Scraped from the sidebar.

Groups:

- `completed`
- `hot`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "chapter_id": "string",
  "chapter_date": "string"
}
```

Hot item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "chapter_id": number,
  "read_count": "string"
}
```

Note: the source page renders Completed in the HTML. When Hot only ships as a lazy-loading placeholder, the API fills it from Roliascan's popular chapters endpoint.

#### `recently_added_novels`

Scraped from the Recently Added Novels slider.

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "chapter_id": number,
  "chapter_date": "string"
}
```

#### `popular_chapters`

Fetched from Roliascan's JSON-backed popular chapters widget.

Groups:

- `today`
- `week`
- `month`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "chapter_id": "string"
}
```

#### `manga_by_status`

Fetched from Roliascan's manga status widget.

Groups:

- `reading`
- `completed`
- `plan_to_read`
- `dropped`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "user_count": "string"
}
```

#### `most_followed_new_manga`

Fetched from Roliascan's most followed new manga widget.

Groups:

- `seven_days`
- `one_month`
- `three_months`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "follow_count": number
}
```

#### `most_followed_manga`

Fetched from Roliascan's most followed manga widget.

Groups:

- `today`
- `week`
- `month`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "follow_count": number
}
```

#### `popular_manga`

Fetched from Roliascan's popular manga widget.

Groups:

- `today`
- `week`
- `month`
- `all`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "type": "string"
}
```

#### `high_score_manga`

Fetched from Roliascan's high score widget.

Groups:

- `all`
- `manga`
- `manhwa`
- `manhua`

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "image": "string",
  "type": "string"
}
```

### `GET /browse`

Loads Roliascan browse results in pages, matching the source site's infinite-scroll behavior.

Use `page` to request the next batch:

```text
GET /browse?page=1
GET /browse?page=2
```

Accepted query params:

- `page`: page number, defaults to `1`.
- `title`, `search`, `keyword`, or `q`: keyword/title search.
- `type` or `types`: `Manga`, `Manhwa`, `Manhua`, or `Novel`.
- `status` or `statuses`: `Cancelled`, `Completed`, `Hiatus`, or `Ongoing`.
- `year` or `years`: release year.
- `genres` or `tags`: comma-separated numeric genre IDs.
- `order` or `sort`: `latest`, `oldest`, `a-z`, `z-a`, `popular`, `release`, `release-asc`, or direct sort values like `post_desc`.
- `match`: `any` or `all` for multiple genres.

Examples:

```text
GET /browse?page=1&type=manhwa&status=ongoing
GET /browse?page=1&title=keyword
GET /browse?page=2&year=year&order=latest
```

Response shape:

```text
{
  "success": boolean,
  "data": {
    "page": number,
    "next_page": number,
    "has_next_page": boolean,
    "count": number,
    "filters": {
      "page": number,
      "types": ["string"],
      "statuses": ["string"],
      "sort": "string",
      "genre_match_mode": "string"
    },
    "results": [
      {
        "id": "string",
        "title": "string",
        "image": "string",
        "type": "string",
        "year": "string",
        "status": "string",
        "chapter_count": "string",
        "description": "string",
        "updated_at": "string"
      }
    ]
  }
}
```

Note: Roliascan omits some fields for some records. Empty values are removed from each item. Bookmark fields are not included.

Frontend infinite-scroll flow:

1. Call `/browse?page=1`.
2. Append `data.results` to your list.
3. When the user scrolls near the bottom, call `/browse?page=<next_page>`.
4. Stop loading more when `has_next_page` is `false`.

### `GET /manga/:id`

Scrapes a Roliascan manga detail page.

Use the manga slug as `:id`.

Example:

```text
GET /manga/:id
```

Response shape:

```text
{
  "success": boolean,
  "data": {
    "id": "string",
    "about": {},
    "chapters": [],
    "similar": []
  }
}
```

#### `about`

Manga details from the About tab.

Fields may vary by source page, but commonly include:

```text
{
  "manga_id": "string",
  "title": "string",
  "alternative_titles": [
    "string"
  ],
  "image": "string",
  "type": "string",
  "status": "string",
  "released": "string",
  "rating": "string",
  "views": "string",
  "chapter_count": "string",
  "last_updated": "string",
  "author": "string",
  "genres": ["string"],
  "description": "string"
}
```

#### `chapters`

Chapter entries from the Chapters tab. Roliascan lazy-loads this section, so the API fills it from the same chapter JSON endpoint used by the source page when needed.

Item fields:

```text
{
  "chapter_id": "string",
  "chapter": "string",
  "chapter_label": "string",
  "title": "string",
  "group_id": number,
  "group_name": "string",
  "date": "string"
}
```

Use `chapter_id` with the manga `id` in the reader endpoint.

#### `similar`

Similar manga entries.

Item fields:

```text
{
  "id": "string",
  "title": "string",
  "type": "string",
  "status": "string"
}
```

### `GET /read/:id/:chapter_id`

Scrapes a Roliascan chapter reader page. Image chapters return `images`; novel/text chapters return `content`.

Use the manga `id` and the `chapter_id` value from `/manga/:id` chapters.

Example:

```text
GET /read/:id/:chapter_id
```

Response shape:

Image chapter:

```text
{
  "success": boolean,
  "data": {
    "id": "string",
    "chapter_id": "string",
    "prev_chapter_id": "string",
    "next_chapter_id": "string",
    "images": [
      "string"
    ]
  }
}
```

Novel chapter:

```text
{
  "success": boolean,
  "data": {
    "id": "string",
    "chapter_id": "string",
    "prev_chapter_id": "string",
    "next_chapter_id": "string",
    "content": "string"
  }
}
```

### `GET /random`

Suggests 4 random manga/manhwa entries from Roliascan.

Response shape:

```text
{
  "success": boolean,
  "data": [
    {
      "id": "string",
      "title": "string",
      "image": "string",
      "type": "string"
    }
  ]
}
```

### `GET /search`

Searches Roliascan manga/manhwa results by keyword.

Accepted query params:

- `keyword`, `q`, or `query`: search text.
- `limit`: optional result limit, defaults to `20`, max `50`.

Examples:

```text
GET /search?keyword=keyword
GET /search?q=keyword&limit=5
GET /search/keyword
```

Response shape:

```text
{
  "success": boolean,
  "data": {
    "keyword": "string",
    "count": number,
    "results": [
      {
        "id": "string",
        "title": "string",
        "image": "string",
        "alternative_titles": [
          "string"
        ],
        "authors": [
          "string"
        ],
        "description": "string",
        "type": "string",
        "status": "string"
      }
    ]
  }
}
```

## Error Responses

Unknown endpoint:

```text
{
  "success": boolean,
  "status": number,
  "error": "string"
}
```

Missing search keyword:

```text
{
  "success": boolean,
  "status": number,
  "error": "string"
}
```

If the source site cannot be reached while loading `/home`, `/browse`, `/manga/:id`, `/read/:id/:chapter_id`, `/random`, or `/search`, the API returns a JSON error with status `502`.
