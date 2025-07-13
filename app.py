import psycopg2
from psycopg2 import sql
from flask import Flask, render_template, request, redirect, url_for, session, jsonify
import os
import subprocess
from datetime import datetime
app = Flask(__name__)
app.secret_key = "supersecretkey"  # Ключ для работы с сессиями

# Функция для подключения к базе данных
def get_db_connection():
    conn = psycopg2.connect(
        dbname="drug_store_new",
        user="postgres",
        password="password",
        host="localhost",
        port="5432"
    )
    return conn

def create_backup(reason="manual"):
    """Создает бэкап и записывает информацию в лог"""
    conn = get_db_connection()
    db_params = conn.get_dsn_parameters()
    cursor = conn.cursor()
    
    try:
        # 1. Создаем точку восстановления в логах
        cursor.execute("""
            INSERT INTO log (operation_time, table_name, operation_type, old_data, new_data)
            VALUES (NOW(), 'SYSTEM', 'BACKUP_CREATE', 
                   jsonb_build_object('reason', %s),
                   jsonb_build_object('backup_type', 'manual'))
            RETURNING log_id;
        """, (reason,))
        backup_log_id = cursor.fetchone()[0]
        conn.commit()

        # 2. Создаем бэкап с именем, содержащим log_id
        os.environ['PGPASSWORD'] = 'password'
        pg_dump_path = r"C:\Program Files\PostgreSQL\17\bin\pg_dump.exe"
        database = db_params['dbname']
        backup_file = os.path.join(
            f"{database}_backup_logid_{backup_log_id}_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.sql"
        )

        command = [
            pg_dump_path, 
            "-U", db_params['user'], 
            "-h", db_params['host'], 
            "-p", db_params['port'], 
            "--data-only",
            "--column-inserts",
            "-f", backup_file, 
            database
        ]

        subprocess.run(command, check=True)
        
        # 3. Обновляем запись в логах с путем к бэкапу
        cursor.execute("""
            UPDATE log SET new_data = new_data || jsonb_build_object('backup_path', %s)
            WHERE log_id = %s;
        """, (backup_file, backup_log_id))
        conn.commit()
        
        return backup_file
        
    except Exception as e:
        conn.rollback()
        print(f"Ошибка при создании бэкапа: {e}")
        return None
    finally:
        cursor.close()
        conn.close()
def restore_backup(backup_file_path):
    """
    Полное восстановление из бэкапа с очисткой ВСЕХ таблиц
    """
    if not os.path.exists(backup_file_path):
        print("Ошибка: Файл бэкапа не найден")
        return False

    conn = None
    try:
        # 1. Очистка ВСЕХ таблиц
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Отключаем все ограничения
        cursor.execute("SET session_replication_role = 'replica';")
        
        # Получаем список всех таблиц
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_type = 'BASE TABLE'
            ORDER BY table_name;
        """)
        
        tables = [row[0] for row in cursor.fetchall()]
        print(f"Очищаем {len(tables)} таблиц (включая логи)")

        # Сначала очищаем таблицу log
        cursor.execute("TRUNCATE TABLE log CASCADE;")
        print("Очищена таблица: log")
        
        # Затем остальные таблицы
        for table in tables:
            if table != 'log':  # Уже очистили
                try:
                    cursor.execute(f"TRUNCATE TABLE {table} CASCADE;")
                    print(f"Очищена таблица: {table}")
                except Exception as e:
                    print(f"Ошибка при очистке {table}: {str(e)}")
                    conn.rollback()
                    continue
        
        conn.commit()
        cursor.close()
        conn.close()

        # 2. Восстановление данных
        os.environ['PGPASSWORD'] = 'password'
        psql_path = r"C:\Program Files\PostgreSQL\17\bin\psql.exe"
        db_params = get_db_connection().get_dsn_parameters()
        
        command = [
            psql_path,
            "-U", db_params['user'],
            "-h", db_params['host'],
            "-p", db_params['port'],
            "-d", db_params['dbname'],
            "-v", "ON_ERROR_STOP=1",
            "-c", "SET session_replication_role TO replica;",
            "-f", backup_file_path,
            "-c", "SET session_replication_role TO origin;"
        ]
        
        print("Начинаем восстановление данных...")
        
        result = subprocess.run(
            command,
            check=True,
            text=True,
            encoding='utf-8',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=300
        )
        
        print("Восстановление завершено успешно")
        return True
        
    except subprocess.TimeoutExpired:
        print("Ошибка: Превышено время ожидания восстановления")
        return False
    except subprocess.CalledProcessError as e:
        print(f"Ошибка восстановления (код {e.returncode}):")
        print(e.stderr)
        return False
    except Exception as e:
        print(f"Неожиданная ошибка: {str(e)}")
        return False
    finally:
        if conn and not conn.closed:
            conn.close()

def rollback_to_log(log_id):
    """Откат с полной очисткой всех таблиц"""
    conn = None
    try:
        # 1. Получаем информацию о бэкапе
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Используем отдельное соединение для чтения пути
        cursor.execute("""
            SELECT new_data->>'backup_path'
            FROM log 
            WHERE log_id = %s AND operation_type = 'BACKUP_CREATE'
            LIMIT 1;
        """, (log_id,))
        
        backup_record = cursor.fetchone()
        if not backup_record:
            print("Ошибка: Запись бэкапа не найдена")
            return False
            
        backup_path = backup_record[0]
        if not backup_path or not os.path.exists(backup_path):
            print(f"Ошибка: Файл бэкапа не найден по пути {backup_path}")
            return False

        # 2. Закрываем соединение перед восстановлением
        cursor.close()
        conn.close()
        conn = None

        # 3. Выполняем полное восстановление
        print(f"Начинаем восстановление из бэкапа {backup_path}")
        success = restore_backup(backup_path)
        
        if not success:
            print("Ошибка при восстановлении из бэкапа")
            return False

        # 4. Фиксируем откат в логах (новое соединение)
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO log (operation_time, table_name, operation_type, old_data, new_data)
            VALUES (NOW(), 'SYSTEM', 'ROLLBACK', 
                   jsonb_build_object('rollback_to_log_id', %s),
                   jsonb_build_object('status', 'success', 'backup_path', %s));
        """, (log_id, backup_path))
        
        conn.commit()
        print("Откат успешно завершен")
        return True
        
    except Exception as e:
        print(f"Критическая ошибка при откате: {str(e)}")
        if conn and not conn.closed:
            conn.rollback()
        return False
    finally:
        if conn and not conn.closed:
            cursor.close()
            conn.close()

