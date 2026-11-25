import os

import psycopg2
import psycopg2.extras
from flask import Flask, flash, g, redirect, render_template, request, url_for, abort

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-secret-key")
DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgres://postgres:postgres@localhost:5432/bike_rental")


def col(name, label, kind="text", **kw):
    return dict(name=name, label=label, kind=kind, **kw)


BIKE_STATUS = ["свободен", "в прокате", "на обслуживании", "списан"]
RENTAL_STATUS = ["оформлен", "оплачен", "выдан", "возвращён", "закрыт", "отменён"]


TABLES = {
    "positions": dict(title="Должности", label="t.title", cols=[
        col("title", "Название"), col("salary", "Оклад, ₽", "number")]),
    "employees": dict(title="Сотрудники", label="t.last_name || ' ' || t.first_name", cols=[
        col("last_name", "Фамилия"), col("first_name", "Имя"), col("middle_name", "Отчество"),
        col("birth_date", "Дата рождения", "date"), col("phone", "Телефон"),
        col("hired_on", "Принят на работу", "date"), col("login", "Логин"),
        col("position_id", "Должность", "fk", ref="positions")]),
    "client_categories": dict(title="Категории клиентов", label="t.title", cols=[
        col("title", "Название"), col("discount", "Скидка, %", "number", dflt=True)]),
    "clients": dict(title="Клиенты", label="t.last_name || ' ' || t.first_name", cols=[
        col("last_name", "Фамилия"), col("first_name", "Имя"), col("middle_name", "Отчество"),
        col("birth_date", "Дата рождения", "date"), col("phone", "Телефон"),
        col("email", "Эл. почта"), col("passport_series", "Серия паспорта"),
        col("passport_number", "Номер паспорта"),
        col("registered_on", "Дата регистрации", "date", dflt=True),
        col("proof_doc_type", "Подтверждающий документ"), col("proof_doc_number", "Номер документа"),
        col("category_valid_until", "Категория действует до", "date"),
        col("category_id", "Категория", "fk", ref="client_categories", dflt=True)]),
    "bike_types": dict(title="Типы велосипедов", label="t.title", cols=[
        col("title", "Название"), col("price_per_hour", "Цена за час, ₽", "number"),
        col("deposit", "Залог, ₽", "number")]),
    "bikes": dict(title="Велосипеды",
                  label="t.inventory_number || ' ' || t.brand || ' ' || t.model", cols=[
        col("inventory_number", "Инвентарный номер"), col("frame_serial", "Серийный номер рамы"),
        col("brand", "Марка"), col("model", "Модель"), col("frame_size", "Размер рамы"),
        col("release_year", "Год выпуска", "number"), col("commissioned_on", "Введён в эксплуатацию", "date"),
        col("status", "Статус", "choice", options=BIKE_STATUS),
        col("type_id", "Тип", "fk", ref="bike_types")]),
    "rentals": dict(title="Прокаты (договоры)", label="t.contract_number",
                    extra=[("calc", "Расчёт по формуле, ₽", "fn_rental_total(t.id)")], cols=[
        col("contract_number", "Номер договора"), col("created_on", "Дата оформления", "date", dflt=True),
        col("issue_date", "Дата выдачи", "date"), col("issue_time", "Время выдачи", "time"),
        col("planned_return_date", "Плановая дата возврата", "date"),
        col("planned_return_time", "Плановое время возврата", "time"),
        col("actual_return_date", "Фактическая дата возврата", "date"),
        col("actual_return_time", "Фактическое время возврата", "time"),
        col("status", "Статус", "choice", options=RENTAL_STATUS),
        col("fine", "Штраф, ₽", "number", dflt=True), col("total", "Итоговая сумма, ₽", "number"),
        col("client_id", "Клиент", "fk", ref="clients"),
        col("employee_id", "Сотрудник", "fk", ref="employees")]),
    "rental_items": dict(title="Строки проката", label="t.id::text", cols=[
        col("rental_id", "Договор", "fk", ref="rentals"), col("bike_id", "Велосипед", "fk", ref="bikes"),
        col("price_per_hour", "Цена за час, ₽", "number"), col("paid_hours", "Оплачиваемые часы", "number"),
        col("condition_out", "Состояние при выдаче"), col("condition_in", "Состояние при возврате")]),
    "payments": dict(title="Платежи", label="t.id::text", cols=[
        col("rental_id", "Договор", "fk", ref="rentals"),
        col("paid_on", "Дата платежа", "date", dflt=True), col("paid_at", "Время платежа", "time", dflt=True),
        col("amount", "Сумма, ₽", "number"),
        col("kind", "Вид платежа", "choice",
            options=["предоплата", "залог", "доплата", "возврат залога", "возврат предоплаты"]),
        col("method", "Способ оплаты", "choice", options=["наличные", "карта", "онлайн"])]),
    "maintenance": dict(title="Обслуживание", label="t.id::text", cols=[
        col("bike_id", "Велосипед", "fk", ref="bikes"), col("mechanic_id", "Механик", "fk", ref="employees"),
        col("started_on", "Начало работ", "date"), col("finished_on", "Окончание работ", "date"),
        col("work_kind", "Вид работ", "choice", options=["плановое ТО", "ремонт"]),
        col("description", "Описание работ"), col("cost", "Стоимость, ₽", "number", dflt=True)]),
}


