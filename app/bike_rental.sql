DROP DATABASE IF EXISTS bike_rental;

CREATE DATABASE bike_rental
    ENCODING   'UTF8'
    LC_COLLATE 'Russian_Russia'
    LC_CTYPE   'Russian_Russia'
    TEMPLATE   template0;

\connect bike_rental

CREATE DOMAIN d_title AS varchar(100)
    CONSTRAINT d_title_not_blank CHECK (btrim(VALUE) <> '');

CREATE DOMAIN d_person_name AS varchar(50)
    CONSTRAINT d_person_name_not_blank CHECK (btrim(VALUE) <> '');

CREATE DOMAIN d_phone AS varchar(20)
    CONSTRAINT d_phone_format CHECK (VALUE ~ '^\+7 [0-9]{3} [0-9]{3}-[0-9]{2}-[0-9]{2}$');

CREATE DOMAIN d_money AS numeric(10,2)
    CONSTRAINT d_money_non_negative CHECK (VALUE >= 0);

CREATE DOMAIN d_price AS numeric(10,2)
    CONSTRAINT d_price_positive CHECK (VALUE > 0);

CREATE DOMAIN d_percent AS numeric(5,2)
    CONSTRAINT d_percent_range CHECK (VALUE >= 0 AND VALUE <= 100);

CREATE TABLE positions (
    id     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title  d_title NOT NULL UNIQUE,
    salary d_price NOT NULL
);

CREATE TABLE client_categories (
    id       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title    d_title   NOT NULL UNIQUE,
    discount d_percent NOT NULL DEFAULT 0
);

CREATE TABLE bike_types (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title          d_title NOT NULL UNIQUE,
    price_per_hour d_price NOT NULL,
    deposit        d_money NOT NULL
);

CREATE TABLE employees (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    last_name   d_person_name NOT NULL,
    first_name  d_person_name NOT NULL,
    middle_name d_person_name,
    birth_date  date          NOT NULL,
    phone       d_phone       NOT NULL UNIQUE,
    hired_on    date          NOT NULL,
    login       varchar(30)   NOT NULL UNIQUE,
    position_id integer       NOT NULL REFERENCES positions (id) ON DELETE RESTRICT,
    CONSTRAINT employee_adult CHECK (hired_on >= birth_date + INTERVAL '18 years')
);