# Функция для получения случайных 6 препаратов
def get_random_drugs():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT drug_id, name, description, pi, expiry_date, prescription, price FROM drug ORDER BY RANDOM() LIMIT 5;")
    drugs = cur.fetchall()
    cur.close()
    conn.close()
    return drugs

# Функция для получения списка фармакологических групп
def get_pharmacological_groups():
    conn = get_db_connection()
    cur = conn.cursor()
    # Сначала получаем все обычные группы
    cur.execute("SELECT * FROM farmgroup ORDER BY name;")
    groups = cur.fetchall()
    
    # Создаем искусственную группу "Все препараты" с id=0
    all_drugs_group = (0, "Все препараты")
    
    # Добавляем ее в начало списка
    groups = [all_drugs_group] + groups
    
    cur.close()
    conn.close()
    return groups

# Функция для получения препаратов по фармакологической группе
def get_drugs_by_group(group_id):
    conn = get_db_connection()
    cur = conn.cursor()
    
    if group_id == 0:  # Это наша специальная группа "Все препараты"
        cur.execute("SELECT drug_id, name, description, pi, expiry_date, prescription, price FROM drug ORDER BY name;")
    else:
        cur.execute("SELECT * FROM get_drugs_by_farmgroup_id(%s);", (group_id,))
    
    drugs = cur.fetchall()
    cur.close()
    conn.close()
    return drugs

@app.route("/error")
def error_page():
    error_message = request.args.get('message', 'Неизвестная ошибка')
    referrer = request.referrer or url_for('index')  # Если нет referrer, перенаправляем на главную
    return render_template("error.html", error_message=error_message)

def authenticate_client(login, password):
    """Аутентификация клиента."""
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        if not conn:
            return False

        cur = conn.cursor()
        cur.execute("SELECT authenticate_client(%s, %s)", (login, password))
        result = cur.fetchone()[0]
        return result  # True или False
    except Exception as e:
        print(f"Ошибка аутентификации клиента: {e}")
        return False
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

def authenticate_employee(login, password):
    """Аутентификация сотрудника (ищем в таблице employee_info)."""
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        if not conn:
            return False

        cur = conn.cursor()
        
        cur.execute("SELECT authenticate_employee(%s, %s)", (login, password))
        result = cur.fetchone()[0]

        # Если логин == "admin", добавляем флаг администратора
        if result and login == "siteAdmin":
            session["admin"] = True
        else:
            session["admin"] = False

        return result
    except Exception as e:
        print(f"Ошибка аутентификации сотрудника: {e}")
        return False
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

def register_user(login, name, surname, password, birth_date, patronymic=None):
    """Функция для регистрации нового пользователя."""
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        if not conn:
            return

        cur = conn.cursor()
        create_backup("перед регистрацией нового пользователя")
        cur.execute(
            sql.SQL("SELECT register_client(%s, %s, %s, %s, %s, %s)"),
            (login, name, surname, password, birth_date, patronymic)
        )

        conn.commit()
        print("Пользователь успешно зарегистрирован!")
        create_backup("после регистрации нового пользователя")
    except Exception as e:
        print(f"Ошибка при регистрации пользователя: {e}")
        raise  # Пробрасываем ошибку дальше
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.route("/")
def index():
    drugs = get_random_drugs()
    groups = get_pharmacological_groups()
    return render_template("base.html", drugs=drugs, groups=groups)

@app.route("/search")
def search():
    query = request.args.get("query", "").strip()  # Получаем строку поиска

    if not query:
        return redirect(url_for("index"))  # Если запрос пустой, вернемся на главную

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Ищем препараты по частичному совпадению названия (регистронезависимый поиск)
        cur.execute("""
            SELECT drug_id, name, description, pi, expiry_date, prescription, price 
            FROM drug 
            WHERE name ILIKE %s;
        """, ('%' + query + '%',))

        drugs = cur.fetchall()
        groups = get_pharmacological_groups()  # Получаем список групп для боковой панели

        return render_template("search_results.html", drugs=drugs, groups=groups, query=query)

    except Exception as e:
        print(f"Ошибка при поиске: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при поиске: {e}"))
    
    finally:
        cur.close()
        conn.close()


@app.route("/group/<int:group_id>")
def group(group_id):
    drugs = get_drugs_by_group(group_id)
    groups = get_pharmacological_groups()
    return render_template("base.html", drugs=drugs, groups=groups)

@app.route("/about")
def get_page_about():
    return render_template("about.html")

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]
        employee = "employee" in request.form  # Проверяем чекбокс

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            if employee:
                authenticated = authenticate_employee(username, password)

                if authenticated:
                    # Получаем ID сотрудника
                    cur.execute("SELECT employee_id FROM employee WHERE login = %s;", (username,))
                    employee_data = cur.fetchone()
                    
                    if employee_data:
                        session["employee_id"] = employee_data[0]  # Сохраняем ID сотрудника
                    session["username"] = username
                    session["employee"] = True

                    # Проверяем, является ли сотрудник администратором
                    cur.execute("SELECT COUNT(*) FROM employeerights er JOIN accessrights ar ON er.accessrights_id = ar.accessrights_id WHERE er.employee_id = %s AND ar.description = 'admin';", (session["employee_id"],))
                    is_admin = cur.fetchone()[0] > 0

                    if is_admin:
                        session["admin"] = True
                        return redirect(url_for("adminprofile"))
                    
                    return redirect(url_for("emprofile"))

            else:
                authenticated = authenticate_client(username, password)

                if authenticated:
                    cur.execute("SELECT client_id FROM client WHERE login = %s;", (username,))
                    client_id = cur.fetchone()

                    if client_id:
                        session["client_id"] = client_id[0]  # Сохраняем client_id в сессии
                    session["username"] = username
                    session["employee"] = False  # Не сотрудник

                    return redirect(url_for("index"))  # Перенаправление на главную

            error = "Неверный логин или пароль"
        except Exception as e:
            print(f"Ошибка аутентификации: {e}")
            error = "Ошибка авторизации"
        finally:
            cur.close()
            conn.close()

    return render_template("login.html", error=error)


#================= БЛОК АДМИНА=====================
@app.route("/adminprofile")
def adminprofile():
    # Проверяем, что пользователь — администратор
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    return render_template("adminprofile.html", username=session["username"])