MESSAGES = {
    "client_adult": "Клиент должен быть старше 18 лет на дату регистрации.",
    "employee_adult": "Сотрудник должен быть старше 18 лет на дату приёма на работу.",
    "client_passport_unique": "Клиент с такими серией и номером паспорта уже есть.",
    "passport_series_format": "Серия паспорта – 4 цифры.",
    "passport_number_format": "Номер паспорта – 6 цифр.",
    "client_email_format": "Некорректный адрес электронной почты.",
    "client_proof_together": "Вид и номер подтверждающего документа заполняются вместе.",
    "rental_min_duration": "Прокат не может быть короче 1 часа.",
    "rental_max_duration": "Прокат не может быть длиннее 7 суток.",
    "rental_work_hours": "Время выдачи и возврата – с 09:00 до 21:00.",
    "rental_actual_after_issue": "Фактический возврат должен быть позже выдачи.",
    "rental_returned_has_actual": "Для статуса «возвращён» или «закрыт» нужны дата и время возврата.",
    "rental_closed_has_total": "Для закрытого договора нужна итоговая сумма.",
    "rental_item_unique": "Этот велосипед уже есть в договоре.",
    "paid_hours_min": "Оплачиваемых часов должно быть не меньше 1.",
    "maintenance_dates": "Окончание работ не может быть раньше начала.",
    "d_phone_format": "Телефон – в формате +7 XXX XXX-XX-XX.",
    "d_money_non_negative": "Сумма не может быть отрицательной.",
    "d_price_positive": "Цена или сумма должна быть больше нуля.",
    "d_percent_range": "Процент должен быть от 0 до 100.",
    "bike_release_year": "Год выпуска – от 2000 до текущего года.",
}


def db():
    if "db" not in g:
        g.db = psycopg2.connect(DATABASE_URL)
    return g.db


@app.context_processor
def inject_tables():
    return {"tables": TABLES}


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def query(sql_text, params=(), one=False):
    with db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql_text, params)
        rows = cur.fetchall()
    return (rows[0] if rows else None) if one else rows


def error_text(exc):
    d = exc.diag
    if d.constraint_name in MESSAGES:
        return MESSAGES[d.constraint_name]
    if exc.pgcode == "23502":
        return "Не заполнено обязательное поле: %s." % d.column_name
    if exc.pgcode == "23503":
        return "Нельзя выполнить действие: запись связана с другими таблицами."
    if exc.pgcode == "23505":
        return "Такое значение уже есть в базе (%s)." % (d.constraint_name or "уникальное поле")
    return d.message_primary or str(exc)


