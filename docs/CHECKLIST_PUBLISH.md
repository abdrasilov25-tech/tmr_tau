# Почему не публикуется объявление (товар) — чек-лист

## 1. Вы залогинены?

- Если нет — приложение покажет «Войдите в аккаунт» или уйдёт на экран входа.
- **Сделать:** войти (или зарегистрироваться) и снова нажать «Добавить товар» → заполнить форму → «Опубликовать».

---

## 2. Ошибка про Storage (фото не загружается)

Внизу экрана появляется сообщение вроде:  
*«Storage: создайте бакет «products» в Supabase…»*

**Сделать в Supabase:**

1. **Storage** → **New bucket** → имя **`products`** → включить **Public** → сохранить.
2. **SQL Editor** → выполнить:

```sql
drop policy if exists "Allow authenticated uploads to products" on storage.objects;
drop policy if exists "Allow public read products" on storage.objects;
create policy "Allow authenticated uploads to products"
on storage.objects for insert to authenticated with check (bucket_id = 'products');
create policy "Allow public read products"
on storage.objects for select to public using (bucket_id = 'products');
```

После этого снова попробовать опубликовать (можно с фото или без).

---

## 3. Ошибка про базу данных

Сообщение вроде:  
*«База данных: проверьте таблицу products…»* или **PostgrestException** в логах.

**Сделать в Supabase:**

1. **Table Editor** → есть ли таблица **`products`**?
2. Если нет или структура старая — **SQL Editor** → открыть в проекте файл **`supabase/schema.sql`** → скопировать весь текст → вставить в запрос → **Run**.
3. Проверить политики: **Table Editor** → **products** → вкладка **Policies**. Должна быть политика **INSERT** для авторизованных (например, `auth.uid() = seller_id`). Если политик нет — они создаются при выполнении `schema.sql` (см. шаг 2).

---

## 4. Поля формы

- **Название** — не пустое.
- **Цена** — число (например, `1000` или `500`), без букв.
- **Фото** — необязательно; можно опубликовать товар без фото.

Если что-то не так, приложение покажет свою ошибку (например, «Введите корректную цену»).

---

## 5. Симулятор и сеть

- Симулятор должен иметь доступ в интернет (обычно есть по умолчанию).
- В **main.dart** должны стоять правильные **SUPABASE_URL** и **SUPABASE_ANON_KEY** твоего проекта.

---

## Кратко

| Что проверить | Где |
|---------------|-----|
| Войти в аккаунт | Приложение |
| Бакет **products** и политики Storage | Supabase → Storage + SQL Editor |
| Таблица **products** и RLS (INSERT) | Supabase → Table Editor / schema.sql |
| Название и цена заполнены | Форма «Добавить товар» |

Если после этого при нажатии «Опубликовать» снова появляется ошибка — скопируй **точный текст** из красного сообщения внизу экрана (или из консоли `flutter run`) и проверь по нему: это подскажет, Storage это или база данных.
