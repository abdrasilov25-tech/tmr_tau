# Сайт tmrtau App на GitHub Pages

Файлы лендинга: **`site/index.html`**, **`site/styles.css`**.

Публичный URL после настройки:

**https://abdrasilov25-tech.github.io/tmr_tau/**

---

## Почему был Error: Get Pages site failed (404)

Старый вариант с **`actions/configure-pages` + `deploy-pages`** обращается к API GitHub Pages. Пока в репозитории **ни разу не выбран источник публикации**, этого «сайта» в API нет → **404**.

Сейчас используется деплой в ветку **`gh-pages`** (`peaceiris/actions-gh-pages`) — обычный push ветки, **без** этого API.

---

## Что сделать (один раз)

1. Дождись зелёного workflow **Deploy GitHub Pages** на вкладке **Actions** (или запусти **Run workflow** вручную).

2. Открой: **https://github.com/abdrasilov25-tech/tmr_tau/settings/pages**

3. В **Build and deployment** → **Source** выбери **Deploy from a branch** (не GitHub Actions).

4. **Branch:** `gh-pages`, папка **`/ (root)`** → **Save**.

5. Через минуту открой: **https://abdrasilov25-tech.github.io/tmr_tau/**

Если пункта **Deploy from a branch** нет — обнови страницу или зайди с аккаунта **владельца** репозитория.

---

## Обновление контента

Правь **`site/`**, пуш в `main` — workflow снова обновит ветку `gh-pages`.