@app.route("/backup_management")
def backup_management():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем список бэкапов из таблицы логов
        cur.execute("""
            SELECT log_id, operation_time, 
                   old_data->>'reason' as reason
            FROM log 
            WHERE operation_type = 'BACKUP_CREATE'
            ORDER BY operation_time DESC;
        """)
        logs = cur.fetchall()

        return render_template("backup.html", username=session["username"], logs=logs)

    except Exception as e:
        print(f"Ошибка при загрузке логов бэкапов: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке логов бэкапов: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/create_backup", methods=["POST"])
def create_backup_route():
    if "admin" not in session or not session["admin"]:
        return jsonify({"success": False, "message": "Доступ запрещен"}), 403

    reason = request.form.get("reason", "Ручное создание бэкапа")
    
    try:
        backup_file = create_backup(reason)
        if backup_file:
            return jsonify({"success": True, "message": f"Бэкап создан: {backup_file}"})
        else:
            return jsonify({"success": False, "message": "Не удалось создать бэкап"})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@app.route("/rollback_backup", methods=["POST"])
def rollback_backup():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    log_id = request.form.get("log_id")
    if not log_id:
        return redirect(url_for("error_page", message="Не указан ID лога для отката"))

    try:
        success = rollback_to_log(int(log_id))
        if success:
            print("Откат успешно выполнен", "success")
        else:
            print("Ошибка при выполнении отката", "danger")
    except Exception as e:
        print(f"Ошибка при выполнении отката: {str(e)}", "danger")

    return redirect(url_for("backup_management"))

@app.route("/employees")
def employees():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем основные данные о сотрудниках
        cur.execute("SELECT employee_id, login FROM employee;")
        employees = cur.fetchall()

        # Для каждого сотрудника получаем права доступа
        employees_with_details = []
        for e in employees:
            employee_id = e[0]

            # Получаем права доступа для сотрудника
            cur.execute("""
                SELECT ar.description 
                FROM employeerights er
                JOIN accessrights ar ON er.accessrights_id = ar.accessrights_id
                WHERE er.employee_id = %s;
            """, (employee_id,))
            rights = [row[0] for row in cur.fetchall()]

            # Объединяем данные
            employee_with_details = list(e) + [", ".join(rights)]
            employees_with_details.append(employee_with_details)

        return render_template("employees.html", username=session["username"], employees=employees_with_details)
    except Exception as e:
        print(f"Ошибка при загрузке сотрудников: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке сотрудников: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/add_employee", methods=["POST"])
