# Сайт tmrtau App на GitHub Pages

Целевой URL: **https://abdrasilov25-tech.github.io/tmr_tau/**

Файлы лендинга: **`site/index.html`**, **`site/styles.css`** (деплой в ветку **`gh-pages`** через Actions).  
В **корне** репозитория тоже есть **`index.html`** — запасной вариант без ветки `gh-pages`.

---

## Если открывается 404

Значит GitHub **ещё не отдаёт** ни одну опубликованную папку. Сделай **один** из вариантов.

### Вариант A (проще всего): публикация из ветки `main`, папка корень

Подходит, потому что в корне уже лежат **`index.html`** и **`styles.css`**.

1. Открой: **https://github.com/abdrasilov25-tech/tmr_tau/settings/pages**
2. **Build and deployment** → **Source** → **Deploy from a branch**
3. **Branch:** `main` → **Folder:** `/ (root)` → **Save**
4. Подожди 1–2 минуты и снова открой:  
   **https://abdrasilov25-tech.github.io/tmr_tau/**

В корне есть **`.nojekyll`**, чтобы GitHub не ломал раздачу через Jekyll.

### Вариант B: только папка `site/` через ветку `gh-pages`

1. Вкладка **Actions** → workflow **Deploy GitHub Pages** → **Run workflow** (чтобы создалась/обновилась ветка `gh-pages`).
2. Дождись **зелёного** статуса.
3. **Settings** → **Pages** → **Branch:** `gh-pages` → **Folder:** `/ (root)` → **Save**

---

## Организация и права

Если репозиторий в **организации**, владелец org может запретить Actions или Pages — тогда в **Settings** репозитория проверь, что **Actions** включены, а **Pages** разрешены.

---

## Обновление контента

- При варианте **A** правь **`index.html`** / **`styles.css`** в **корне** (или синхронно с `site/`).
- При варианте **B** правь **`site/`** и жди деплоя workflow.
