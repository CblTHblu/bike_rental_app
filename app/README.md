# Прокат велосипедов

Веб-приложение (Flask + PostgreSQL) для работы со всеми таблицами базы bike_rental:
просмотр, добавление, изменение и удаление записей.

## Подключение к базе

PostgreSQL 14 или новее.

База bike_rental, кодировка UTF-8, локаль ru_RU.UTF-8.

Хост localhost, порт 5432.

```
DATABASE_URL=postgres://postgres:пароль@localhost:5432/bike_rental
```

## Как создать таблицы

Файл bike_rental.sql создаёт базу, домены, десять таблиц, триггеры, процедуру
и заполняет учебные строки. Его выполняют, подключившись к базе postgres:

```
psql -h localhost -U postgres -d postgres -f bike_rental.sql
```

Повторный запуск стирает базу bike_rental и собирает её заново.

На Windows локаль ru_RU.UTF-8 может не подойти: замените её в bike_rental.sql на Russian_Russia.

## Как запустить приложение

```
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
export DATABASE_URL=postgres://postgres:пароль@localhost:5432/bike_rental
                                   # Windows (cmd): set DATABASE_URL=...
flask --app app run
```

Приложение открывается по адресу http://127.0.0.1:5000