def add_employee():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    login = request.form["login"].strip()
    password = request.form["password"].strip()

    if not login or not password:
        return "Логин и пароль не могут быть пустыми", 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО добавления нового сотрудника")
        cur.execute("SELECT public.register_employee(%s, %s);", (login, password))
        conn.commit()
        create_backup("ПОСЛЕ добавления нового сотрудника")
        return redirect(url_for("employees"))
    except Exception as e:
        print(f"Ошибка добавления сотрудника: {e}")
        return redirect(url_for("error_page", message=f"Ошибка добавления сотрудника: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/change_employee/<int:id>", methods=["GET"])
def show_change_employee_form(id):
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Загрузка данных сотрудника
        cur.execute("SELECT employee_id, login FROM employee WHERE employee_id = %s;", (id,))
        employee = cur.fetchone()
        if not employee:
            return "Сотрудник не найден"

        # Загрузка всех прав доступа
        cur.execute("SELECT accessrights_id, description FROM accessrights;")
        accessrights = cur.fetchall()

        # Загрузка выбранных прав доступа для сотрудника
        cur.execute("SELECT accessrights_id FROM employeerights WHERE employee_id = %s;", (id,))
        selected_accessrights = [row[0] for row in cur.fetchall()]

        return render_template("change_employee_form.html", employee=employee, accessrights=accessrights,
                               selected_accessrights=selected_accessrights)
    except Exception as e:
        print(f"Ошибка при загрузке сотрудника: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке сотрудника: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/change_employee/<int:id>", methods=["POST"])
def change_employee(id):
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    login = request.form["login"]  # Логин нельзя менять
    new_password = request.form["password"].strip()  # Новый пароль (если есть)
    selected_accessrights = request.form.getlist("accessrights")  # Права доступа

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО изменения данных сотрудника")
        # Если введен новый пароль — обновляем в БД, используя crypt() в PostgreSQL
        if new_password:
            cur.execute("UPDATE employee_info SET password = crypt(%s, gen_salt('bf')) WHERE login = %s;",
                        (new_password, login))

        # Обновление прав доступа
        cur.execute("DELETE FROM employeerights WHERE employee_id = %s;", (id,))
        for right_id in selected_accessrights:
            cur.execute("INSERT INTO employeerights (employee_id, accessrights_id) VALUES (%s, %s);", (id, right_id))

        conn.commit()
        create_backup("ПОСЛЕ изменения данных сотрудника")
        return redirect(url_for("employees"))
    except Exception as e:
        print(f"Ошибка изменения сотрудника: {e}")
        return redirect(url_for("error_page", message=f"Ошибка изменения сотрудника: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/delete_employee/<int:id>", methods=["POST"])
def delete_employee(id):
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО удаления сотрудника")
        cur.execute("""
            DELETE FROM employee_info 
            WHERE login = (SELECT login FROM employee WHERE employee_id = %s);
        """, (id,))
        conn.commit()
        create_backup("ПОСЛЕ удаления сотрудника")
        return redirect(url_for("employees"))
    except Exception as e:
        print(f"Ошибка удаления сотрудника: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления сотрудника: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/control_rights")
def control_rights():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT accessrights_id, description FROM accessrights;")
        access_rights = cur.fetchall()
        return render_template("control_rights.html", access_rights=access_rights)
    except Exception as e:
        print(f"Ошибка загрузки прав доступа: {e}")
        return redirect(url_for("error_page", message=f"Ошибка загрузки прав доступа: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/add_access_right", methods=["POST"])
def add_access_right():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    description = request.form["description"].strip()

    if not description:
        return "Описание не может быть пустым", 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО добавления права")
        cur.execute("INSERT INTO accessrights (description) VALUES (%s);", (description,))
        conn.commit()
        create_backup("ПОСЛЕ добавления права")
        return redirect(url_for("control_rights"))
    except Exception as e:
        print(f"Ошибка добавления права доступа: {e}")
        return redirect(url_for("error_page", message=f"Ошибка добавления права доступа: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/delete_access_right/<int:id>", methods=["POST"])
def delete_access_right(id):
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО удаления права")
        cur.execute("DELETE FROM accessrights WHERE accessrights_id = %s;", (id,))
        conn.commit()
        create_backup("ПОСЛЕ удаления права")
        return redirect(url_for("control_rights"))
    except Exception as e:
        print(f"Ошибка удаления права доступа: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления права доступа: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/control_invoice")
def control_invoice():
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем список накладных и препаратов в них
        cur.execute("""
            SELECT i.invoice_id, i.status, 
                   STRING_AGG(d.name, ', ') AS drugs
            FROM public.invoice i
            LEFT JOIN public.druglist dl ON i.invoice_id = dl.invoice_id
            LEFT JOIN public.drug d ON dl.drug_id = d.drug_id
            GROUP BY i.invoice_id;
        """)
        invoices = cur.fetchall()

        return render_template("control_invoice.html", username=session["username"], invoices=invoices)

    except Exception as e:
        print(f"Ошибка при загрузке накладных: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке накладных: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/confirm_invoice", methods=["POST"])
def confirm_invoice():
    # Логируем весь запрос для диагностики
    print("Данные формы:", request.form)

    try:
        invoice_id = request.form["invoice_id"]
    except KeyError:
        return "Ошибка: Невозможно получить invoice_id из формы", 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО подтверждения накладной")
        cur.execute("SELECT public.confirm_invoice(%s);", (invoice_id,))
        conn.commit()
        create_backup("ПОСЛЕ подтверждения накладной")
        return redirect(url_for("control_invoice"))
    except Exception as e:
        print(f"Ошибка при подтверждении накладной: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при подтверждении накладной: {e}"))
    finally:
        cur.close()
        conn.close()

        
@app.route("/invoice_list/<int:invoice_id>")
def view_invoice(invoice_id):
    if "admin" not in session or not session["admin"]:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Выводим подробности перед запросом
        print(f"Получаем препараты для накладной с ID: {invoice_id}")

        # Получаем все препараты в указанной накладной
        cur.execute("""
            SELECT d.name, dl.amount, d.drug_id
            FROM public.druglist dl
            JOIN public.drug d ON dl.drug_id = d.drug_id
            WHERE dl.invoice_id = %s;
        """, (invoice_id,))
        drugs_in_invoice = cur.fetchall()

        # Получаем статус накладной (например, 0 - не подтверждена, 1 - подтверждена)
        cur.execute("SELECT status FROM public.invoice WHERE invoice_id = %s;", (invoice_id,))
        status = cur.fetchone()[0]  # Получаем статус накладной
        # Проверяем данные
        print("Данные из накладной:", drugs_in_invoice)

        # Получаем список всех препаратов для выпадающего списка
        cur.execute("SELECT drug_id, name FROM public.drug;")
        all_drugs = cur.fetchall()

        return render_template("invoice_list.html", invoice_id=invoice_id, drugs_in_invoice=drugs_in_invoice, all_drugs=all_drugs, status=status)
    except Exception as e:
        print(f"Ошибка при просмотре накладной: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при просмотре накладной: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/create_invoice", methods=["POST"])
def create_invoice():
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО создания накладной")
        # Создаем новую накладную с пустым статусом (не подтверждена)
        cur.execute("""
            INSERT INTO public.invoice (status)
            VALUES (false) RETURNING invoice_id;
        """)
        new_invoice_id = cur.fetchone()[0]
        conn.commit()
        create_backup("ПОСЛЕ создания накладной")
        # Перенаправляем на страницу управления накладными
        return redirect(url_for('control_invoice'))
    except Exception as e:
        print(f"Ошибка при создании накладной: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при создании накладной: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/add_drug_to_invoice/<int:invoice_id>", methods=["POST"])
def add_drug_to_invoice(invoice_id):
    drug_id = request.form["drug_id"]
    amount = request.form["amount"]

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("""
            INSERT INTO public.druglist (invoice_id, drug_id, amount)
            VALUES (%s, %s, %s);
        """, (invoice_id, drug_id, amount))
        conn.commit()
        return redirect(url_for("view_invoice", invoice_id=invoice_id))
    except Exception as e:
        print(f"Ошибка при добавлении препарата в накладную: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при добавлении препарата в накладную: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/delete_drug_from_invoice/<int:invoice_id>/<int:drug_id>", methods=["POST"])
def delete_drug_from_invoice(invoice_id, drug_id):
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО удаления из накладной")
        cur.execute("""
            DELETE FROM public.druglist
            WHERE invoice_id = %s AND drug_id = %s;
        """, (invoice_id, drug_id))
        conn.commit()
        create_backup("ПОСЛЕ удаления из накладной")
        return redirect(url_for("view_invoice", invoice_id=invoice_id))
    except Exception as e:
        print(f"Ошибка при удалении препарата из накладной: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при удалении препарата из накладной: {e}"))
    finally:
        cur.close()
        conn.close()


#================= БЛОК СОТРУДНИКА=====================
@app.route("/emprofile")
def emprofile():
    print("Session data:", session)

    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем права сотрудника
        cur.execute("""
            SELECT ar.description 
            FROM employeerights er
            JOIN accessrights ar ON er.accessrights_id = ar.accessrights_id
            WHERE er.employee_id = %s;
        """, (session["employee_id"],))
        rights = [row[0] for row in cur.fetchall()]

        return render_template("emprofile.html", username=session["username"], rights=rights)
    except Exception as e:
        print(f"Ошибка при загрузке профиля сотрудника: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке профиля сотрудника: {e}"))
    finally:
        cur.close()
        conn.close()


@app.route("/unvbills")
def unvbills():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем список неоплаченных счетов
        cur.execute("SELECT * FROM get_all_unv_bills();")
        bills = cur.fetchall()

        # Для каждого чека получаем список рецептурных препаратов
        bills_with_drugs = []
        for bill in bills:
            bill_id = bill[0]
            cur.execute("SELECT * FROM get_prescription_drugs_by_bill(%s);", (bill_id,))
            drugs = cur.fetchone()[0]  # Получаем строку с названиями препаратов
            bills_with_drugs.append((bill[0], bill[1], bill[3], drugs))  # Добавляем данные в список

        return render_template("unvbills.html", bills=bills_with_drugs, prescriptions=None)
    except Exception as e:
        print(f"Ошибка при загрузке чеков: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке чеков: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/approve_bill/<int:bill_id>", methods=["POST"])
def approve_bill(bill_id):  # Добавьте параметр bill_id
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Вызываем функцию подтверждения чека
        create_backup("ДО подтверждения чека")
        cur.execute("SELECT approve_bill(%s);", (bill_id,))
        conn.commit()
        create_backup("ПОСЛЕ подтверждения чека")
        return redirect(url_for("unvbills"))
    except Exception as e:
        print(f"Ошибка при подтверждении чека: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при подтверждении чека: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/show_px/<int:client_id>", methods=["POST"])
def showpx(client_id):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем все рецепты для клиента
        cur.execute("SELECT * FROM get_prescriptions_by_client(%s);", (client_id,))
        prescriptions = cur.fetchall()

        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':  # AJAX-запрос
            # Возвращаем рецепты в формате JSON
            return jsonify([list(px) for px in prescriptions])

        # Получаем список неоплаченных счетов для отображения на той же странице
        cur.execute("SELECT * FROM get_all_unv_bills();")
        bills = cur.fetchall()

        bills_with_drugs = []
        for bill in bills:
            bill_id = bill[0]
            cur.execute("SELECT * FROM get_prescription_drugs_by_bill(%s);", (bill_id,))
            drugs = cur.fetchone()[0]
            bills_with_drugs.append((bill[0], bill[1], bill[3], drugs))

        return render_template("unvbills.html", bills=bills_with_drugs, prescriptions=prescriptions)
    except Exception as e:
        print(f"Ошибка при загрузке рецептов: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке рецептов: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/unvpx")
def unvpx():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT * FROM get_all_unv_px();")
        pxs = cur.fetchall()
        return render_template("unvpx.html", username=session["employee"], prescriptions=pxs)
    except Exception as e:
        print(f"Ошибка при загрузке рецептов: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке рецептов: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/approve_px/<int:px_id>", methods=["POST"])
def approve_px(px_id):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT client_id FROM prescription WHERE px_id = %s;", (px_id,))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]
        
        create_backup("ДО подтверждения рецепта")

        cur.execute("SELECT confirm_px_status(%s, %s);", (px_id, client_id))
        conn.commit()

        create_backup("ПОСЛЕ подтверждения рецепта")

        return redirect(url_for("unvpx"))
    except Exception as e:
        print(f"Ошибка подтверждения рецепта: {e}")
        return redirect(url_for("error_page", message=f"Ошибка подтверждения рецепта: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/activesubs")
def activesubs():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT * FROM get_all_activesub_info();")
        subs = cur.fetchall()
        return render_template("activesubs.html", username=session["employee"], subs=subs)
    except Exception as e:
        print(f"Ошибка при загрузке веществ: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке веществ: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/add_asub", methods=["POST"])
def add_sub():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    sub_name = request.form["sub_name"]
    sub_status = request.form["sub_status"]
    sub_desc = request.form["sub_desc"]

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО добавления вещества")
        cur.execute("SELECT add_activesub_info(%s, %s, %s);",
                    (sub_name, sub_status, sub_desc))

        conn.commit()
        create_backup("ПОСЛЕ добавления вещества")
        return redirect(url_for("activesubs"))
    except Exception as e:
        print(f"Ошибка добавления вещества: {e}")
        return redirect(url_for("error_page", message=f"Ошибка добавления вещества: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/delete_sub/<name>", methods=["POST"])
def delete_sub(name):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()
    print(name)
    try:
        create_backup("ДО удаления вещества")
        cur.execute("SELECT delete_activesub_info(%s);", (name,))
        conn.commit()
        create_backup("ПОСЛЕ удаления вещества")
        return redirect(url_for("activesubs"))
    except Exception as e:
        print(f"Ошибка удаления вещества: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления вещества: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/change_sub/<name>", methods=["GET"])
def show_change_sub_form(name):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM activesub_info WHERE name = %s;", (name,))
        sub = cur.fetchone()
        if not sub:
            return "Вещество не найдено"

        return render_template("change_sub_form.html", sub=sub)
    except Exception as e:
        print(f"Ошибка при загрузке вещества: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке вещества: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/change_sub/<name>", methods=["POST"])
def change_sub(name):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    new_active = request.form.get("sub_active") == "true"
    new_description = request.form.get("sub_description")

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        create_backup("ДО изменения вещества")
        cur.execute("SELECT update_activesub_info(%s, %s, %s);", (name, new_active, new_description))
        conn.commit()
        create_backup("ПОСЛЕ изменения вещества")
        return redirect(url_for("activesubs"))
    except Exception as e:
        print(f"Ошибка изменения вещества: {e}")
        return redirect(url_for("error_page", message=f"Ошибка изменения вещества: {e}"))
    finally:
        cur.close()
        conn.close()

#======================FARMGROUP INFO========================#
@app.route("/farmgroups")
def farmgroups():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT * FROM get_all_farmgroup_info();")
        groups = cur.fetchall()
        return render_template("farmgroups.html", username=session["employee"], groups=groups)
    except Exception as e:
        print(f"Ошибка при загрузке групп: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке групп: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/add_group", methods=["POST"])
def add_group():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    g_name = request.form["g_name"]
    g_desc = request.form["g_desc"]

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО добавления группы")
        cur.execute("SELECT add_farmgroup_info(%s, %s);",
                    (g_name, g_desc))

        conn.commit()
        create_backup("ПОСЛЕ добавления группы")
        return redirect(url_for("farmgroups"))
    except Exception as e:
        print(f"Ошибка добавления группы: {e}")
        return redirect(url_for("error_page", message=f"Ошибка добавления группы: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/delete_group/<name>", methods=["POST"])
def delete_group(name):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО удаления группы")
        cur.execute("SELECT delete_farmgroup_info(%s);", (name,))
        conn.commit()
        create_backup("ПОСЛЕ удаления группы")
        return redirect(url_for("farmgroups"))
    except Exception as e:
        print(f"Ошибка удаления группы: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления группы: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/change_group/<name>", methods=["GET"])
def show_change_group_form(name):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM farmgroup_info WHERE name = %s;", (name,))
        g = cur.fetchone()
        if not g:
            return "Группа не найдена"

        return render_template("change_group_form.html", g=g)
    except Exception as e:
        print(f"Ошибка при загрузке группы: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке группы: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/change_group/<name>", methods=["POST"])
def change_group(name):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    new_description = request.form.get("g_description")

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        create_backup("ДО изменения группы")
        cur.execute("SELECT update_farmgroup_info(%s, %s);", (name, new_description))
        conn.commit()
        create_backup("ПОСЛЕ изменения группы")
        return redirect(url_for("farmgroups"))
    except Exception as e:
        print(f"Ошибка изменения группы: {e}")
        return redirect(url_for("error_page", message=f"Ошибка изменения группы: {e}"))
    finally:
        cur.close()
        conn.close()

#==========================DRUGS========================#
@app.route("/drugs")
def drugs():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем основные данные о препаратах
        cur.execute("SELECT drug_id, name, description, pi, expiry_date, prescription, price, amount FROM drug;")
        drugs = cur.fetchall()

        # Для каждого препарата получаем фармгруппы и активные вещества
        drugs_with_details = []
        for drug in drugs:
            drug_id = drug[0]

            # Получаем фармгруппы для препарата
            cur.execute("""
                SELECT fg.name 
                FROM farmgrouplist fgl
                JOIN farmgroup fg ON fgl.farmgroup_id = fg.farmgroup_id
                WHERE fgl.drug_id = %s;
            """, (drug_id,))
            farmgroups = [row[0] for row in cur.fetchall()]

            # Получаем активные вещества для препарата
            cur.execute("""
                SELECT asub.name 
                FROM activesublist asl
                JOIN activesub asub ON asl.activesub_id = asub.activesub_id
                WHERE asl.drug_id = %s;
            """, (drug_id,))
            activesubs = [row[0] for row in cur.fetchall()]

            # Объединяем данные
            drug_with_details = list(drug) + [", ".join(farmgroups), ", ".join(activesubs)]
            drugs_with_details.append(drug_with_details)

        return render_template("drugs.html", username=session["employee"], drugs=drugs_with_details)
    except Exception as e:
        print(f"Ошибка при загрузке препаратов: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке препаратов: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/add_drug", methods=["POST"])
def add_drug():
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    name = request.form["name"]
    description = request.form["description"]
    pi = request.form["pi"]
    expiry_date = request.form["expiry_date"]
    prescription = request.form["prescription"] == "true"
    price = int(request.form["price"])
    amount = int(request.form["amount"])

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО добавления препарата")
        cur.execute("CALL add_drug(%s, %s, %s, %s, %s, %s, %s);",
                    (description, pi, expiry_date, prescription, price, name, amount))
        conn.commit()
        create_backup("ПОСЛЕ добавления препарата")
        return redirect(url_for("drugs"))
    except Exception as e:
        print(f"Ошибка добавления препарата: {e}")
        return redirect(url_for("error_page", message=f"Ошибка добавления препарата: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/delete_drug/<int:id>", methods=["POST"])
def delete_drug(id):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО удаления препарата")
        cur.execute("DELETE FROM drug WHERE drug_id = %s;", (id,))
        conn.commit()
        create_backup("ПОСЛЕ удаления препарата")
        return redirect(url_for("drugs"))
    except Exception as e:
        print(f"Ошибка удаления препарата: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления препарата: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/change_drug/<int:id>", methods=["GET"])
def show_change_drug_form(id):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Загрузка данных препарата
        cur.execute("SELECT drug_id, name, description, pi, expiry_date, prescription, price, amount FROM drug WHERE drug_id = %s;", (id,))
        drug = cur.fetchone()
        if not drug:
            return "Препарат не найден"

        # Загрузка всех фармгрупп
        cur.execute("SELECT farmgroup_id, name FROM farmgroup;")
        farmgroups = cur.fetchall()

        # Загрузка всех активных веществ
        cur.execute("SELECT activesub_id, name FROM activesub;")
        activesubs = cur.fetchall()

        # Загрузка выбранных фармгрупп для препарата
        cur.execute("SELECT farmgroup_id FROM farmgrouplist WHERE drug_id = %s;", (id,))
        selected_farmgroups = [row[0] for row in cur.fetchall()]

        # Загрузка выбранных активных веществ для препарата
        cur.execute("SELECT activesub_id FROM activesublist WHERE drug_id = %s;", (id,))
        selected_activesubs = [row[0] for row in cur.fetchall()]

        return render_template("change_drug_form.html", drug=drug, farmgroups=farmgroups, activesubs=activesubs,
                               selected_farmgroups=selected_farmgroups, selected_activesubs=selected_activesubs)
    except Exception as e:
        print(f"Ошибка при загрузке препарата: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке препарата: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/change_drug/<int:id>", methods=["POST"])
def change_drug(id):
    if "employee" not in session or not session["employee"] or session.get("admin"):
        return redirect(url_for("login"))

    # Основные данные препарата
    name = request.form["name"]
    description = request.form["description"]
    pi = request.form["pi"]
    expiry_date = request.form["expiry_date"]
    prescription = request.form["prescription"] == "true"
    price = int(request.form["price"])
    amount = int(request.form["amount"])

    # Выбранные фармгруппы и активные вещества
    selected_farmgroups = request.form.getlist("farmgroups")
    selected_activesubs = request.form.getlist("activesubs")

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Обновление данных препарата
        create_backup("ДО ИЗМЕНЕНИЯ препарата")
        cur.execute("CALL update_drug(%s, %s, %s, %s, %s, %s, %s, %s);",
                    (id, description, pi, expiry_date, prescription, price, name, amount))

        # Обновление фармгрупп
        cur.execute("DELETE FROM farmgrouplist WHERE drug_id = %s;", (id,))
        for group_id in selected_farmgroups:
            cur.execute("INSERT INTO farmgrouplist (drug_id, farmgroup_id) VALUES (%s, %s);", (id, group_id))

        # Обновление активных веществ
        cur.execute("DELETE FROM activesublist WHERE drug_id = %s;", (id,))
        for sub_id in selected_activesubs:
            cur.execute("INSERT INTO activesublist (drug_id, activesub_id, quantity) VALUES (%s, %s, 1);", (id, sub_id))
        conn.commit()
        create_backup("ПОСЛЕ ИЗМЕНЕНИЯ препарата")
        return redirect(url_for("drugs"))
    except Exception as e:
        print(f"Ошибка изменения препарата: {e}")
        return redirect(url_for("error_page", message=f"Ошибка изменения препарата: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/profile")
def profile():

    if "username" in session:
        if "admin" in session and session["admin"]:
            return redirect(url_for("adminprofile"))
        if "employee" in session and session["employee"]:
            return redirect(url_for("emprofile"))
        return render_template("profile.html", username=session["username"])
    else:
        return redirect(url_for("login"))
    
@app.route("/editprofile", methods=["GET", "POST"])
def editprofile():
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем текущие данные клиента из таблицы client_info
        cur.execute(
            "SELECT name, surname, patronymic, birth_date FROM client_info WHERE login = %s;",
            (session["username"],)
        )
        client_data = cur.fetchone()

        if not client_data:
            return "Ошибка: клиент не найден"

        name, surname, patronymic, birth_date = client_data

        if request.method == "POST":
            # Получаем данные из формы
            new_name = request.form.get("name")
            new_surname = request.form.get("surname")
            new_patronymic = request.form.get("patronymic")
            new_password = request.form.get("password")
            new_birth_date = request.form.get("birth_date")
            create_backup("ДО ИЗМЕНЕНИЯ профиля клиента")
            # Обновляем данные, если они заполнены
            if new_name:
                cur.execute(
                    "UPDATE client_info SET name = %s WHERE login = %s;",
                    (new_name, session["username"])
                )
            if new_surname:
                cur.execute(
                    "UPDATE client_info SET surname = %s WHERE login = %s;",
                    (new_surname, session["username"])
                )
            if new_patronymic:
                cur.execute(
                    "UPDATE client_info SET patronymic = %s WHERE login = %s;",
                    (new_patronymic, session["username"])
                )
            if new_password:
                cur.execute(
                    "UPDATE client_info SET password = %s WHERE login = %s;",
                    (new_password, session["username"])
                )
            if new_birth_date:
                cur.execute(
                    "UPDATE client_info SET birth_date = %s WHERE login = %s;",
                    (new_birth_date, session["username"])
                )

            conn.commit()
            create_backup("ПОСЛЕ ИЗМЕНЕНИЯ профиля клиента")
            return redirect(url_for("profile"))

        # Передаем текущие данные в шаблон
        return render_template(
            "editprofile.html",
            username=session["username"],
            name=name,
            surname=surname,
            patronymic=patronymic,
            birth_date=birth_date
        )

    except Exception as e:
        print(f"Ошибка при загрузке или обновлении данных: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке или обновлении данных: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/pay_info", methods=["GET", "POST"])
def pay_info():
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем текущие данные клиента из таблицы client_info
        cur.execute(
            "SELECT phone_number FROM client_info WHERE login = %s;",
            (session["username"],))
        client_data = cur.fetchone()

        if not client_data:
            return "Ошибка: клиент не найден"

        # Извлекаем номер телефона из кортежа
        number = client_data[0] if client_data[0] else ""

        if request.method == "POST":
            create_backup("ДО изменения номера клиента")
            # Получаем данные из формы
            new_num = request.form.get("number")

            # Обновляем данные, если они заполнены
            if new_num:
                cur.execute(
                    "UPDATE client_info SET phone_number = %s WHERE login = %s;",
                    (new_num, session["username"])
                )
                conn.commit()
                create_backup("ПОСЛЕ изменения номера клиента")
                return redirect(url_for("profile"))

        # Передаем текущие данные в шаблон
        return render_template(
            "pay_info.html",
            username=session["username"],
            number=number,
        )

    except Exception as e:
        print(f"Ошибка при загрузке или обновлении данных: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке или обновлении данных: {e}"))
    finally:
        cur.close()
        conn.close()

    
@app.route("/mypx")
def mypx():
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем client_id по логину
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]

        # Получаем список рецептов
        cur.execute("SELECT px_id, drug_name, expiry_date, drug_quantity, status FROM get_prescriptions_by_client(%s);", (client_id,))
        prescriptions = cur.fetchall()

        return render_template("mypx.html", username=session["username"], prescriptions=prescriptions)
    except Exception as e:
        print(f"Ошибка при загрузке рецептов: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке рецептов: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/delete_prescription/<int:px_id>", methods=["POST"])
def delete_prescription(px_id):
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем client_id по логину
        create_backup("ДО удаления рецепта клиентом")
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]

        # Вызываем функцию удаления рецепта
        cur.execute("SELECT delete_prescription(%s, %s);", (px_id, client_id))
        conn.commit()
        create_backup("ПОСЛЕ удаления рецепта клиентом")
        return redirect(url_for("mypx"))
    except Exception as e:
        print(f"Ошибка удаления рецепта: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления рецепта: {e}"))
    finally:
        cur.close()
        conn.close()

    
@app.route("/myshopcart")
def myshopcart():
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем client_id по логину
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]
        cur.execute("SELECT * FROM view_shopcart(%s);", (client_id,))
        products = cur.fetchall()

        # Если данные есть, извлекаем информацию о чеке
        if products:
            bill_info = {
                "bill_id": products[0][0],  # ID чека
                "date_time": products[0][1],  # Дата и время
                "status": products[0][2],  # Статус
                "bill_amount": products[0][3],  # Сумма
            }
            drugs = [
                {
                    "drug_id": p[4],  # ID препарата
                    "drug_name": p[5],  # Название препарата
                    "drug_price": p[6],  # Цена препарата
                    "drug_prescription": p[7],
                    "quantity": p[8]  # Количество
                }
                for p in products
            ]
        else:
            bill_info = None
            drugs = []

        return render_template(
            "myshopcart.html",
            username=session["username"],
            bill_info=bill_info,
            drugs=drugs,
        )
    except Exception as e:
        print(f"Ошибка при загрузке корзины: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке корзины: {e}"))
    finally:
        cur.close()
        conn.close()