def get_table(name):
    if name not in TABLES:
        abort(404)
    return TABLES[name]


def options_for(ref):
    t = TABLES[ref]
    return query("SELECT t.id, %s AS label FROM %s t ORDER BY 2" % (t["label"], ref))


def prepare_form(table):
    for c in table["cols"]:
        if c["kind"] == "fk":
            c["choices"] = options_for(c["ref"])
    return table


@app.route("/")
def index():
    counts = {n: query("SELECT count(*) AS n FROM %s" % n, one=True)["n"] for n in TABLES}
    return render_template("index.html", counts=counts)


@app.route("/<name>/")
def listing(name):
    t = get_table(name)
    selects, joins = ["t.id"], []
    for i, c in enumerate(t["cols"]):
        if c["kind"] == "fk":
            r = TABLES[c["ref"]]
            joins.append("LEFT JOIN %s j%d ON j%d.id = t.%s" % (c["ref"], i, i, c["name"]))
            selects.append("%s AS %s" % (r["label"].replace("t.", "j%d." % i), c["name"]))
        else:
            selects.append("t.%s" % c["name"])
    for key, _label, expr in t.get("extra", []):
        selects.append("%s AS %s" % (expr, key))
    rows = query("SELECT %s FROM %s t %s ORDER BY t.id" % (", ".join(selects), name, " ".join(joins)))
    return render_template("list.html", name=name, t=t, rows=rows)


def read_form(t, insert):
    values = {}
    for c in t["cols"]:
        raw = request.form.get(c["name"], "").strip()
        if raw == "":
            if insert and c.get("dflt"):
                continue
            raw = None
        values[c["name"]] = raw
    return values


@app.route("/<name>/new", methods=["GET", "POST"])
def create(name):
    t = prepare_form(get_table(name))
    if request.method == "POST":
        values = read_form(t, insert=True)
        names = ", ".join(values) if values else ""
        marks = ", ".join(["%s"] * len(values))
        sql_text = ("INSERT INTO %s (%s) VALUES (%s)" % (name, names, marks)) if values \
            else "INSERT INTO %s DEFAULT VALUES" % name
        try:
            with db().cursor() as cur:
                cur.execute(sql_text, list(values.values()))
            db().commit()
            flash("Запись добавлена.", "ok")
            return redirect(url_for("listing", name=name))
        except psycopg2.Error as exc:
            db().rollback()
            flash(error_text(exc), "error")
        return render_template("form.html", name=name, t=t, row=request.form, new=True)
    return render_template("form.html", name=name, t=t, row={}, new=True)


@app.route("/<name>/<int:row_id>/edit", methods=["GET", "POST"])
def edit(name, row_id):
    t = prepare_form(get_table(name))
    current = query("SELECT * FROM %s WHERE id = %%s" % name, (row_id,), one=True)
    if current is None:
        abort(404)
    if request.method == "POST":
        values = read_form(t, insert=False)
        sets = ", ".join("%s = %%s" % k for k in values)
        try:
            with db().cursor() as cur:
                cur.execute("UPDATE %s SET %s WHERE id = %%s" % (name, sets),
                            list(values.values()) + [row_id])
            db().commit()
            flash("Запись изменена.", "ok")
            return redirect(url_for("listing", name=name))
        except psycopg2.Error as exc:
            db().rollback()
            flash(error_text(exc), "error")
        return render_template("form.html", name=name, t=t, row=request.form, new=False)
    return render_template("form.html", name=name, t=t, row=current, new=False)


@app.route("/<name>/<int:row_id>/delete", methods=["POST"])
def delete(name, row_id):
    get_table(name)
    try:
        with db().cursor() as cur:
            cur.execute("DELETE FROM %s WHERE id = %%s" % name, (row_id,))
        db().commit()
        flash("Запись удалена.", "ok")
    except psycopg2.Error as exc:
        db().rollback()
        flash(error_text(exc), "error")
    return redirect(url_for("listing", name=name))


if __name__ == "__main__":
    app.run(debug=True)
