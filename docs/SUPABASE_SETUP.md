# Как получить Supabase URL и ключи (по шагам)

## Шаг 1. Регистрация в Supabase

1. Открой в браузере: **https://supabase.com**
2. Нажми **Start your project** (или **Sign in**).
3. Войди через **GitHub** или **Email** и при необходимости подтверди почту.

---

## Шаг 2. Создать новый проект

1. После входа откроется **Dashboard**.
2. Нажми **New Project** (зелёная кнопка).
3. Заполни:
   - **Name** — например: `tmr_tau`
   - **Database Password** — придумай надёжный пароль и **сохрани его** (для доступа к БД).
   - **Region** — выбери ближайший регион (например, Frankfurt).
4. Нажми **Create new project** и подожди 1–2 минуты, пока проект поднимется.

---

## Шаг 3. Найти URL и anon key

1. В левом меню выбери **Project Settings** (иконка шестерёнки внизу).
2. В подменю слева выбери **API**.
3. На странице **API** увидишь блок **Project URL** и блок **Project API keys**:
   - **Project URL** — это твой **SUPABASE_URL** (например: `https://xxxxxxxx.supabase.co`).
   - **anon public** — это твой **SUPABASE_ANON_KEY** (длинная строка, начинается с `eyJ...`).  
     Копируй именно **anon public**, не **service_role**.

Скопируй оба значения в блокнот — они понадобятся в следующем шаге.

---

## Шаг 4. Подставить значения в приложение

Открой в проекте файл **`lib/main.dart`** и замени плейсхолдеры на свои значения:

**Было:**
```dart
const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://your-project.supabase.co',
);
const String _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'your-anon-key',
);
```

**Стало (подставь свои URL и ключ):**
```dart
const String _supabaseUrl = 'https://ТВОЙ_ПРОЕКТ_ID.supabase.co';
const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';  // твой anon key
```

Либо оставь `String.fromEnvironment` и запускай так:

```bash
flutter run --dart-define=SUPABASE_URL=https://ТВОЙ_ПРОЕКТ.supabase.co --dart-define=SUPABASE_ANON_KEY=твой_anon_ключ
```

---

## Шаг 5. Создать таблицы в БД

1. В левом меню Supabase выбери **SQL Editor**.
2. Нажми **New query**.
3. Открой в проекте файл **`supabase/schema.sql`**, скопируй весь его текст.
4. Вставь в редактор запроса в Supabase и нажми **Run** (или Ctrl+Enter).
5. Убедись, что запрос выполнился без ошибок — после этого таблицы `users`, `products`, `orders`, `messages`, `favorites`, `followers` и RLS-политики созданы.  
   Для товаров включены: просмотр для всех, добавление/редактирование/удаление — только для владельца (`seller_id = auth.uid()`).

---

## Шаг 5.1. Storage: бакеты для фото товаров и новостей

Без этого при «Добавить товар» или «Новая новость» будет **StorageException**.

1. В Supabase открой **Storage**.
2. Создай два бакета (если их ещё нет):
   - **products** — для фото товаров (включи **Public bucket**).
   - **posts** — для фото/видео новостей (включи **Public bucket**).
3. В **SQL Editor** выполни (разрешит загрузку и просмотр файлов):

```sql
-- Удалить старые политики, если уже создавали (иначе будет "already exists")
drop policy if exists "Allow authenticated uploads to products" on storage.objects;
drop policy if exists "Allow public read products" on storage.objects;

-- Товары: загрузка для авторизованных, чтение для всех
create policy "Allow authenticated uploads to products"
on storage.objects for insert to authenticated with check (bucket_id = 'products');
create policy "Allow public read products"
on storage.objects for select to public using (bucket_id = 'products');
```

Для бакета **posts** (новости) политики настраиваются так же — см. обсуждение в чате или повтори те же шаги для `bucket_id = 'posts'`.

---

## Шаг 6. Проверить приложение

1. Сохрани изменения в `main.dart`.
2. Перезапусти приложение:
   ```bash
   flutter run
   ```
3. Должен открыться экран приложения (Splash → Login), без красного экрана и без сообщения «Supabase не настроен».

---

## Кратко

| Что нужно | Где взять в Supabase |
|----------|----------------------|
| **URL**  | Project Settings → API → **Project URL** |
| **Anon key** | Project Settings → API → **Project API keys** → **anon public** |

**Важно:** ключ **service_role** в приложение не подставляй — он для бэкенда с полным доступом. В приложении используй только **anon public**.

---

## Чтобы вход по паролю работал без подтверждения email

1. В Supabase: **Authentication** → **Providers** → **Email**.
2. Выключи **Confirm email** (или оставь включённым — тогда после регистрации нужно перейти по ссылке из письма).
3. Сохрани. После этого можно входить сразу после регистрации тем же email и паролем.