@app.route("/update_cart_quantity", methods=["POST"])
def update_cart_quantity():
    if "username" not in session:
        return jsonify(success=False, error="Требуется авторизация"), 401

    try:
        data = request.get_json()
        drug_id = data['drug_id']
        quantity = data['quantity']
        
        if quantity < 1:
            return jsonify(success=False, error="Количество не может быть меньше 1"), 400
            
        conn = get_db_connection()
        with conn.cursor() as cur:
            # Получаем client_id
            cur.execute("SELECT client_id FROM client WHERE login = %s", 
                        (session["username"],))
            client_id = cur.fetchone()[0]
            
            # Вызываем обновление
            cur.execute("SELECT * FROM update_cart_item(%s, %s, %s)", 
                       (client_id, drug_id, quantity))
            result = cur.fetchone()
            conn.commit()
            
            if not result:
                return jsonify(success=False, error="Препарат не найден"), 404
                
            return jsonify(
                success=True,
                new_quantity=result[0],
                item_total=float(result[1])
            )
            
    except Exception as e:
        conn.rollback()
        return jsonify(success=False, error=str(e)), 500
    finally:
        if 'conn' in locals():
            conn.close()
@app.route("/get_drug_quantity", methods=["GET"])
def get_drug_quantity():
    if "username" not in session:
        return jsonify({"success": False, "error": "Необходима авторизация"}), 401

    drug_id = request.args.get('drug_id')
    if not drug_id:
        return jsonify({"success": False, "error": "Не указан ID препарата"}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем client_id
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()[0]

        # Получаем текущее количество
        cur.execute("""
            SELECT sc.quantity 
            FROM shoppingcart sc
            WHERE sc.drug_id = %s 
            AND sc.bill_id = (SELECT bill_id FROM bill WHERE client_id = %s AND status = false)
            """, (drug_id, client_id))
        
        result = cur.fetchone()
        if result:
            return jsonify({
                "success": True,
                "quantity": result[0]
            })
        else:
            return jsonify({"success": False, "error": "Препарат не найден"}), 404

    except Exception as e:
        print(f"Ошибка получения количества: {e}")
        return jsonify({"success": False, "error": str(e)}), 500
    finally:
        cur.close()
        conn.close()
@app.route("/delete_from_shopcart/<int:drug_id>", methods=["POST"])
def delete_from_shopcart(drug_id):
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО удаления из корзины")
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]

        # Вызываем функцию удаления из корзины
        cur.execute("SELECT remove_from_cart(%s, %s);", (client_id, drug_id))
        conn.commit()
        create_backup("ПОСЛЕ удаления из корзины")
        return redirect(url_for("myshopcart"))
    except Exception as e:
        print(f"Ошибка удаления рецепта: {e}")
        return redirect(url_for("error_page", message=f"Ошибка удаления рецепта: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/pay_bill/<int:bill_id>", methods=["POST"])
def pay_bill(bill_id):
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        create_backup("ДО совершения оплаты клиентом")
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]

        cur.execute("SELECT pay_bill(%s, %s);", (bill_id, client_id))
        conn.commit()
        create_backup("ПОСЛЕ совершения оплаты клиентом")
        return redirect(url_for("myshopcart"))
    except Exception as e:
        print(f"Ошибка оплаты: {e}")
        return redirect(url_for("error_page", message=f"Ошибка оплаты: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/mybills")
def mybills():
    if "username" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Получаем client_id по логину
        cur.execute("SELECT client_id FROM client WHERE login = %s;", (session["username"],))
        client_id = cur.fetchone()

        if not client_id:
            return "Ошибка: клиент не найден"

        client_id = client_id[0]

        # Получаем список чеков с помощью функции view_mybills
        cur.execute("SELECT * FROM view_mybills(%s);", (client_id,))
        bills = cur.fetchall()

        return render_template("mybills.html", username=session["username"], bills=bills)
    except Exception as e:
        print(f"Ошибка при загрузке чеков: {e}")
        return redirect(url_for("error_page", message=f"Ошибка при загрузке чеков: {e}"))
    finally:
        cur.close()
        conn.close()


@app.route("/pxform")
def pxform():
    if "username" in session:
        return render_template("pxform.html", username=session["username"])
    else:
        return redirect(url_for("login"))

@app.route("/add_prescription", methods=["POST"])
def add_prescription():
    if "username" not in session:
        return redirect(url_for("login"))

    drug_name = request.form["drug_name"]
    expiry_date = request.form["expiry_date"]
    drug_quantity = request.form["drug_quantity"]

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Передаем login вместо client_id
        create_backup("ДО добавления рецепта клиентом")
        cur.execute("SELECT add_prescription(%s, %s, %s, %s);",
                    (session["username"], expiry_date, drug_name, drug_quantity))

        conn.commit()
        create_backup("ПОСЛЕ добавления рецепта клиентом")
        return redirect(url_for("profile"))
    except Exception as e:
        print(f"Ошибка добавления рецепта: {e}")
        return redirect(url_for("error_page", message=f"Ошибка добавления рецепта: {e}"))
    finally:
        cur.close()
        conn.close()

@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        login = request.form["username"]
        password = request.form["password"]
        name = request.form["reg_name"]
        surname = request.form["reg_surname"]
        patronymic = request.form.get("reg_patronymic", None)
        birth_date = request.form["reg_bdate"]
        print(f"отладка {login}, {name}, {password}, {surname}, {patronymic}, {birth_date}")
        if not all([login, password, name, surname, birth_date]):
            print("Ошибка: не все поля заполнены!")
            return render_template("register.html", error="Все обязательные поля должны быть заполнены!")

        try:
            print(f"Попытка регистрации: {login}, {name}, {surname}")
            register_user(login, name, surname, password, birth_date, patronymic)
            return redirect(url_for("login"))  # После успешной регистрации перенаправляем на страницу входа
        except Exception as e:
            print(f"Ошибка регистрации: {e}")
            return render_template("register.html", error=f"Ошибка регистрации: {e}")

    return render_template("register.html")


def get_client_id(conn, username):
    cur = conn.cursor()
    cur.execute("SELECT client_id FROM client WHERE login = %s;", (username,))
    client_id = cur.fetchone()
    cur.close()
    return client_id[0] if client_id else None

@app.route("/add_to_cart", methods=["POST"])
def add_to_cart():
    if "username" not in session:
        return jsonify({"success": False, "error": "Вы не авторизованы!"})

    conn = get_db_connection()  # Открываем соединение
    try:
        client_id = get_client_id(conn, session["username"])  # Передаём уже открытую БД
        if not client_id:
            return jsonify({"success": False, "error": "Пользователь не найден."})

        data = request.get_json()
        drug_id = data.get("drug_id")
        if not drug_id:
            return jsonify({"success": False, "error": "Неверный идентификатор препарата."})
        #create_backup("ДО добавления препарата в корзину")
        cur = conn.cursor()
        cur.execute("SELECT add_to_cart(%s, %s, 1);", (client_id, drug_id))
        conn.commit()
        cur.close()
        #create_backup("ПОСЛЕ добавления препарата в корзину")
        return jsonify({"success": True})

    except Exception as e:
        return jsonify({"success": False, "error": str(e)})

    finally:
        conn.close()  # Закрываем соединение

@app.route("/logout")
def logout():
    session.pop("username", None)
    session.pop("client_id", None)
    session.pop("employee", None)
    session.pop("admin", None) 
    session.pop("employee_id", None) 
    return redirect(url_for("login"))

if __name__ == "__main__":
    app.run(debug=True)
