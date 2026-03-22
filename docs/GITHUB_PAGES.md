# Сайт tmrtau App на GitHub Pages

Файлы лендинга: **`site/index.html`**, **`site/styles.css`**.

Публичный URL после настройки:

**https://abdrasilov25-tech.github.io/tmr_tau/**

(имя организации в URL — **`abdrasilov25-tech`**, с дефисом)

---

## Где искать настройки (если не видишь «Deploy from a branch»)

1. Открой репозиторий: **https://github.com/abdrasilov25-tech/tmr_tau**
2. Вверху вкладка **Settings** (Параметры). Если её нет — у аккаунта нет прав администратора на репозиторий.
3. В **левом меню** прокрути вниз до раздела **Code and automation** → пункт **Pages**.
4. Блок **Build and deployment**:
   - в новом интерфейсе чаще сначала предлагают **GitHub Actions** — это нормально;
   - выбери **GitHub Actions** (не «None»).

В репозитории уже есть workflow **`.github/workflows/deploy-github-pages.yml`**: после включения **Source: GitHub Actions** сделай пуш в `main` или открой **Actions → Deploy GitHub Pages → Run workflow**.

Через 1–3 минуты сайт откроется по ссылке выше. Там же GitHub покажет зелёный статус деплоя.

### Вариант без Actions (классический)

Если в **Source** есть **Deploy from a branch**:

- Branch: **main**
- Folder: **/ (root)**  
  Тогда сайт будет по адресу **`.../tmr_tau/site/`** (потому что файлы лежат в папке `site/` в репозитории). В приложении тогда нужен URL с `/site/` — сейчас в коде указан корень **`.../tmr_tau/`** под деплой через Actions.

---

## Обновление контента

Правь **`site/index.html`** и **`site/styles.css`**, коммит в `main` — workflow пересоберёт сайт (если включены GitHub Actions).

В корне репозитория есть **`.nojekyll`** (для классического деплоя из ветки).
