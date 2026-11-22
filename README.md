# goit-rdb-fp

Фінальний проєкт курсу Relational Databases for DS: схема pandemic у PostgreSQL, імпорт infectious_cases.csv, нормалізація до 3НФ, агрегати по Number_rabies, різниця в роках через вбудовані функції, дві власні функції на PL/pgSQL.

## Датасет

infectious_cases.csv: статистика інфекційних захворювань за країнами, регіонами і роками (1920–2023), 10521 рядок, 12 колонок.

- Джерело: файл з опису фінального проєкту GoIT (Google Drive).
- `data/infectious_cases.csv` — та сама копія без змін.

## Файли

- `FP.ipynb` — notebook з output клітинок.
- `fp.sql` — усі SQL-запити в тому ж порядку, що й у notebook.
- `screenshots/` — скриншоти запитів і результатів.
- `data/infectious_cases.csv` — датасет.

## Запуск

Відкрити `FP.ipynb` у Google Colab → Runtime → Restart and run all.

Notebook бере CSV з `data/`, якщо файлу немає, качає його з Google Drive через gdown, а якщо не вийшло, з цього репозиторію. PostgreSQL 16 запускається через `pixeltable-pgserver` (`pip install pgserver` на поточному Colab не ставиться).

`fp.sql` можна виконати в psql з кореня репозиторію: імпорт там через `\copy`.

## Що де

| Завдання | Notebook | Скриншоти |
|---|---|---|
| 1. Схема pandemic, імпорт, огляд даних | `## 1` | `01_schema_import.png`, `01_data_overview.png` |
| 2. Нормалізація до 3НФ: `entities` і `infectious_cases_normalized` | `## 2` | `02_normalization.png`, `02_tables.png`, `02_checks.png` |
| 3. AVG / MIN / MAX / SUM для Number_rabies, top-10 | `## 3` | `03_rabies_stats.png`, `03_rabies_stats_countries.png` |
| 4. Дата 1 січня, поточна дата, різниця в роках | `## 4` | `04_year_diff.png` |
| 5. `fn_years_diff` і `fn_avg_per_period` | `## 5` | `05_functions.png`, `05_fn_years_diff.png`, `05_fn_avg_per_period.png` |

Number_* у сирій таблиці зберігаються як TEXT, бо в CSV багато пустих значень. У нормалізованій таблиці вони NUMERIC, пусті значення стали NULL.

Завдання 4 і 5 залежать від поточної дати. Notebook запущено 2026-11-23.