CREATE TABLE clients (
    id                   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    last_name            d_person_name NOT NULL,
    first_name           d_person_name NOT NULL,
    middle_name          d_person_name,
    birth_date           date          NOT NULL,
    phone                d_phone       NOT NULL,
    email                varchar(100),
    passport_series      char(4)       NOT NULL,
    passport_number      char(6)       NOT NULL,
    registered_on        date          NOT NULL DEFAULT CURRENT_DATE,
    proof_doc_type       varchar(60),
    proof_doc_number     varchar(40),
    category_valid_until date,
    category_id          integer       NOT NULL DEFAULT 1
                         REFERENCES client_categories (id) ON DELETE RESTRICT,
    CONSTRAINT client_passport_unique UNIQUE (passport_series, passport_number),
    CONSTRAINT passport_series_format CHECK (passport_series ~ '^[0-9]{4}$'),
    CONSTRAINT passport_number_format CHECK (passport_number ~ '^[0-9]{6}$'),
    CONSTRAINT client_email_format    CHECK (email IS NULL OR email ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'),
    CONSTRAINT client_adult           CHECK (registered_on >= birth_date + INTERVAL '18 years'),
    CONSTRAINT client_proof_together  CHECK ((proof_doc_type IS NULL) = (proof_doc_number IS NULL))
);

CREATE TABLE bikes (
    id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_number varchar(20) NOT NULL UNIQUE,
    frame_serial     varchar(40) NOT NULL UNIQUE,
    brand            varchar(50) NOT NULL,
    model            varchar(50) NOT NULL,
    frame_size       varchar(10) NOT NULL,
    release_year     smallint    NOT NULL,
    commissioned_on  date        NOT NULL,
    status           varchar(20) NOT NULL DEFAULT 'свободен',
    type_id          integer     NOT NULL REFERENCES bike_types (id) ON DELETE RESTRICT,
    CONSTRAINT known_bike_status CHECK (status IN ('свободен', 'в прокате', 'на обслуживании', 'списан')),
    CONSTRAINT bike_release_year CHECK (release_year BETWEEN 2000 AND EXTRACT(YEAR FROM CURRENT_DATE))
);

CREATE TABLE rentals (
    id                   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_number      varchar(20) NOT NULL UNIQUE,
    created_on           date        NOT NULL DEFAULT CURRENT_DATE,
    issue_date           date        NOT NULL,
    issue_time           time        NOT NULL,
    planned_return_date  date        NOT NULL,
    planned_return_time  time        NOT NULL,
    actual_return_date   date,
    actual_return_time   time,
    status               varchar(20) NOT NULL DEFAULT 'оформлен',
    fine                 d_money     NOT NULL DEFAULT 0,
    total                d_money,
    client_id            integer     NOT NULL REFERENCES clients (id)   ON DELETE RESTRICT,
    employee_id          integer     NOT NULL REFERENCES employees (id) ON DELETE RESTRICT,
    CONSTRAINT known_rental_status CHECK
        (status IN ('оформлен', 'оплачен', 'выдан', 'возвращён', 'закрыт', 'отменён')),
    CONSTRAINT rental_min_duration CHECK
        (planned_return_date + planned_return_time >= issue_date + issue_time + INTERVAL '1 hour'),
    CONSTRAINT rental_max_duration CHECK
        (planned_return_date + planned_return_time <= issue_date + issue_time + INTERVAL '7 days'),
    CONSTRAINT rental_work_hours CHECK
        (issue_time BETWEEN TIME '09:00' AND TIME '21:00'
         AND planned_return_time BETWEEN TIME '09:00' AND TIME '21:00'),
    CONSTRAINT rental_actual_together CHECK
        ((actual_return_date IS NULL) = (actual_return_time IS NULL)),
    CONSTRAINT rental_actual_after_issue CHECK
        (actual_return_date IS NULL
         OR actual_return_date + actual_return_time > issue_date + issue_time),
    CONSTRAINT rental_returned_has_actual CHECK
        (status NOT IN ('возвращён', 'закрыт') OR actual_return_date IS NOT NULL),
    CONSTRAINT rental_closed_has_total CHECK
        (status <> 'закрыт' OR total IS NOT NULL)
);

CREATE TABLE rental_items (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rental_id      integer      NOT NULL REFERENCES rentals (id) ON DELETE CASCADE,
    bike_id        integer      NOT NULL REFERENCES bikes (id)   ON DELETE RESTRICT,
    price_per_hour d_price      NOT NULL,
    paid_hours     integer,
    condition_out  varchar(200) NOT NULL,
    condition_in   varchar(200),
    CONSTRAINT rental_item_unique UNIQUE (rental_id, bike_id),
    CONSTRAINT paid_hours_min CHECK (paid_hours IS NULL OR paid_hours >= 1)
);

CREATE TABLE payments (
    id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rental_id integer     NOT NULL REFERENCES rentals (id) ON DELETE RESTRICT,
    paid_on   date        NOT NULL DEFAULT CURRENT_DATE,
    paid_at   time        NOT NULL DEFAULT LOCALTIME(0),
    amount    d_price     NOT NULL,
    kind      varchar(30) NOT NULL,
    method    varchar(20) NOT NULL,
    CONSTRAINT known_payment_kind CHECK
        (kind IN ('предоплата', 'залог', 'доплата', 'возврат залога', 'возврат предоплаты')),
    CONSTRAINT known_payment_method CHECK (method IN ('наличные', 'карта', 'онлайн'))
);

CREATE TABLE maintenance (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bike_id     integer      NOT NULL REFERENCES bikes (id)     ON DELETE RESTRICT,
    mechanic_id integer      NOT NULL REFERENCES employees (id) ON DELETE RESTRICT,
    started_on  date         NOT NULL,
    finished_on date,
    work_kind   varchar(30)  NOT NULL,
    description varchar(300) NOT NULL,
    cost        d_money      NOT NULL DEFAULT 0,
    CONSTRAINT known_work_kind CHECK (work_kind IN ('плановое ТО', 'ремонт')),
    CONSTRAINT maintenance_dates CHECK (finished_on IS NULL OR finished_on >= started_on)
);

CREATE FUNCTION fn_client_category_proof() RETURNS trigger AS $$
DECLARE
    v_discount numeric;
BEGIN
    SELECT discount INTO v_discount FROM client_categories WHERE id = NEW.category_id;
    IF v_discount > 0 AND (NEW.proof_doc_type IS NULL
                           OR NEW.proof_doc_number IS NULL
                           OR NEW.category_valid_until IS NULL) THEN
        RAISE EXCEPTION 'Для категории со скидкой нужны подтверждающий документ и срок его действия';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_client_category_proof
    BEFORE INSERT OR UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION fn_client_category_proof();

CREATE FUNCTION fn_check_rental_item() RETURNS trigger AS $$
DECLARE
    v_status   text;
    v_start    timestamp;
    v_end      timestamp;
    v_count    integer;
BEGIN
    SELECT status INTO v_status FROM bikes WHERE id = NEW.bike_id;
    IF v_status IN ('списан', 'на обслуживании') THEN
        RAISE EXCEPTION 'Велосипед со статусом «%» нельзя добавить в договор', v_status;
    END IF;

    SELECT issue_date + issue_time, planned_return_date + planned_return_time
      INTO v_start, v_end
      FROM rentals WHERE id = NEW.rental_id;

    IF EXISTS (
        SELECT 1
          FROM rental_items ri
          JOIN rentals r ON r.id = ri.rental_id
         WHERE ri.bike_id = NEW.bike_id
           AND ri.id IS DISTINCT FROM NEW.id
           AND r.id <> NEW.rental_id
           AND r.status IN ('оформлен', 'оплачен', 'выдан')
           AND tsrange(r.issue_date + r.issue_time,
                       COALESCE(r.actual_return_date + r.actual_return_time,
                                r.planned_return_date + r.planned_return_time)) && tsrange(v_start, v_end)
    ) THEN
        RAISE EXCEPTION 'Этот велосипед уже занят другим договором на выбранное время';
    END IF;

    SELECT count(*) INTO v_count
      FROM rental_items
     WHERE rental_id = NEW.rental_id AND id IS DISTINCT FROM NEW.id;
    IF v_count >= 5 THEN
        RAISE EXCEPTION 'В одном договоре не может быть больше 5 велосипедов';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_rental_item
    BEFORE INSERT OR UPDATE OF rental_id, bike_id ON rental_items
    FOR EACH ROW EXECUTE FUNCTION fn_check_rental_item();

CREATE FUNCTION fn_rental_status_flow() RETURNS trigger AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    v_ok := (OLD.status, NEW.status) IN (
        ('оформлен', 'оплачен'), ('оформлен', 'отменён'),
        ('оплачен', 'выдан'),    ('оплачен', 'отменён'),
        ('выдан', 'возвращён'),  ('возвращён', 'закрыт'));
    IF NOT v_ok THEN
        RAISE EXCEPTION 'Нельзя перевести договор из статуса «%» в «%»', OLD.status, NEW.status;
    END IF;

    IF NEW.status = 'выдан' THEN
        IF EXISTS (SELECT 1 FROM rental_items ri JOIN bikes b ON b.id = ri.bike_id
                    WHERE ri.rental_id = NEW.id AND b.status <> 'свободен') THEN
            RAISE EXCEPTION 'Выдать можно только велосипеды со статусом «свободен»';
        END IF;
        UPDATE bikes SET status = 'в прокате'
         WHERE id IN (SELECT bike_id FROM rental_items WHERE rental_id = NEW.id);
    ELSIF NEW.status IN ('возвращён', 'отменён') THEN
        UPDATE bikes SET status = 'свободен'
         WHERE status = 'в прокате'
           AND id IN (SELECT bike_id FROM rental_items WHERE rental_id = NEW.id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_rental_status_flow
    BEFORE UPDATE OF status ON rentals
    FOR EACH ROW EXECUTE FUNCTION fn_rental_status_flow();

CREATE FUNCTION fn_rental_total(p_rental_id integer) RETURNS numeric AS $$
DECLARE
    v_rental   rentals%ROWTYPE;
    v_planned  integer;
    v_sum      numeric;
    v_count    integer;
    v_disc     numeric := 0;
    v_group    numeric := 0;
BEGIN
    SELECT * INTO v_rental FROM rentals WHERE id = p_rental_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_planned := GREATEST(1, CEIL(EXTRACT(EPOCH FROM
        ((v_rental.planned_return_date + v_rental.planned_return_time)
         - (v_rental.issue_date + v_rental.issue_time))) / 3600.0));

    SELECT SUM(COALESCE(paid_hours, v_planned) * price_per_hour), COUNT(*)
      INTO v_sum, v_count
      FROM rental_items WHERE rental_id = p_rental_id;
    IF v_count = 0 THEN
        RETURN 0;
    END IF;

    SELECT CASE WHEN cc.discount = 0 THEN 0
                WHEN c.category_valid_until >= v_rental.issue_date THEN cc.discount
                ELSE 0 END
      INTO v_disc
      FROM clients c JOIN client_categories cc ON cc.id = c.category_id
     WHERE c.id = v_rental.client_id;

    IF v_count >= 3 THEN
        v_group := 5;
    END IF;

    RETURN ROUND(v_sum * (1 - v_disc / 100) * (1 - v_group / 100) + v_rental.fine, 2);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE PROCEDURE return_rental(p_rental_id integer, p_date date, p_time time, p_fine numeric DEFAULT 0)
LANGUAGE plpgsql AS $$
DECLARE
    v_start timestamp;
    v_hours integer;
BEGIN
    SELECT issue_date + issue_time INTO v_start FROM rentals WHERE id = p_rental_id;
    v_hours := GREATEST(1, CEIL(EXTRACT(EPOCH FROM ((p_date + p_time) - v_start)) / 3600.0));

    UPDATE rental_items SET paid_hours = v_hours WHERE rental_id = p_rental_id;

    UPDATE rentals
       SET actual_return_date = p_date,
           actual_return_time = p_time,
           fine   = p_fine,
           status = 'возвращён'
     WHERE id = p_rental_id;

    UPDATE rentals SET total = fn_rental_total(p_rental_id) WHERE id = p_rental_id;
END;
$$;

INSERT INTO positions (title, salary) VALUES
    ('Менеджер проката',            45000),
    ('Механик',                     50000),
    ('Бухгалтер',                   55000),
    ('Системный администратор',     60000);

INSERT INTO client_categories (title, discount) VALUES
    ('Обычный',            0),
    ('Студент',           10),
    ('Пенсионер',         15),
    ('Постоянный клиент',  7);

INSERT INTO bike_types (title, price_per_hour, deposit) VALUES
    ('Городской',        250,  3000),
    ('Горный',           350,  5000),
    ('Шоссейный',        400,  6000),
    ('Детский',          150,  1500),
    ('Электровелосипед', 600, 15000);

INSERT INTO employees (last_name, first_name, middle_name, birth_date, phone, hired_on, login, position_id) VALUES
    ('Крылова',  'Мария',  'Сергеевна',    '1994-03-12', '+7 912 345-67-01', '2022-04-01', 'mkrylova',   1),
    ('Орлов',    'Дмитрий','Андреевич',    '1989-09-25', '+7 912 345-67-02', '2021-05-15', 'dorlov',     2),
    ('Лебедева', 'Анна',   'Игоревна',     '1985-01-30', '+7 912 345-67-03', '2020-02-10', 'alebedeva',  3),
    ('Захаров',  'Павел',  'Олегович',     '1991-07-08', '+7 912 345-67-04', '2023-03-01', 'pzakharov',  4),
    ('Новиков',  'Артём',  'Викторович',   '1998-11-19', '+7 912 345-67-05', '2024-06-01', 'anovikov',   1);

INSERT INTO clients (last_name, first_name, middle_name, birth_date, phone, email,
                     passport_series, passport_number, registered_on,
                     proof_doc_type, proof_doc_number, category_valid_until, category_id) VALUES
    ('Соколов',  'Иван',    'Петрович',     '1990-05-14', '+7 922 111-22-01', 'ivan.sokolov@example.com',
        '7501', '123456', '2026-05-10', NULL, NULL, NULL, 1),
    ('Мамедова', 'Алия',    'Рашидовна',    '2003-02-20', '+7 922 111-22-02', 'aliya.m@example.com',
        '7503', '234567', '2025-09-10', 'Студенческий билет', '№ 21-4567', '2027-06-30', 2),
    ('Кузнецов', 'Виктор',  'Николаевич',   '1958-08-03', '+7 922 111-22-03', NULL,
        '7504', '345678', '2026-05-20', 'Пенсионное удостоверение', '№ 045-778', '2030-12-31', 3),
    ('Белова',   'Екатерина','Михайловна',  '1995-12-09', '+7 922 111-22-04', 'belova.e@example.com',
        '7505', '456789', '2026-04-02', 'Карта постоянного клиента', '№ ПК-0017', '2027-12-31', 4),
    ('Смирнов',  'Олег',    'Александрович','1987-04-27', '+7 922 111-22-05', NULL,
        '7506', '567890', '2026-06-01', NULL, NULL, NULL, 1),
    ('Ким',      'Дарья',   'Владимировна', '2001-10-01', '+7 922 111-22-06', 'kim.d@example.com',
        '7507', '678901', '2026-10-15', NULL, NULL, NULL, 1);

INSERT INTO bikes (inventory_number, frame_serial, brand, model, frame_size, release_year, commissioned_on, status, type_id) VALUES
    ('B-001', 'WTU12345001', 'Stels',   'Navigator 500', 'L',  2023, '2023-04-20', 'свободен',        1),
    ('B-002', 'WTU12345002', 'Stels',   'Navigator 500', 'M',  2023, '2023-04-20', 'свободен',        1),
    ('B-003', 'MRD77700003', 'Merida',  'Big.Nine 20',   'L',  2024, '2024-04-15', 'в прокате',       2),
    ('B-004', 'MRD77700004', 'Merida',  'Big.Nine 20',   'M',  2024, '2024-04-15', 'свободен',        2),
    ('B-005', 'GNT55500005', 'Giant',   'Contend 3',     '54', 2022, '2022-05-01', 'свободен',        3),
    ('B-006', 'FWD33300006', 'Forward', 'Racer 16',      'S',  2024, '2024-05-10', 'свободен',        4),
    ('B-007', 'FWD33300007', 'Forward', 'Racer 16',      'S',  2024, '2024-05-10', 'свободен',        4),
    ('B-008', 'XMI88800008', 'Xiaomi',  'Himo C20',      'M',  2025, '2025-04-25', 'в прокате',       5),
    ('B-009', 'WTU12345009', 'Stels',   'Navigator 500', 'L',  2021, '2021-05-05', 'на обслуживании', 1),
    ('B-010', 'ALT10100010', 'Altair',  'City Rover',    'L',  2019, '2019-05-05', 'списан',          1);

INSERT INTO rentals (contract_number, created_on, issue_date, issue_time, planned_return_date, planned_return_time,
                     actual_return_date, actual_return_time, status, fine, total, client_id, employee_id) VALUES
    ('ПР-2026-0001', '2026-06-12', '2026-06-12', '10:00', '2026-06-12', '14:00', '2026-06-12', '14:30', 'закрыт',    0,    3000.00, 1, 1),
    ('ПР-2026-0002', '2026-06-13', '2026-06-13', '11:00', '2026-06-13', '15:00', '2026-06-13', '15:00', 'закрыт',    0,     900.00, 2, 5),
    ('ПР-2026-0003', '2026-06-20', '2026-06-20', '09:00', '2026-06-20', '12:00', '2026-06-20', '13:10', 'закрыт', 1800, 3500.00, 3, 1),
    ('ПР-2026-0004', '2026-07-04', '2026-07-04', '12:00', '2026-07-04', '15:00', '2026-07-04', '15:00', 'закрыт',    0, 1722.83, 4, 1),
    ('ПР-2026-0005', '2026-11-22', '2026-11-22', '10:00', '2026-11-22', '18:00', NULL,         NULL,    'выдан',     0,     NULL, 5, 5),
    ('ПР-2026-0006', '2026-11-20', '2026-11-23', '12:00', '2026-11-23', '16:00', NULL,         NULL,    'оформлен',  0,     NULL, 1, 1),
    ('ПР-2026-0007', '2026-11-21', '2026-11-24', '10:00', '2026-11-24', '13:00', NULL,         NULL,    'оплачен',   0,     NULL, 2, 1),
    ('ПР-2026-0008', '2026-11-21', '2026-11-25', '11:00', '2026-11-25', '14:00', NULL,         NULL,    'отменён',   0,     NULL, 5, 5);

INSERT INTO rental_items (rental_id, bike_id, price_per_hour, paid_hours, condition_out, condition_in) VALUES
    (1, 1, 250, 5, 'Исправен, царапин нет',          'Исправен'),
    (1, 4, 350, 5, 'Исправен',                       'Исправен'),
    (2, 2, 250, 4, 'Исправен',                       'Исправен'),
    (3, 5, 400, 5, 'Исправен','Повреждено заднее колесо'),
    (4, 6, 150, 3, 'Исправен',                       'Исправен'),
    (4, 7, 150, 3, 'Исправен',                       'Исправен'),
    (4, 4, 350, 3, 'Исправен',                       'Исправен'),
    (5, 3, 350, NULL, 'Исправен',                    NULL),
    (5, 8, 600, NULL, 'Исправен, заряд 100 %',       NULL),
    (6, 1, 250, NULL, 'Исправен',                    NULL),
    (7, 5, 400, NULL, 'Исправен',                    NULL),
    (8, 4, 350, NULL, 'Исправен',                    NULL);

INSERT INTO payments (rental_id, paid_on, paid_at, amount, kind, method) VALUES
    (1, '2026-06-12', '09:50', 2400.00, 'предоплата',         'карта'),
    (1, '2026-06-12', '09:51', 8000.00, 'залог',              'карта'),
    (1, '2026-06-12', '14:40',  600.00, 'доплата',            'карта'),
    (1, '2026-06-12', '14:41', 8000.00, 'возврат залога',     'карта'),
    (2, '2026-06-13', '10:55',  900.00, 'предоплата',         'наличные'),
    (2, '2026-06-13', '10:56', 3000.00, 'залог',              'наличные'),
    (2, '2026-06-13', '15:10', 3000.00, 'возврат залога',     'наличные'),
    (3, '2026-06-20', '08:55', 1020.00, 'предоплата',         'онлайн'),
    (3, '2026-06-20', '08:56', 6000.00, 'залог',              'онлайн'),
    (3, '2026-06-20', '13:25', 2480.00, 'доплата',            'карта'),
    (3, '2026-06-20', '13:26', 6000.00, 'возврат залога',     'карта'),
    (4, '2026-07-04', '11:50', 1722.83, 'предоплата',         'карта'),
    (4, '2026-07-04', '11:51', 8000.00, 'залог',              'карта'),
    (4, '2026-07-04', '15:10', 8000.00, 'возврат залога',     'карта'),
    (5, '2026-11-22', '09:55', 7600.00, 'предоплата',         'карта'),
    (5, '2026-11-22', '09:56', 20000.00,'залог',              'карта'),
    (7, '2026-11-21', '18:30', 1080.00, 'предоплата',         'онлайн'),
    (7, '2026-11-21', '18:31', 6000.00, 'залог',              'онлайн'),
    (8, '2026-11-21', '12:00', 1050.00, 'предоплата',         'онлайн'),
    (8, '2026-11-21', '16:20', 1050.00, 'возврат предоплаты', 'онлайн');

INSERT INTO maintenance (bike_id, mechanic_id, started_on, finished_on, work_kind, description, cost) VALUES
    (4, 2, '2026-05-10', '2026-05-10', 'плановое ТО', 'Смазка цепи, регулировка тормозов',            600.00),
    (5, 2, '2026-06-21', '2026-06-22', 'ремонт',      'Замена заднего колеса после повреждения',     1800.00),
    (9, 2, '2026-11-20', NULL,         'плановое ТО', 'Замена цепи и тормозных колодок',                 0.00);
