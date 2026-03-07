# tmr_tau — Project Structure

Marketplace + social app (Instagram/TikTok style). Flutter, Clean Architecture, feature-first.

## Tech Stack

- **Flutter** (latest stable)
- **State:** flutter_bloc
- **Navigation:** go_router
- **Backend:** Supabase
- **Images:** cached_network_image, image_picker

## Folder Structure

```
lib/
├── core/
│   ├── constants/       # app_constants, supabase_constants
│   ├── theme/           # app_theme
│   ├── router/          # app_router (go_router, 5-tab shell)
│   ├── utils/           # logger, etc.
│   └── widgets/         # app_loading, app_error_view, cached_avatar, cached_product_image
├── features/
│   ├── auth/            # login, register, session (Supabase Auth)
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   ├── feed/            # global product feed (vertical scroll), stories strip
│   ├── product/         # product CRUD, feed, search, trending
│   ├── profile/         # seller profile, follow, edit profile
│   ├── stories/         # 24h stories (domain, data, presentation)
│   ├── comments/        # product comments (domain, data, presentation)
│   ├── search/          # product + seller search, trending (in feed/search_page)
│   └── notifications/   # notifications list, mark read
├── app.dart
└── main.dart
```

## Bottom Navigation (5 tabs)

1. **Home** — Product feed (vertical), stories strip, like/comment/follow
2. **Search** — Product search, trending
3. **Add** — Add product (image, title, price, description, category)
4. **Notifications** — Notifications list
5. **Profile** — My profile / seller profile, edit, product grid

## Supabase

- **Schema:** `supabase/schema.sql` — users, products, product_likes, product_comments, followers, stories, notifications, favorites, orders
- **Storage buckets:** `products`, `stories` (and `posts` if using legacy posts)
- Run the schema in Supabase SQL Editor after creating the project.

## Features

- **Auth:** Login, register, session (Supabase)
- **Feed:** Products with like, comment, follow; stories strip at top
- **Product:** Add (image, title, price, description, category), detail, search, trending
- **Profile:** View seller, follow/unfollow, edit avatar/bio, product grid
- **Stories:** Entity + repository (upload/view via stories feature)
- **Comments:** Product comments (entity, repository, UI can be sheet on product detail)
- **Notifications:** List, mark read

All new code is modular and production-oriented; extend per feature as needed.
