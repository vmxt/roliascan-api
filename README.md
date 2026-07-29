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

```json
{
  "success": true,
  "message": "Welcome to Roliascans-API"
}
```

### `GET /home`

Scrapes and aggregates the Roliascan homepage.

Response shape:

```json
{
  "success": true,
  "data": {
    "spotlight_carousel": [],
    "recently_added": [],
    "completed_hot": {
      "completed": [],
      "hot": []
    },
    "recently_added_novels": [],
    "source": "https://roliascan.com/home/",
    "fetched_at": "2026-07-30T00:00:00Z",
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

```json
{
  "id": "manga-slug",
  "title": "Manga Title",
  "image": "https://example.com/cover.jpg",
  "genre": ["Action", "Fantasy"]
}
```

#### `recently_added`

Scraped from the Recently Added grid.

Item fields:

```json
{
  "id": "manga-slug",
  "title": "Manga Title",
  "image": "https://example.com/cover.jpg",
  "chapter_id": 123456,
  "chapter_date": "3s ago"
}
```

#### `completed_hot`

Scraped from the sidebar.

Groups:

- `completed`
- `hot`

Item fields:

```json
{
  "id": "manga-slug",
  "title": "Manga Title",
  "image": "https://example.com/cover.jpg",
  "chapter_id": "176",
  "chapter_date": "1 week ago"
}
```

Hot item fields:

```json
{
  "id": "manga-slug",
  "title": "Manga Title",
  "image": "https://example.com/cover.jpg",
  "chapter_id": 278586,
  "read_count": "861 reads"
}
```

Note: the source page renders Completed in the HTML. When Hot only ships as a lazy-loading placeholder, the API fills it from Roliascan's popular chapters endpoint.

#### `recently_added_novels`

Scraped from the Recently Added Novels slider.

Item fields:

```json
{
  "id": "novel-slug",
  "title": "Novel Title",
  "image": "https://example.com/cover.jpg",
  "chapter_id": 123456,
  "chapter_date": "12h ago"
}
```

#### `popular_chapters`

Fetched from Roliascan's JSON-backed popular chapters widget.

Groups:

- `today`
- `week`
- `month`

Item fields:

```json
{
  "id": 10822,
  "title": "Manga Title",
  "image": "https://example.com/cover.webp",
  "chapter_id": 278586
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

```json
{
  "id": 7,
  "title": "Manga Title",
  "image": "https://example.com/cover.webp",
  "user_count": "656 users"
}
```

#### `most_followed_new_manga`

Fetched from Roliascan's most followed new manga widget.

Groups:

- `seven_days`
- `one_month`
- `three_months`

Item fields:

```json
{
  "id": 269254,
  "title": "Manga Title",
  "image": "https://example.com/cover.jpg",
  "follow_count": 76
}
```

#### `most_followed_manga`

Fetched from Roliascan's most followed manga widget.

Groups:

- `today`
- `week`
- `month`

Item fields:

```json
{
  "id": 11126,
  "title": "Manga Title",
  "image": "https://example.com/cover.webp",
  "follow_count": 12
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

```json
{
  "id": "manga-slug",
  "title": "Manga Title",
  "image": "https://example.com/cover.webp",
  "type": "Manhwa"
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

```json
{
  "id": "manga-slug",
  "title": "Manga Title",
  "image": "https://example.com/cover.webp",
  "type": "Manga"
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
GET /browse?page=1&title=solo%20leveling
GET /browse?page=2&year=2026&order=latest
```

Response shape:

```json
{
  "success": true,
  "data": {
    "page": 1,
    "next_page": 2,
    "has_next_page": true,
    "count": 24,
    "filters": {
      "page": 1,
      "types": ["Manhwa"],
      "statuses": ["Ongoing"],
      "sort": "post_desc",
      "genre_match_mode": "any"
    },
    "results": [
      {
        "id": "there-is-no-what-if",
        "title": "There is No \"What If\"",
        "image": "https://roliascan.com/content/media/manga-278456-cover-1785201934.jpg",
        "type": "Manhwa",
        "year": "2026",
        "status": "Ongoing",
        "chapter_count": "12",
        "description": "Save or die. There are no what ifs here.",
        "updated_at": "2 days ago"
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
GET /manga/the-regressed-mercenary-has-a-plan
```

Response shape:

```json
{
  "success": true,
  "data": {
    "id": "the-regressed-mercenary-has-a-plan",
    "about": {},
    "chapters": [],
    "similar": []
  }
}
```

#### `about`

Manga details from the About tab.

Fields may vary by source page, but commonly include:

```json
{
  "manga_id": "11092",
  "title": "The Regressed Mercenary Has a Plan",
  "alternative_titles": [
    "The Regressed Mercenary's Machinations"
  ],
  "image": "https://example.com/cover.jpg",
  "type": "Manhwa",
  "status": "Ongoing",
  "released": "2024",
  "rating": "9.9",
  "views": "415104",
  "chapter_count": "100 chapters",
  "last_updated": "2 months ago",
  "author": "Park, Jinseok, Gold Haeng",
  "genres": ["Action", "Fantasy"],
  "description": "About text..."
}
```

#### `chapters`

Chapter entries from the Chapters tab. Roliascan lazy-loads this section, so the API fills it from the same chapter JSON endpoint used by the source page when needed.

Item fields:

```json
{
  "chapter_id": "ch99-278019",
  "chapter": "99",
  "chapter_label": "Ch. 99",
  "title": "N/A",
  "group_id": 450,
  "group_name": "Asurascans",
  "date": "2 days ago"
}
```

Use `chapter_id` with the manga `id` in the reader endpoint.

#### `similar`

Similar manga entries.

Item fields:

```json
{
  "id": "artifact-devouring-player",
  "title": "Artifact-Devouring Player",
  "type": "Manhwa",
  "status": "Ongoing"
}
```

### `GET /read/:id/:chapter_id`

Scrapes a Roliascan chapter reader page. Image chapters return `images`; novel/text chapters return `content`.

Use the manga `id` and the `chapter_id` value from `/manga/:id` chapters.

Example:

```text
GET /read/the-regressed-mercenary-has-a-plan/ch98-276849
```

Response shape:

Image chapter:

```json
{
  "success": true,
  "data": {
    "id": "the-regressed-mercenary-has-a-plan",
    "chapter_id": "ch98-276849",
    "prev_chapter_id": "ch97-269090",
    "next_chapter_id": "ch99-278019",
    "images": [
      "https://roliascan.org/storage/chapters/manhwa_11092_98/001.png",
      "https://roliascan.org/storage/chapters/manhwa_11092_98/002.png"
    ]
  }
}
```

Novel chapter:

```json
{
  "success": true,
  "data": {
    "id": "as-a-mafia-boss-i-refuse-to-be-an-extra-novel",
    "chapter_id": "ch442-278571",
    "prev_chapter_id": "ch441-278549",
    "next_chapter_id": "ch443-278681",
    "content": "Damian's eyes tracked four massive weapons descending from different angles...\n\nHe moved as telekinesis activated, pulling his body sideways faster than muscles alone could manage."
  }
}
```

### `GET /random`

Suggests 4 random manga/manhwa entries from Roliascan.

Response shape:

```json
{
  "success": true,
  "data": [
    {
      "id": "solo-bug-player",
      "title": "Solo Bug Player",
      "image": "https://roliascan.com/content/media/manga-10864-cover-1775133472.png",
      "type": "Manhwa"
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
GET /search?keyword=solo%20leveling
GET /search?q=solo%20leveling&limit=5
GET /search/solo%20leveling
```

Response shape:

```json
{
  "success": true,
  "data": {
    "keyword": "solo leveling",
    "count": 2,
    "results": [
      {
        "id": "solo-leveling",
        "title": "Solo Leveling",
        "image": "https://roliascan.com/content/media/121496l.webp",
        "alternative_titles": [
          "Na Honjaman Level Up",
          "I Level Up Alone"
        ],
        "authors": [
          "Chugong",
          "Jang"
        ],
        "description": "Ten years ago, the Gate appeared...",
        "type": "Manhwa",
        "status": "Completed"
      }
    ]
  }
}
```

## Error Responses

Unknown endpoint:

```json
{
  "success": false,
  "status": 404,
  "error": "Endpoint not found"
}
```

Missing search keyword:

```json
{
  "success": false,
  "status": 400,
  "error": "Search keyword is required"
}
```

If the source site cannot be reached while loading `/home`, `/browse`, `/manga/:id`, `/read/:id/:chapter_id`, `/random`, or `/search`, the API returns a JSON error with status `502`.