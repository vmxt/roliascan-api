# Roliascans API

Ruby JSON API for scraping Roliascan

Built with:

- Ruby
- Roda
- Nokogiri
- Puma
- Rack CORS

The API currently exposes an index endpoint, a homepage aggregation endpoint, and a manga detail endpoint.

## Project Structure

```text
.
|-- app.rb
|-- config.ru
|-- controllers
|   |-- home_controller.rb
|   `-- manga_controller.rb
|-- router
|   `-- router.rb
|-- utils
|   |-- cache_store.rb
|   |-- config.rb
|   |-- home_scraper.rb
|   |-- http_client.rb
|   |-- manga_scraper.rb
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
  "id": 278019,
  "chapter": "99",
  "chapter_label": "Ch. 99",
  "title": "N/A",
  "group_id": 450,
  "group_name": "Asurascans",
  "date": "2 days ago"
}
```

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

## Error Responses

Unknown endpoint:

```json
{
  "success": false,
  "status": 404,
  "error": "Endpoint not found"
}
```

If the source site cannot be reached while loading `/home` or `/manga/:id`, the API returns a JSON error with status `502`.

## Development Checks

Syntax check all Ruby files:

```bash
ruby -c app.rb
ruby -c config.ru
ruby -c router/router.rb
ruby -c controllers/home_controller.rb
ruby -c controllers/manga_controller.rb
ruby -c utils/home_scraper.rb
ruby -c utils/manga_scraper.rb
```

Quick local checks after starting Puma:

```bash
curl http://127.0.0.1:9292/
curl http://127.0.0.1:9292/home
curl http://127.0.0.1:9292/manga/the-regressed-mercenary-has-a-plan
```
