# Сайт tmrtau App на GitHub Pages

Статическая страница лежит в папке **`site/`** (`index.html` + `styles.css`).  
Публичный URL (после включения Pages):

**https://abdrasilov25-tech.github.io/tmr_tau/site/**

> Важно: имя организации в URL — **`abdrasilov25-tech`** (с дефисом), как в remote репозитория.

## Включить сайт

1. GitHub → репозиторий **tmr_tau** → **Settings** → **Pages**.
2. **Build and deployment** → **Source**: **Deploy from a branch**.
3. **Branch**: `main`, папка **`/ (root)`** → Save.
4. Через 1–3 минуты страница станет доступна по ссылке выше.

В корне репозитория есть файл **`.nojekyll`**, чтобы GitHub не прогонял сайт через Jekyll и не ломал статику.

## Обновление контента

Правь **`site/index.html`** и **`site/styles.css`** (или скопируй изменения из корневых `index.html` / `styles.css` в `site/`), закоммить и запушь в `main`.
