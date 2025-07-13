--
-- PostgreSQL database dump
--

-- Dumped from database version 17.3
-- Dumped by pg_dump version 17.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: add_activesub_info(character varying, boolean, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_activesub_info(p_name character varying, p_active boolean, p_description character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO public.activesub_info (name, active, description)
    VALUES (p_name, p_active, p_description);
END;
$$;


ALTER FUNCTION public.add_activesub_info(p_name character varying, p_active boolean, p_description character varying) OWNER TO postgres;

--
-- Name: add_drug(character varying, character varying, date, boolean, integer, character varying, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.add_drug(IN p_description character varying, IN p_pi character varying, IN p_expiry_date date, IN p_prescription boolean, IN p_price integer, IN p_name character varying, IN p_amount integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Вставляем новую запись
    INSERT INTO public.drug (description, pi, expiry_date, prescription, price, name, amount)
    VALUES (p_description, p_pi, p_expiry_date, p_prescription, p_price, p_name, p_amount);
END;
$$;


ALTER PROCEDURE public.add_drug(IN p_description character varying, IN p_pi character varying, IN p_expiry_date date, IN p_prescription boolean, IN p_price integer, IN p_name character varying, IN p_amount integer) OWNER TO postgres;

--
-- Name: add_drug_to_druglist(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_drug_to_druglist(p_drug_id integer, p_amount integer, p_invoice_id integer DEFAULT NULL::integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_invoice_id integer;
    v_existing_amount integer;
    v_invoice_status boolean;
BEGIN
    -- Если переданный p_invoice_id равен NULL, создаём новую накладную
    IF p_invoice_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.invoice WHERE invoice_id = p_invoice_id) THEN
        INSERT INTO public.invoice (status)
        VALUES (false)
        RETURNING invoice_id INTO v_invoice_id;

        RAISE NOTICE 'Создана новая накладная с ID %', v_invoice_id;
    ELSE
        -- Проверяем статус существующей накладной
        SELECT status INTO v_invoice_status FROM public.invoice WHERE invoice_id = p_invoice_id;

        IF v_invoice_status THEN
            RAISE EXCEPTION 'Накладная с ID % уже закрыта', p_invoice_id;
        END IF;

        v_invoice_id := p_invoice_id;
    END IF;

    -- Проверяем, существует ли препарат
    IF NOT EXISTS (SELECT 1 FROM public.drug WHERE drug_id = p_drug_id) THEN
        RAISE EXCEPTION 'Препарат с ID % не существует', p_drug_id;
    END IF;

    -- Проверяем, есть ли препарат в накладной
    SELECT amount INTO v_existing_amount
    FROM public.druglist
    WHERE invoice_id = v_invoice_id AND drug_id = p_drug_id;

    IF v_existing_amount IS NOT NULL THEN
        -- Если препарат уже есть, увеличиваем количество
        UPDATE public.druglist
        SET amount = amount + p_amount
        WHERE invoice_id = v_invoice_id AND drug_id = p_drug_id;

        RAISE NOTICE 'Количество препарата с ID % в накладной % увеличено на %', p_drug_id, v_invoice_id, p_amount;
    ELSE
        -- Если препарата нет, добавляем его
        INSERT INTO public.druglist (invoice_id, drug_id, amount)
        VALUES (v_invoice_id, p_drug_id, p_amount);

        RAISE NOTICE 'Препарат с ID % добавлен в накладную % в количестве %', p_drug_id, v_invoice_id, p_amount;
    END IF;

    RETURN v_invoice_id;
END;
$$;


ALTER FUNCTION public.add_drug_to_druglist(p_drug_id integer, p_amount integer, p_invoice_id integer) OWNER TO postgres;

--
-- Name: add_farmgroup_info(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_farmgroup_info(p_name character varying, p_description character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO public.farmgroup_info (name, description)
    VALUES (p_name, p_description);
END;
$$;


ALTER FUNCTION public.add_farmgroup_info(p_name character varying, p_description character varying) OWNER TO postgres;

--
-- Name: add_prescription(integer, date, character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_prescription(p_client_id integer, p_expiry_date date, p_drug_name character varying, p_drug_quantity integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Проверяем, что client_id соответствует текущему пользователю
    -- (этот механизм зависит от вашей системы аутентификации)
    -- В данном примере предполагаем, что client_id передается корректно.

    -- Вставляем новый рецепт
    INSERT INTO public.prescription (client_id, expiry_date, drug_name, drug_quantity)
    VALUES (p_client_id, p_expiry_date, p_drug_name, p_drug_quantity);

    -- Сообщение об успешном добавлении
    RAISE NOTICE 'Рецепт успешно добавлен для клиента с ID %', p_client_id;
END;
$$;


ALTER FUNCTION public.add_prescription(p_client_id integer, p_expiry_date date, p_drug_name character varying, p_drug_quantity integer) OWNER TO postgres;

--
-- Name: add_prescription(character varying, date, character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_prescription(p_login character varying, p_expiry_date date, p_drug_name character varying, p_drug_quantity integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    client_id integer;
BEGIN
    -- Ищем client_id по login в таблице client
    SELECT client.client_id INTO client_id
    FROM client
    WHERE client.login = p_login;

    -- Если client_id не найден, выбрасываем ошибку
    IF client_id IS NULL THEN
        RAISE EXCEPTION 'Ошибка: клиент с логином % не найден', p_login;
    END IF;

    -- Вставляем новый рецепт
    INSERT INTO public.prescription (client_id, expiry_date, drug_name, drug_quantity)
    VALUES (client_id, p_expiry_date, p_drug_name, p_drug_quantity);

    RAISE NOTICE 'Рецепт успешно добавлен для клиента %', client_id;
END;
$$;


ALTER FUNCTION public.add_prescription(p_login character varying, p_expiry_date date, p_drug_name character varying, p_drug_quantity integer) OWNER TO postgres;

--
-- Name: add_to_cart(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_to_cart(p_client_id integer, p_drug_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bill_id integer;
    v_price numeric;
    v_count integer;
BEGIN
    -- Проверяем, есть ли активный чек у клиента
    SELECT bill_id INTO v_bill_id
    FROM public.bill
    WHERE client_id = p_client_id AND status = false
    LIMIT 1;

    -- Если активный чек не найден, создаем новый
    IF v_bill_id IS NULL THEN
        INSERT INTO public.bill (client_id, date_time, amount)
        VALUES (p_client_id, CURRENT_TIMESTAMP, 0)
        RETURNING bill_id INTO v_bill_id;
    END IF;

    -- Проверяем, существует ли препарат и узнаем его цену
    SELECT price INTO v_price
    FROM public.drug
    WHERE drug_id = p_drug_id;

    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Препарат с ID % не найден', p_drug_id;
    END IF;

    -- Проверяем, есть ли уже этот препарат в корзине
    SELECT COUNT(*) INTO v_count
    FROM public.shoppingcart
    WHERE bill_id = v_bill_id AND drug_id = p_drug_id;

    IF v_count = 0 THEN
        -- Добавляем препарат в корзину
        INSERT INTO public.shoppingcart (bill_id, drug_id)
        VALUES (v_bill_id, p_drug_id);

        RAISE NOTICE 'Препарат с ID % добавлен в корзину клиента с ID %', p_drug_id, p_client_id;
    ELSE
        RAISE NOTICE 'Препарат с ID % уже есть в корзине клиента с ID %', p_drug_id, p_client_id;
    END IF;
END;
$$;


ALTER FUNCTION public.add_to_cart(p_client_id integer, p_drug_id integer) OWNER TO postgres;

--
-- Name: add_to_cart(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_to_cart(p_client_id integer, p_drug_id integer, p_quantity integer DEFAULT 1) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bill_id integer;
    v_price numeric;
    v_count integer;
BEGIN
    -- Проверяем, есть ли активный чек у клиента
    SELECT bill_id INTO v_bill_id
    FROM public.bill
    WHERE client_id = p_client_id AND status = false
    LIMIT 1;

    -- Если активный чек не найден, создаем новый
    IF v_bill_id IS NULL THEN
        INSERT INTO public.bill (client_id, date_time, amount)
        VALUES (p_client_id, CURRENT_TIMESTAMP, 0)
        RETURNING bill_id INTO v_bill_id;
    END IF;

    -- Проверяем, существует ли препарат
    SELECT price INTO v_price
    FROM public.drug
    WHERE drug_id = p_drug_id;

    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Препарат с ID % не найден', p_drug_id;
    END IF;

    -- Проверяем, есть ли уже этот препарат в корзине
    SELECT COUNT(*) INTO v_count
    FROM public.shoppingcart
    WHERE bill_id = v_bill_id AND drug_id = p_drug_id;

    IF v_count = 0 THEN
        -- Добавляем препарат в корзину (триггер сам обновит сумму)
        INSERT INTO public.shoppingcart (bill_id, drug_id, quantity)
        VALUES (v_bill_id, p_drug_id, p_quantity);
    ELSE
        -- Увеличиваем количество (триггер сам обновит сумму)
        UPDATE public.shoppingcart
        SET quantity = quantity + p_quantity
        WHERE bill_id = v_bill_id AND drug_id = p_drug_id;
    END IF;

    RAISE NOTICE 'Препарат с ID % добавлен/обновлен в корзине', p_drug_id;
END;
$$;


ALTER FUNCTION public.add_to_cart(p_client_id integer, p_drug_id integer, p_quantity integer) OWNER TO postgres;

--
-- Name: approve_bill(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.approve_bill(p_bill_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_client_id integer;
    v_client_phone text;
    v_drug_record RECORD;
    v_drug_amount integer;
BEGIN
    -- Получаем ID клиента по ID чека
    SELECT client_id INTO v_client_id
    FROM public.bill
    WHERE bill_id = p_bill_id;
    
    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Чек с ID % не найден', p_bill_id;
    END IF;

    -- Проверяем наличие номера телефона у клиента
    SELECT ci.phone_number INTO v_client_phone
    FROM public.client c
    JOIN public.client_info ci ON c.login = ci.login
    WHERE c.client_id = v_client_id;

    IF v_client_phone IS NULL OR v_client_phone = '' THEN
        RAISE EXCEPTION 'Подтверждение невозможно: у клиента не указан номер телефона';
    END IF;

    -- Проверяем количество препаратов в корзине и доступное количество
    FOR v_drug_record IN 
        SELECT sc.drug_id, sc.quantity, d.amount as drug_amount
        FROM public.shoppingcart sc
        JOIN public.drug d ON sc.drug_id = d.drug_id
        WHERE sc.bill_id = p_bill_id
    LOOP
        IF v_drug_record.drug_amount = 0 THEN
            RAISE EXCEPTION 'Подтверждение невозможно: препарат с ID % отсутствует на складе', v_drug_record.drug_id;
        END IF;
        
        IF v_drug_record.quantity > v_drug_record.drug_amount THEN
            RAISE EXCEPTION 'Подтверждение невозможно: запрошенное количество препарата с ID % превышает доступное', v_drug_record.drug_id;
        END IF;
    END LOOP;

    -- Обновляем количество препаратов в таблице drug
    UPDATE public.drug d
    SET amount = d.amount - sc.quantity
    FROM public.shoppingcart sc
    WHERE d.drug_id = sc.drug_id AND sc.bill_id = p_bill_id;

    -- Меняем статус чека на true (подтвержден)
    UPDATE public.bill
    SET status = true
    WHERE bill_id = p_bill_id;

    RAISE NOTICE 'Чек с ID % подтвержден модератором', p_bill_id;
END;
$$;


ALTER FUNCTION public.approve_bill(p_bill_id integer) OWNER TO postgres;

--
-- Name: authenticate_client(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.authenticate_client(p_login character varying, p_password character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    stored_hash TEXT;
BEGIN
    -- Получаем хеш пароля из базы данных
    SELECT password INTO stored_hash
    FROM public.client_info
    WHERE login = p_login;

    -- Если пользователь не найден, возвращаем FALSE
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Сравниваем хеш введенного пароля с хранимым хешем
    RETURN stored_hash = crypt(p_password, stored_hash);
END;
$$;


ALTER FUNCTION public.authenticate_client(p_login character varying, p_password character varying) OWNER TO postgres;

--
-- Name: authenticate_employee(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.authenticate_employee(p_login character varying, p_password character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    stored_hash TEXT;
BEGIN
    SELECT password INTO stored_hash
    FROM public.employee_info
    WHERE login = p_login;
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    RETURN stored_hash = crypt(p_password, stored_hash);
END;
$$;


ALTER FUNCTION public.authenticate_employee(p_login character varying, p_password character varying) OWNER TO postgres;

--
-- Name: check_drug_exists(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_drug_exists() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Проверяем, существует ли препарат
    IF NOT EXISTS (SELECT 1 FROM public.drug WHERE drug_id = NEW.drug_id) THEN
        RAISE EXCEPTION 'Препарат с ID % не существует', NEW.drug_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_drug_exists() OWNER TO postgres;

--
-- Name: confirm_invoice(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.confirm_invoice(p_invoice_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_drug_id integer;
    v_amount integer;
BEGIN
    -- Проверяем, существует ли накладная с таким ID
    IF NOT EXISTS (SELECT 1 FROM public.invoice WHERE invoice_id = p_invoice_id) THEN
        RAISE EXCEPTION 'Накладная с ID % не существует', p_invoice_id;
    END IF;

    -- Проверяем, был ли уже подтверждён статус накладной
    IF EXISTS (SELECT 1 FROM public.invoice WHERE invoice_id = p_invoice_id AND status = true) THEN
        RAISE EXCEPTION 'Накладная с ID % уже подтверждена', p_invoice_id;
    END IF;

    -- Обновляем статус накладной на "подтверждена" (status = true)
    UPDATE public.invoice
    SET status = true
    WHERE invoice_id = p_invoice_id;

    -- Для каждого препарата в druglist увеличиваем количество в drug
    FOR v_drug_id, v_amount IN
        SELECT drug_id, amount
        FROM public.druglist
        WHERE invoice_id = p_invoice_id
    LOOP
        -- Обновляем количество препарата в таблице drug
        UPDATE public.drug
        SET amount = amount + v_amount
        WHERE drug_id = v_drug_id;
    END LOOP;

    RAISE NOTICE 'Накладная с ID % успешно подтверждена и препараты обновлены', p_invoice_id;
END;
$$;


ALTER FUNCTION public.confirm_invoice(p_invoice_id integer) OWNER TO postgres;

--
-- Name: confirm_px_status(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.confirm_px_status(px_id integer, client_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.prescription
    SET status = true
    WHERE public.prescription.px_id = confirm_px_status.px_id
      AND public.prescription.client_id = confirm_px_status.client_id
      AND public.prescription.status = false;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Рецепт с px_id = % и client_id = % не найден или уже имеет статус true.', px_id, client_id;
    END IF;
END;
$$;


ALTER FUNCTION public.confirm_px_status(px_id integer, client_id integer) OWNER TO postgres;

--
-- Name: delete_activesub_info(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_activesub_info(p_name character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.activesub_info
    WHERE name = p_name;
END;
$$;


ALTER FUNCTION public.delete_activesub_info(p_name character varying) OWNER TO postgres;

--
-- Name: delete_client_info(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_client_info() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.client WHERE login = OLD.login;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_client_info() OWNER TO postgres;

--
-- Name: delete_client_prescriptions(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_client_prescriptions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Удаляем все рецепты для клиента, который был удален
    DELETE FROM public.prescription WHERE client_id = OLD.client_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_client_prescriptions() OWNER TO postgres;

--
-- Name: delete_druglist_on_drug_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_druglist_on_drug_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.druglist WHERE drug_id = OLD.drug_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_druglist_on_drug_delete() OWNER TO postgres;

--
-- Name: delete_druglist_on_invoice_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_druglist_on_invoice_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.druglist WHERE invoice_id = OLD.invoice_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_druglist_on_invoice_delete() OWNER TO postgres;

--
-- Name: delete_expired_prescription(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_expired_prescription() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Если срок действия истек, удаляем запись
    IF NEW.expiry_date < CURRENT_DATE THEN
        DELETE FROM public.prescription WHERE id = NEW.id;
        RETURN NULL;  -- Возвращаем NULL, чтобы указать, что запись была удалена
    END IF;
    RETURN NEW;  -- Возвращаем новую запись, если срок действия не истек
END;
$$;


ALTER FUNCTION public.delete_expired_prescription() OWNER TO postgres;

--
-- Name: delete_farmgroup_info(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_farmgroup_info(p_name character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.farmgroup_info
    WHERE name = p_name;
END;
$$;


ALTER FUNCTION public.delete_farmgroup_info(p_name character varying) OWNER TO postgres;

--
-- Name: delete_from_activesublist_activesub(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_from_activesublist_activesub() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.activesublist
    WHERE activesub_id = OLD.activesub_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_from_activesublist_activesub() OWNER TO postgres;

--
-- Name: delete_from_activesublist_drug(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_from_activesublist_drug() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.activesublist
    WHERE drug_id = OLD.drug_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_from_activesublist_drug() OWNER TO postgres;

--
-- Name: delete_from_farmgrouplist_drug(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_from_farmgrouplist_drug() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.farmgrouplist
    WHERE drug_id = OLD.drug_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_from_farmgrouplist_drug() OWNER TO postgres;

--
-- Name: delete_from_farmgrouplist_farmgroup(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_from_farmgrouplist_farmgroup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.farmgrouplist
    WHERE farmgroup_id = OLD.farmgroup_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_from_farmgrouplist_farmgroup() OWNER TO postgres;

--
-- Name: delete_prescription(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_prescription(p_px_id integer, p_client_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Удаляем рецепт только если он принадлежит клиенту
    DELETE FROM public.prescription
    WHERE px_id = p_px_id AND client_id = p_client_id;

    -- Проверяем, был ли удален рецепт
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Рецепт с ID % не найден или не принадлежит клиенту с ID %', p_px_id, p_client_id;
    ELSE
        RAISE NOTICE 'Рецепт с ID % успешно удален', p_px_id;
    END IF;
END;
$$;


ALTER FUNCTION public.delete_prescription(p_px_id integer, p_client_id integer) OWNER TO postgres;

--
-- Name: get_all_activesub_info(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_all_activesub_info() RETURNS TABLE(name character varying, active boolean, description character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.activesub_info;
END;
$$;


ALTER FUNCTION public.get_all_activesub_info() OWNER TO postgres;

--
-- Name: get_all_farmgroup_info(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_all_farmgroup_info() RETURNS TABLE(name character varying, description character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.farmgroup_info;
END;
$$;


ALTER FUNCTION public.get_all_farmgroup_info() OWNER TO postgres;

--
-- Name: get_all_unv_bills(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_all_unv_bills() RETURNS TABLE(bill_id integer, client_id integer, date_time timestamp without time zone, status boolean, amount integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.bill_id,
        b.client_id,
        b.date_time,
        b.status,
        b.amount
    FROM
        public.bill b
    WHERE
        b.status = false; -- Возвращаем все чеки со статусом false
END;
$$;


ALTER FUNCTION public.get_all_unv_bills() OWNER TO postgres;

--
-- Name: get_all_unv_px(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_all_unv_px() RETURNS TABLE(px_id integer, client_id integer, status boolean, expiry_date date, drug_name character varying, drug_quantity integer, client_info text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.px_id,
        p.client_id,
        p.status,
        p.expiry_date,
        p.drug_name,
        p.drug_quantity,
        CONCAT(
            ci.surname, ' ', 
            ci.name, 
            CASE WHEN ci.patronymic IS NOT NULL THEN ' ' || ci.patronymic ELSE '' END,
            ', ', 
            TO_CHAR(ci.birth_date, 'DD.MM.YYYY')
        ) AS client_info
    FROM
        public.prescription p
    JOIN
        public.client c ON p.client_id = c.client_id
    JOIN
        public.client_info ci ON c.login = ci.login
    WHERE
        p.status = false;
END;
$$;


ALTER FUNCTION public.get_all_unv_px() OWNER TO postgres;

--
-- Name: get_drugs_by_farmgroup_id(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_drugs_by_farmgroup_id(farmgroup_id integer) RETURNS TABLE(drug_id integer, drug_name character varying, description character varying, pi character varying, expiry_date date, prescription boolean, price integer, farmgroup_name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.drug_id,
        d.name AS drug_name,
        d.description,
        d.pi,
        d.expiry_date,
        d.prescription,
        d.price,
        fg.name AS farmgroup_name
    FROM 
        farmgrouplist fgl
    JOIN 
        drug d ON fgl.drug_id = d.drug_id
    JOIN 
        farmgroup fg ON fgl.farmgroup_id = fg.farmgroup_id
    WHERE 
        fgl.farmgroup_id = get_drugs_by_farmgroup_id.farmgroup_id;  -- Указываем явно, что используем параметр функции
END;
$$;


ALTER FUNCTION public.get_drugs_by_farmgroup_id(farmgroup_id integer) OWNER TO postgres;

--
-- Name: get_prescription_drugs_by_bill(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_prescription_drugs_by_bill(p_bill_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_drug_names text;
BEGIN
    SELECT coalesce(string_agg(d.name::text, ', '), '')
    INTO v_drug_names
    FROM public.shoppingcart sc
    JOIN public.drug d ON sc.drug_id = d.drug_id
    WHERE sc.bill_id = p_bill_id AND d.prescription = true;
    RETURN v_drug_names;
END;
$$;


ALTER FUNCTION public.get_prescription_drugs_by_bill(p_bill_id integer) OWNER TO postgres;

--
-- Name: get_prescriptions_by_client(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_prescriptions_by_client(p_client_id integer) RETURNS TABLE(px_id integer, client_id integer, status boolean, expiry_date date, drug_name character varying, drug_quantity integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.px_id,
        p.client_id,
        p.status,
        p.expiry_date,
        p.drug_name,
        p.drug_quantity
    FROM
        public.prescription p
    WHERE
        p.client_id = p_client_id;
END;
$$;


ALTER FUNCTION public.get_prescriptions_by_client(p_client_id integer) OWNER TO postgres;

--
-- Name: insert_into_activesub(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_into_activesub() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO public.activesub (name)
    VALUES (NEW.name);
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.insert_into_activesub() OWNER TO postgres;

--
-- Name: insert_into_farmgroup(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_into_farmgroup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO public.farmgroup (name)
    VALUES (NEW.name);
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.insert_into_farmgroup() OWNER TO postgres;

--
-- Name: log_trigger_function(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_trigger_function() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO public.log (table_name, operation_type, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb);
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO public.log (table_name, operation_type, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO public.log (table_name, operation_type, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW)::jsonb);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.log_trigger_function() OWNER TO postgres;

--
-- Name: pay_bill(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pay_bill(p_bill_id integer, p_client_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_has_prescription_drug boolean;
    v_client_phone text;
    v_drug_record RECORD;
    v_drug_amount integer;
BEGIN
    -- Проверяем, что чек принадлежит клиенту
    IF NOT EXISTS (SELECT 1 FROM public.bill WHERE bill_id = p_bill_id AND client_id = p_client_id) THEN
        RAISE EXCEPTION 'Чек с ID % не принадлежит клиенту с ID %', p_bill_id, p_client_id;
    END IF;

    -- Проверяем наличие номера телефона у клиента
    SELECT ci.phone_number INTO v_client_phone
    FROM public.client c
    JOIN public.client_info ci ON c.login = ci.login
    WHERE c.client_id = p_client_id;

    IF v_client_phone IS NULL OR v_client_phone = '' THEN
        RAISE EXCEPTION 'Оплата невозможна: у клиента не указан номер телефона';
    END IF;

    -- Проверяем, есть ли в корзине рецептурные препараты
    SELECT EXISTS (
        SELECT 1
        FROM public.shoppingcart sc
        JOIN public.drug d ON sc.drug_id = d.drug_id
        WHERE sc.bill_id = p_bill_id AND d.prescription = true
    ) INTO v_has_prescription_drug;

    -- Если есть рецептурные препараты, оплата запрещена
    IF v_has_prescription_drug THEN
        RAISE EXCEPTION 'Оплата невозможна: в корзине есть рецептурные препараты';
    END IF;

    -- Проверяем количество препаратов в корзине и доступное количество
    FOR v_drug_record IN 
        SELECT sc.drug_id, sc.quantity, d.amount as drug_amount
        FROM public.shoppingcart sc
        JOIN public.drug d ON sc.drug_id = d.drug_id
        WHERE sc.bill_id = p_bill_id
    LOOP
        IF v_drug_record.drug_amount = 0 THEN
            RAISE EXCEPTION 'Оплата невозможна: препарат с ID % отсутствует на складе', v_drug_record.drug_id;
        END IF;
        
        IF v_drug_record.quantity > v_drug_record.drug_amount THEN
            RAISE EXCEPTION 'Оплата невозможна: запрошенное количество препарата с ID % превышает доступное', v_drug_record.drug_id;
        END IF;
    END LOOP;

    -- Обновляем количество препаратов в таблице drug
    UPDATE public.drug d
    SET amount = d.amount - sc.quantity
    FROM public.shoppingcart sc
    WHERE d.drug_id = sc.drug_id AND sc.bill_id = p_bill_id;

    -- Меняем статус чека на true (оплачен)
    UPDATE public.bill
    SET status = true
    WHERE bill_id = p_bill_id;

    RAISE NOTICE 'Чек с ID % успешно оплачен', p_bill_id;
END;
$$;


ALTER FUNCTION public.pay_bill(p_bill_id integer, p_client_id integer) OWNER TO postgres;

--
-- Name: register_client(character varying, character varying, character varying, character varying, date, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.register_client(p_login character varying, p_name character varying, p_surname character varying, p_password character varying, p_birth_date date, p_patronymic character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    hashed_password TEXT;
BEGIN
    -- Проверяем, существует ли уже пользователь с таким логином
    IF EXISTS (SELECT 1 FROM public.client_info WHERE login = p_login) THEN
        RAISE EXCEPTION 'Пользователь с логином "%" уже существует', p_login;
    END IF;

    -- Хешируем пароль
    hashed_password := crypt(p_password, gen_salt('bf'));

    -- Вставляем данные в таблицу client_info
    INSERT INTO public.client_info (login, name, surname, patronymic, password, birth_date)
    VALUES (p_login, p_name, p_surname, p_patronymic, hashed_password, p_birth_date);

    -- Вставляем данные в таблицу client
    INSERT INTO public.client (client_id, login)
    VALUES (nextval('client_client_id_seq'), p_login);
END;
$$;


ALTER FUNCTION public.register_client(p_login character varying, p_name character varying, p_surname character varying, p_password character varying, p_birth_date date, p_patronymic character varying) OWNER TO postgres;

--
-- Name: register_employee(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.register_employee(p_login character varying, p_password character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    hashed_password TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM public.employee_info WHERE login = p_login) THEN
        RAISE EXCEPTION 'Сотрудник с логином "%" уже существует', p_login;
    END IF;

    hashed_password := crypt(p_password, gen_salt('bf'));

    INSERT INTO public.employee_info (login, password)
    VALUES (p_login, hashed_password);

    INSERT INTO public.employee (login)
    VALUES (p_login);
END;
$$;


ALTER FUNCTION public.register_employee(p_login character varying, p_password character varying) OWNER TO postgres;

--
-- Name: remove_drug_from_druglist(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.remove_drug_from_druglist(p_drug_id integer, p_invoice_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_existing_amount integer;
    v_invoice_status boolean;
BEGIN
    -- Проверяем, существует ли накладная с таким ID
    IF NOT EXISTS (SELECT 1 FROM public.invoice WHERE invoice_id = p_invoice_id) THEN
        RAISE EXCEPTION 'Накладная с ID % не существует', p_invoice_id;
    END IF;

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status FROM public.invoice WHERE invoice_id = p_invoice_id;

    IF v_invoice_status THEN
        RAISE EXCEPTION 'Накладная с ID % уже закрыта, препарат не может быть удален', p_invoice_id;
    END IF;

    -- Проверяем, есть ли такой препарат в накладной
    SELECT amount INTO v_existing_amount
    FROM public.druglist
    WHERE invoice_id = p_invoice_id AND drug_id = p_drug_id;

    IF v_existing_amount IS NULL THEN
        RAISE EXCEPTION 'Препарат с ID % не найден в накладной с ID %', p_drug_id, p_invoice_id;
    END IF;

    -- Удаляем препарат из накладной
    DELETE FROM public.druglist
    WHERE invoice_id = p_invoice_id AND drug_id = p_drug_id;

    RAISE NOTICE 'Препарат с ID % удален из накладной с ID %', p_drug_id, p_invoice_id;
END;
$$;


ALTER FUNCTION public.remove_drug_from_druglist(p_drug_id integer, p_invoice_id integer) OWNER TO postgres;

--
-- Name: remove_from_cart(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.remove_from_cart(p_client_id integer, p_drug_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bill_id integer;
    v_count integer;
BEGIN
    -- Проверяем активный чек
    SELECT bill_id INTO v_bill_id
    FROM public.bill
    WHERE client_id = p_client_id AND status = false
    LIMIT 1;

    IF v_bill_id IS NULL THEN
        RAISE EXCEPTION 'Активный чек для клиента с ID % не найден', p_client_id;
    END IF;

    -- Проверяем наличие препарата в корзине
    SELECT COUNT(*) INTO v_count
    FROM public.shoppingcart
    WHERE bill_id = v_bill_id AND drug_id = p_drug_id;

    IF v_count > 0 THEN
        -- Удаляем препарат (триггер сам обновит сумму)
        DELETE FROM public.shoppingcart
        WHERE bill_id = v_bill_id AND drug_id = p_drug_id;
        
        RAISE NOTICE 'Препарат с ID % удален из корзины клиента с ID %', p_drug_id, p_client_id;
    ELSE
        RAISE NOTICE 'Препарат с ID % не найден в корзине клиента с ID %', p_drug_id, p_client_id;
    END IF;
END;
$$;


ALTER FUNCTION public.remove_from_cart(p_client_id integer, p_drug_id integer) OWNER TO postgres;

--
-- Name: update_activesub_info(character varying, boolean, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_activesub_info(p_name character varying, p_new_active boolean, p_new_description character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.activesub_info
    SET active = p_new_active,
        description = p_new_description
    WHERE name = p_name;
END;
$$;


ALTER FUNCTION public.update_activesub_info(p_name character varying, p_new_active boolean, p_new_description character varying) OWNER TO postgres;

--
-- Name: update_bill_amount(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_bill_amount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_price numeric;
BEGIN
    -- Для операций INSERT/UPDATE берем NEW, для DELETE - OLD
    SELECT price INTO v_price 
    FROM public.drug 
    WHERE drug_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.drug_id ELSE NEW.drug_id END;

    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Препарат не найден';
    END IF;

    IF TG_OP = 'INSERT' THEN
        UPDATE public.bill
        SET amount = amount + (v_price * NEW.quantity)
        WHERE bill_id = NEW.bill_id;
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE public.bill
        SET amount = amount + (v_price * (NEW.quantity - OLD.quantity))
        WHERE bill_id = NEW.bill_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.bill
        SET amount = GREATEST(amount - (v_price * OLD.quantity), 0)
        WHERE bill_id = OLD.bill_id;
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_bill_amount() OWNER TO postgres;

--
-- Name: update_cart_item(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_cart_item(p_client_id integer, p_drug_id integer, p_quantity integer) RETURNS TABLE(new_quantity integer, item_total numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bill_id integer;
    v_price numeric;
    v_current_quantity integer;  
BEGIN
    -- Находим активный чек
    SELECT bill_id INTO v_bill_id FROM bill
    WHERE client_id = p_client_id AND status = false LIMIT 1;
   
    IF v_bill_id IS NULL THEN
        RAISE EXCEPTION 'Активный чек не найден';
    END IF;

    -- Проверяем наличие препарата в корзине
    SELECT quantity INTO v_current_quantity
    FROM public.shoppingcart
    WHERE bill_id = v_bill_id AND drug_id = p_drug_id;
    
    IF v_current_quantity IS NULL THEN
        RAISE EXCEPTION 'Препарат с ID % не найден в корзине', p_drug_id;
    END IF;

    -- Получаем цену препарата
    SELECT price INTO v_price FROM drug WHERE drug_id = p_drug_id;
    
    -- Обновляем количество и возвращаем результат
    RETURN QUERY
    UPDATE shoppingcart 
    SET quantity = p_quantity
    WHERE bill_id = v_bill_id AND drug_id = p_drug_id
    RETURNING quantity, quantity * v_price;
END;
$$;


ALTER FUNCTION public.update_cart_item(p_client_id integer, p_drug_id integer, p_quantity integer) OWNER TO postgres;

--
-- Name: update_client_field(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_client_field(p_login character varying, p_field_name character varying, p_new_value character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF p_field_name = 'name' THEN
        UPDATE public.client_info SET name = p_new_value WHERE login = p_login;
    ELSIF p_field_name = 'surname' THEN
        UPDATE public.client_info SET surname = p_new_value WHERE login = p_login;
    ELSIF p_field_name = 'patronymic' THEN
        UPDATE public.client_info SET patronymic = p_new_value WHERE login = p_login;
    ELSIF p_field_name = 'password' THEN
        UPDATE public.client_info SET password = p_new_value WHERE login = p_login;
    ELSIF p_field_name = 'birth_date' THEN
        UPDATE public.client_info SET birth_date = p_new_value WHERE login = p_login;
    ELSE
        RAISE EXCEPTION 'Неизвестное поле: %', p_field_name;
    END IF;
END;
$$;


ALTER FUNCTION public.update_client_field(p_login character varying, p_field_name character varying, p_new_value character varying) OWNER TO postgres;

--
-- Name: update_drug(integer, character varying, character varying, date, boolean, integer, character varying, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_drug(IN p_drug_id integer, IN p_description character varying, IN p_pi character varying, IN p_expiry_date date, IN p_prescription boolean, IN p_price integer, IN p_name character varying, IN p_amount integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Обновляем запись
    UPDATE public.drug
    SET
        description = p_description,
        pi = p_pi,
        expiry_date = p_expiry_date,
        prescription = p_prescription,
        price = p_price,
        name = p_name,
        amount = p_amount
    WHERE drug_id = p_drug_id;
END;
$$;


ALTER PROCEDURE public.update_drug(IN p_drug_id integer, IN p_description character varying, IN p_pi character varying, IN p_expiry_date date, IN p_prescription boolean, IN p_price integer, IN p_name character varying, IN p_amount integer) OWNER TO postgres;

--
-- Name: update_druglist_on_drug_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_druglist_on_drug_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.druglist
    SET drug_id = NEW.drug_id
    WHERE drug_id = OLD.drug_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_druglist_on_drug_update() OWNER TO postgres;

--
-- Name: update_druglist_on_invoice_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_druglist_on_invoice_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.druglist
    SET invoice_id = NEW.invoice_id
    WHERE invoice_id = OLD.invoice_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_druglist_on_invoice_update() OWNER TO postgres;

--
-- Name: update_farmgroup_info(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_farmgroup_info(p_name character varying, p_new_description character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.farmgroup_info
    SET description = p_new_description
    WHERE name = p_name;
END;
$$;


ALTER FUNCTION public.update_farmgroup_info(p_name character varying, p_new_description character varying) OWNER TO postgres;

--
-- Name: update_password(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_password() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Хешируем новый пароль перед обновлением
    NEW.password := crypt(NEW.password, gen_salt('bf'));
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_password() OWNER TO postgres;

--
-- Name: view_mybills(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.view_mybills(p_client_id integer) RETURNS TABLE(v_bill_id integer, date_time timestamp without time zone, v_status_text text, amount integer, v_drug_names text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.bill_id AS v_bill_id,
        b.date_time,
        CASE 
            WHEN b.status = true THEN 'Оплачен'
            WHEN b.status = false THEN 'Не оплачен'
            ELSE 'Неизвестно' 
        END AS v_status_text,
        b.amount,
        COALESCE(
            string_agg(
                CASE 
                    WHEN sc.quantity > 1 THEN d.name || ' (' || sc.quantity || ')'
                    ELSE d.name
                END, 
                ', '
            ), 
            ''
        ) AS v_drug_names
    FROM 
        public.bill b
    LEFT JOIN 
        public.shoppingcart sc ON b.bill_id = sc.bill_id
    LEFT JOIN 
        public.drug d ON sc.drug_id = d.drug_id
    WHERE 
        b.client_id = p_client_id
    GROUP BY 
        b.bill_id, b.date_time, b.status, b.amount;
END;
$$;


ALTER FUNCTION public.view_mybills(p_client_id integer) OWNER TO postgres;

--
-- Name: view_shopcart(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.view_shopcart(p_client_id integer) RETURNS TABLE(bill_id integer, date_time timestamp without time zone, status text, bill_amount integer, drug_id integer, drug_name character varying, drug_price integer, prescription_status text, quantity integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bill_id integer;
    v_status boolean;
    v_status_text text;
    v_bill_amount integer;
BEGIN
    -- получаю активный чек для клиента
    SELECT b.bill_id, b.date_time, b.status, b.amount
    INTO v_bill_id, date_time, v_status, v_bill_amount
    FROM public.bill b
    WHERE b.client_id = p_client_id AND b.status = false
    LIMIT 1;

    v_status_text := CASE
        WHEN v_status = true THEN 'Оплачен'
        WHEN v_status = false THEN 'Не оплачен'
        ELSE 'Неизвестно'
    END;

    -- данные о чеке и препаратах
    RETURN QUERY
    SELECT
        v_bill_id, 
        date_time,
        v_status_text,
        v_bill_amount,
        d.drug_id,
        d.name, 
        d.price,
        CASE
            WHEN d.prescription = true THEN 'Рецептурный'
            ELSE 'Безрецептурный'
        END AS prescription_status,
        sc.quantity
    FROM public.shoppingcart sc
    JOIN public.drug d ON sc.drug_id = d.drug_id
    WHERE sc.bill_id = v_bill_id; 
END;
$$;


ALTER FUNCTION public.view_shopcart(p_client_id integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accessrights; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.accessrights (
    accessrights_id integer NOT NULL,
    description character varying(50) NOT NULL
);


ALTER TABLE public.accessrights OWNER TO postgres;

--
-- Name: accessrights_accessrights_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.accessrights_accessrights_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accessrights_accessrights_id_seq OWNER TO postgres;

--
-- Name: accessrights_accessrights_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.accessrights_accessrights_id_seq OWNED BY public.accessrights.accessrights_id;


--
-- Name: activesub; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activesub (
    activesub_id integer NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE public.activesub OWNER TO postgres;

--
-- Name: activesub_activesub_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.activesub_activesub_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.activesub_activesub_id_seq OWNER TO postgres;

--
-- Name: activesub_activesub_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.activesub_activesub_id_seq OWNED BY public.activesub.activesub_id;


--
-- Name: activesub_info; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activesub_info (
    name character varying(50) NOT NULL,
    active boolean DEFAULT false,
    description character varying(200) NOT NULL
);


ALTER TABLE public.activesub_info OWNER TO postgres;

--
-- Name: activesublist; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activesublist (
    drug_id integer NOT NULL,
    activesub_id integer NOT NULL,
    quantity integer NOT NULL
);


ALTER TABLE public.activesublist OWNER TO postgres;

--
-- Name: activesublist_activesub_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.activesublist_activesub_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.activesublist_activesub_id_seq OWNER TO postgres;

--
-- Name: activesublist_activesub_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.activesublist_activesub_id_seq OWNED BY public.activesublist.activesub_id;


--
-- Name: activesublist_drug_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.activesublist_drug_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.activesublist_drug_id_seq OWNER TO postgres;

--
-- Name: activesublist_drug_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.activesublist_drug_id_seq OWNED BY public.activesublist.drug_id;


--
-- Name: bill; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bill (
    bill_id integer NOT NULL,
    client_id integer NOT NULL,
    date_time timestamp without time zone NOT NULL,
    status boolean DEFAULT false,
    amount integer NOT NULL
);


ALTER TABLE public.bill OWNER TO postgres;

--
-- Name: bill_bill_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bill_bill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bill_bill_id_seq OWNER TO postgres;

--
-- Name: bill_bill_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bill_bill_id_seq OWNED BY public.bill.bill_id;


--
-- Name: bill_client_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bill_client_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bill_client_id_seq OWNER TO postgres;

--
-- Name: bill_client_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bill_client_id_seq OWNED BY public.bill.client_id;


--
-- Name: client; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client (
    client_id integer NOT NULL,
    login character varying(45) NOT NULL
);


ALTER TABLE public.client OWNER TO postgres;

--
-- Name: client_client_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.client_client_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.client_client_id_seq OWNER TO postgres;

--
-- Name: client_info; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_info (
    login character varying(45) NOT NULL,
    name character varying(45) NOT NULL,
    surname character varying(45) NOT NULL,
    patronymic character varying(45) DEFAULT NULL::character varying,
    password character varying(100) NOT NULL,
    birth_date date NOT NULL,
    phone_number character varying(20)
);


ALTER TABLE public.client_info OWNER TO postgres;

--
-- Name: drug; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.drug (
    drug_id integer NOT NULL,
    description character varying(150) NOT NULL,
    pi character varying(200) NOT NULL,
    expiry_date date NOT NULL,
    prescription boolean DEFAULT false,
    price integer NOT NULL,
    name character varying(50) NOT NULL,
    amount integer DEFAULT 0
);


ALTER TABLE public.drug OWNER TO postgres;

--
-- Name: drug_drug_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.drug_drug_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.drug_drug_id_seq OWNER TO postgres;

--
-- Name: drug_drug_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.drug_drug_id_seq OWNED BY public.drug.drug_id;


--
-- Name: druglist; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.druglist (
    invoice_id integer NOT NULL,
    drug_id integer NOT NULL,
    amount integer NOT NULL
);


ALTER TABLE public.druglist OWNER TO postgres;

--
-- Name: employee; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employee (
    employee_id integer NOT NULL,
    login character varying(25) NOT NULL
);


ALTER TABLE public.employee OWNER TO postgres;

--
-- Name: employee_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employee_employee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_employee_id_seq OWNER TO postgres;

--
-- Name: employee_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employee_employee_id_seq OWNED BY public.employee.employee_id;


--
-- Name: employee_info; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employee_info (
    login character varying(25) NOT NULL,
    password character varying(100) NOT NULL
);


ALTER TABLE public.employee_info OWNER TO postgres;

--
-- Name: employeerights; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employeerights (
    employee_id integer NOT NULL,
    accessrights_id integer NOT NULL
);


ALTER TABLE public.employeerights OWNER TO postgres;

--
-- Name: employeerights_accessrights_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employeerights_accessrights_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employeerights_accessrights_id_seq OWNER TO postgres;

--
-- Name: employeerights_accessrights_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employeerights_accessrights_id_seq OWNED BY public.employeerights.accessrights_id;


--
-- Name: employeerights_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employeerights_employee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employeerights_employee_id_seq OWNER TO postgres;

--
-- Name: employeerights_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employeerights_employee_id_seq OWNED BY public.employeerights.employee_id;


--
-- Name: farmgroup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.farmgroup (
    farmgroup_id integer NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE public.farmgroup OWNER TO postgres;

--
-- Name: farmgroup_farmgroup_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.farmgroup_farmgroup_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.farmgroup_farmgroup_id_seq OWNER TO postgres;

--
-- Name: farmgroup_farmgroup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.farmgroup_farmgroup_id_seq OWNED BY public.farmgroup.farmgroup_id;


--
-- Name: farmgroup_info; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.farmgroup_info (
    name character varying(50) NOT NULL,
    description character varying(200) NOT NULL
);


ALTER TABLE public.farmgroup_info OWNER TO postgres;

--
-- Name: farmgrouplist; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.farmgrouplist (
    drug_id integer NOT NULL,
    farmgroup_id integer NOT NULL
);


ALTER TABLE public.farmgrouplist OWNER TO postgres;

--
-- Name: farmgrouplist_drug_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.farmgrouplist_drug_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.farmgrouplist_drug_id_seq OWNER TO postgres;

--
-- Name: farmgrouplist_drug_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.farmgrouplist_drug_id_seq OWNED BY public.farmgrouplist.drug_id;


--
-- Name: farmgrouplist_farmgroup_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.farmgrouplist_farmgroup_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.farmgrouplist_farmgroup_id_seq OWNER TO postgres;

--
-- Name: farmgrouplist_farmgroup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.farmgrouplist_farmgroup_id_seq OWNED BY public.farmgrouplist.farmgroup_id;


--
-- Name: invoice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.invoice (
    invoice_id integer NOT NULL,
    status boolean DEFAULT false
);


ALTER TABLE public.invoice OWNER TO postgres;

--
-- Name: invoice_invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.invoice_invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoice_invoice_id_seq OWNER TO postgres;

--
-- Name: invoice_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.invoice_invoice_id_seq OWNED BY public.invoice.invoice_id;


--
-- Name: log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.log (
    log_id integer NOT NULL,
    operation_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    table_name text NOT NULL,
    operation_type text NOT NULL,
    old_data jsonb,
    new_data jsonb
);


ALTER TABLE public.log OWNER TO postgres;

--
-- Name: log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.log_log_id_seq OWNER TO postgres;

--
-- Name: log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.log_log_id_seq OWNED BY public.log.log_id;


--
-- Name: prescription; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.prescription (
    px_id integer NOT NULL,
    client_id integer NOT NULL,
    status boolean DEFAULT false,
    expiry_date date NOT NULL,
    drug_name character varying(100) NOT NULL,
    drug_quantity integer
);


ALTER TABLE public.prescription OWNER TO postgres;

--
-- Name: prescription_client_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.prescription_client_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.prescription_client_id_seq OWNER TO postgres;

--
-- Name: prescription_client_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.prescription_client_id_seq OWNED BY public.prescription.client_id;


--
-- Name: prescription_px_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.prescription_px_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.prescription_px_id_seq OWNER TO postgres;

--
-- Name: prescription_px_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.prescription_px_id_seq OWNED BY public.prescription.px_id;


--
-- Name: shoppingcart; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.shoppingcart (
    bill_id integer NOT NULL,
    drug_id integer NOT NULL,
    quantity integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.shoppingcart OWNER TO postgres;

--
-- Name: shoppingcart_bill_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.shoppingcart_bill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.shoppingcart_bill_id_seq OWNER TO postgres;

--
-- Name: shoppingcart_bill_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.shoppingcart_bill_id_seq OWNED BY public.shoppingcart.bill_id;


--
-- Name: shoppingcart_drug_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.shoppingcart_drug_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.shoppingcart_drug_id_seq OWNER TO postgres;

--
-- Name: shoppingcart_drug_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.shoppingcart_drug_id_seq OWNED BY public.shoppingcart.drug_id;


--
-- Name: accessrights accessrights_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accessrights ALTER COLUMN accessrights_id SET DEFAULT nextval('public.accessrights_accessrights_id_seq'::regclass);


--
-- Name: activesub activesub_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesub ALTER COLUMN activesub_id SET DEFAULT nextval('public.activesub_activesub_id_seq'::regclass);


--
-- Name: activesublist drug_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesublist ALTER COLUMN drug_id SET DEFAULT nextval('public.activesublist_drug_id_seq'::regclass);


--
-- Name: activesublist activesub_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesublist ALTER COLUMN activesub_id SET DEFAULT nextval('public.activesublist_activesub_id_seq'::regclass);


--
-- Name: bill bill_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bill ALTER COLUMN bill_id SET DEFAULT nextval('public.bill_bill_id_seq'::regclass);


--
-- Name: bill client_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bill ALTER COLUMN client_id SET DEFAULT nextval('public.bill_client_id_seq'::regclass);


--
-- Name: drug drug_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.drug ALTER COLUMN drug_id SET DEFAULT nextval('public.drug_drug_id_seq'::regclass);


--
-- Name: employee employee_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee ALTER COLUMN employee_id SET DEFAULT nextval('public.employee_employee_id_seq'::regclass);


--
-- Name: employeerights employee_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employeerights ALTER COLUMN employee_id SET DEFAULT nextval('public.employeerights_employee_id_seq'::regclass);


--
-- Name: employeerights accessrights_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employeerights ALTER COLUMN accessrights_id SET DEFAULT nextval('public.employeerights_accessrights_id_seq'::regclass);


--
-- Name: farmgroup farmgroup_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgroup ALTER COLUMN farmgroup_id SET DEFAULT nextval('public.farmgroup_farmgroup_id_seq'::regclass);


--
-- Name: farmgrouplist drug_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgrouplist ALTER COLUMN drug_id SET DEFAULT nextval('public.farmgrouplist_drug_id_seq'::regclass);


--
-- Name: farmgrouplist farmgroup_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgrouplist ALTER COLUMN farmgroup_id SET DEFAULT nextval('public.farmgrouplist_farmgroup_id_seq'::regclass);


--
-- Name: invoice invoice_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice ALTER COLUMN invoice_id SET DEFAULT nextval('public.invoice_invoice_id_seq'::regclass);


--
-- Name: log log_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log ALTER COLUMN log_id SET DEFAULT nextval('public.log_log_id_seq'::regclass);


--
-- Name: prescription px_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription ALTER COLUMN px_id SET DEFAULT nextval('public.prescription_px_id_seq'::regclass);


--
-- Name: prescription client_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription ALTER COLUMN client_id SET DEFAULT nextval('public.prescription_client_id_seq'::regclass);


--
-- Name: shoppingcart bill_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shoppingcart ALTER COLUMN bill_id SET DEFAULT nextval('public.shoppingcart_bill_id_seq'::regclass);


--
-- Name: shoppingcart drug_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shoppingcart ALTER COLUMN drug_id SET DEFAULT nextval('public.shoppingcart_drug_id_seq'::regclass);


--
-- Data for Name: accessrights; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.accessrights (accessrights_id, description) FROM stdin;
3	unvpx_b
4	unvbills_b
5	activesubs_b
6	farmgroups_b
7	drugs_b
\.


--
-- Data for Name: activesub; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.activesub (activesub_id, name) FROM stdin;
1	Парацетамол
2	Кофеин
3	Ибупрофен
4	Лактоза
5	Аскорбиновая кислота (витамин C)
6	Этанол
7	Глицерин
8	Димедрол
9	Кальция карбонат
10	Вода
11	Мелатонин
12	Ацетилсалициловая кислота (Аспирин)
13	Левотироксин
14	Сальбутамол
15	Флуоксетин
16	Метформин
17	Лоперамид
18	Декстрометорфан
19	Сорбитол
20	Тальк
21	Сахароза
22	Крахмал
23	Парафин
24	Желатин
25	Магния стеарат
26	Целлюлоза микрокристаллическая
27	Пропиленгликоль
28	Диоксид кремния
29	Глюкоза
30	Пищевые красители
31	Ароматизаторы
32	Лецитин
33	Парабены
\.


--
-- Data for Name: activesub_info; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.activesub_info (name, active, description) FROM stdin;
Парацетамол	t	Стимулятор центральной нервной системы, повышает бодрость, концентрацию и снижает усталость. Содержится в кофе, чае, энергетических напитках и некоторых лекарствах.
Кофеин	t	Стимулятор центральной нервной системы, повышает бодрость, концентрацию и снижает усталость. Содержится в кофе, чае, энергетических напитках и некоторых лекарствах.
Ибупрофен	t	Нестероидное противовоспалительное средство (НПВС), применяется для уменьшения боли, воспаления и температуры.
Лактоза	f	Углевод, содержащийся в молочных продуктах. Часто используется как наполнитель в лекарственных препаратах.
Аскорбиновая кислота (витамин C)	t	Антиоксидант, необходим для нормального функционирования иммунной системы, кожи и соединительной ткани.
Этанол	t	Спирт, используемый в медицине как антисептик, растворитель или консервант. Также обладает седативным эффектом.
Глицерин	f	Используется как увлажнитель, растворитель или стабилизатор в лекарственных и косметических средствах.
Димедрол	t	Антигистаминное средство, применяется для лечения аллергических реакций, а также как седативное и противорвотное средство.
Кальция карбонат	t	Антацид, используется для нейтрализации кислоты в желудке, а также как источник кальция.
Мелатонин	t	Гормон, регулирующий циклы сна и бодрствования. Используется для борьбы с бессонницей и джетлагом.
Ацетилсалициловая кислота (Аспирин)	t	Нестероидное противовоспалительное средство, обладающее анальгезирующим, жаропонижающим и антиагрегантным эффектом.
Левотироксин	t	Препарат для заместительной терапии при гипотиреозе, содержит синтетический аналог гормонов щитовидной железы.
Сальбутамол	t	Бронхолитик, применяемый при астме и хронической обструктивной болезни лёгких (ХОБЛ) для облегчения дыхания.
Флуоксетин	t	Антидепрессант из группы селективных ингибиторов обратного захвата серотонина (СИОЗС), применяется при депрессии и тревожных расстройствах.
Метформин	t	Препарат для лечения диабета 2 типа, помогает снизить уровень сахара в крови и повысить чувствительность к инсулину.
Лоперамид	t	Противодиарейное средство, замедляет перистальтику кишечника и уменьшает частоту стула.
Декстрометорфан	t	Противокашлевое средство, используемое при сухом кашле, действует на кашлевой центр в головном мозге.
Сорбитол	f	Сахарный спирт, используемый как подсластитель и наполнитель в лекарственных препаратах.
Тальк	f	Вспомогательный компонент в таблетках, используется как смазывающее вещество.
Сахароза	f	Подсластитель, применяется в сиропах, таблетках и других лекарственных формах.
Крахмал	f	Наполнитель в таблетках, используется для придания формы и стабильности лекарственным препаратам.
Парафин	f	Используется в мазях и свечах как основа и связующее вещество.
Желатин	f	Используется в капсулах и таблетках как загуститель и желирующее вещество.
Магния стеарат	f	Антифрикционный агент, применяется в производстве таблеток для предотвращения их прилипания к пресс-формам.
Целлюлоза микрокристаллическая	f	Наполнитель в таблетках, используется для придания структуры и стабильности.
Пропиленгликоль	f	Растворитель, увлажнитель и стабилизатор, используется в жидких лекарственных формах.
Диоксид кремния	f	Антислеживающий агент, применяется в порошковых и таблетированных препаратах.
Глюкоза	f	Источник энергии, используется в растворах для внутривенного введения и в составе таблеток.
Пищевые красители	f	Используются в оболочках таблеток и капсул для придания цвета.
Ароматизаторы	f	Добавляются в сиропы, жевательные таблетки и другие лекарственные формы для улучшения вкуса.
Лецитин	f	Эмульгатор, применяется в мягких капсулах и жидких формах лекарств.
Вода	f	Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления веществ.
Парабены	f	Консерванты, используемые в кремах, мазях и жидких лекарственных препаратах для предотвращения роста микробов.
\.


--
-- Data for Name: activesublist; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.activesublist (drug_id, activesub_id, quantity) FROM stdin;
2	2	150
2	5	50
3	1	200
3	3	100
4	8	100
4	12	50
5	9	150
5	14	80
6	6	250
6	29	120
7	5	300
1	3	1
8	12	1
\.


--
-- Data for Name: bill; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bill (bill_id, client_id, date_time, status, amount) FROM stdin;
19	5	2025-03-24 19:43:05.390737	t	250
22	5	2025-03-25 23:22:55.938965	t	250
23	5	2025-03-25 23:48:47.759621	t	150
12	5	2025-03-23 12:02:06.602483	t	470
13	5	2025-03-23 12:07:28.107727	t	600
14	5	2025-03-23 14:00:06.198539	t	150
15	5	2025-03-23 16:55:55.554246	t	120
24	5	2025-03-25 23:57:37.174254	t	440
16	5	2025-03-23 20:23:01.234357	t	720
18	4	2025-03-23 21:58:45.528716	t	350
25	5	2025-03-26 00:28:17.823792	t	730
17	5	2025-03-23 20:41:37.84196	t	740
26	5	2025-03-26 16:22:15.372189	f	1000
28	7	2025-03-29 18:31:13.134931	t	220
29	7	2025-03-29 18:32:33.379392	f	550
27	4	2025-03-26 19:06:07.550806	f	1400
\.


--
-- Data for Name: client; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client (client_id, login) FROM stdin;
1	johndoe
2	jane01
3	jane012
4	newuser
5	jack
6	lada
7	jojo33
\.


--
-- Data for Name: client_info; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.client_info (login, name, surname, patronymic, password, birth_date, phone_number) FROM stdin;
johndoe	John	Doe	\N	password123	1990-05-14	\N
jane01	Jane	Doe	\N	password123	1994-05-19	\N
jane012	Jane	Doe	\N	password123	1994-05-19	\N
newuser	User	Used	\N	$2a$06$FthRT7gMCYl7AH1Vqq5EqOf0a0gepOSOtiMryTKeCnoB1qUAqFSNu	1990-05-29	\N
lada	Лада	Комаровская		$2a$06$oV7uN9YPpHqY/gNauiF4R.t7HS1Ecj2aW6yWsbO36lzuw7nL9RkZi	1968-08-26	\N
jojo33	Jordan	Joseph		$2a$06$05KvX235Cn0IB7bZgZF22eKGeNxh4w08292u9b4v7lMQr0fuY91R6	2002-06-29	\N
jack	Джек	Уайт		$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.	1995-02-13	798319103
\.


--
-- Data for Name: drug; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.drug (drug_id, description, pi, expiry_date, prescription, price, name, amount) FROM stdin;
3	Жаропонижающее и обезболивающее средство.	Применяется при простуде и гриппе для снижения температуры.	2025-12-10	t	250	Парацетамол	142
4	Антигистаминное средство с седативным эффектом.	Используется для лечения аллергии и бессонницы. Может вызывать сонливость.	2026-04-05	t	400	Димедрол	151
5	Антацид, снижает кислотность желудочного сока.	Применяется при изжоге и гастрите. Не превышать рекомендуемую дозу.	2028-02-14	f	180	Кальция карбонат	147
6	Антисептик и растворитель, обладает дезинфицирующими свойствами.	Используется для обработки ран и в медицинских растворах.	2030-06-30	f	120	Этанол	56
1	Обезболивающее средство, уменьшает воспаление.	Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.	2026-05-15	t	350	Ибупрофен	64
8	Противоаллергическое средство	Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице	2026-12-31	f	250	Цетрин	100
7	Антиоксидант, поддерживает иммунитет и здоровье кожи.	Рекомендуется для профилактики простудных заболеваний.	2027-11-25	f	220	Аскорбиновая кислота (витамин C)	105
2	Стимулирует центральную нервную систему, повышает бодрость.	Используется для снятия усталости и повышения концентрации. Не рекомендуется перед сном.	2027-08-20	f	150	Кофеин	93
\.


--
-- Data for Name: druglist; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.druglist (invoice_id, drug_id, amount) FROM stdin;
1	2	4
3	2	3
1	8	1
1	3	5
\.


--
-- Data for Name: employee; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employee (employee_id, login) FROM stdin;
1	moderator
2	siteAdmin
4	mod
\.


--
-- Data for Name: employee_info; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employee_info (login, password) FROM stdin;
siteAdmin	$2a$06$NexmkNw92JyiSwzwgSQFiunwxuUG832/jEYv9RlWf5DEM7FzmkAE2
moderator	$2a$06$1Q8VFftniNRYHwcwWbfgv.1HWuKAz7KuL/tZj86vwk62FlGVLlQB.
test	$2a$06$ScIQK0RiCMpWH8WvN1kbGOdYd8cBwQ/TIDp3sqHDozeVXnG5Ze5X.
mod	$2a$06$5W4EEGrSZUz/rSu/IXWshuFsJySECDyJB2MWtiX8k/V4/xNvD2Iva
\.


--
-- Data for Name: employeerights; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employeerights (employee_id, accessrights_id) FROM stdin;
4	3
1	3
1	4
1	5
1	6
1	7
\.


--
-- Data for Name: farmgroup; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.farmgroup (farmgroup_id, name) FROM stdin;
1	Антибиотики
3	Жаропонижающие
4	Обезболивающие
5	Противовирусные
6	Противогрибковые
7	Антигистаминные
8	Седативные
9	Ноотропы
10	Антисептики
11	Спазмолитики
12	Бронхолитики
13	Гипотензивные
14	Диуретики
15	Противокашлевые
16	Отхаркивающие
17	Гепатопротекторы
18	Противоязвенные
19	Антикоагулянты
20	Иммуностимуляторы
\.


--
-- Data for Name: farmgroup_info; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.farmgroup_info (name, description) FROM stdin;
Жаропонижающие	Препараты, снижающие повышенную температуру тела.
Обезболивающие	Анальгетики, используемые для уменьшения боли различного происхождения.
Противовирусные	Лекарства, направленные на борьбу с вирусными инфекциями.
Противогрибковые	Препараты для лечения грибковых инфекций.
Антигистаминные	Средства, блокирующие действие гистамина и уменьшающие аллергические реакции.
Седативные	Препараты, обладающие успокаивающим действием, применяемые при тревожности и бессоннице.
Ноотропы	Препараты, улучшающие когнитивные функции, память и концентрацию.
Антисептики	Средства, уничтожающие или подавляющие рост микроорганизмов на коже и слизистых оболочках.
Спазмолитики	Препараты, снимающие спазмы гладкой мускулатуры.
Бронхолитики	Средства, расширяющие бронхи и облегчающие дыхание при заболеваниях легких.
Гипотензивные	Препараты для снижения артериального давления.
Диуретики	Мочегонные средства, применяемые при отеках и гипертонии.
Противокашлевые	Средства, подавляющие кашель.
Отхаркивающие	Препараты, способствующие разжижению и выведению мокроты.
Гепатопротекторы	Средства, защищающие и восстанавливающие печень.
Противоязвенные	Препараты для лечения язвы желудка и гастрита.
Антикоагулянты	Средства, разжижающие кровь и предотвращающие тромбообразование.
Иммуностимуляторы	Препараты, повышающие активность иммунной системы.
Антибиотики	Группа лекарств, используемых для лечения бактериальных инфекций.
\.


--
-- Data for Name: farmgrouplist; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.farmgrouplist (drug_id, farmgroup_id) FROM stdin;
2	9
2	5
3	3
3	4
4	7
4	5
5	18
5	13
6	10
6	8
7	20
7	5
1	4
1	5
8	7
8	8
\.


--
-- Data for Name: invoice; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.invoice (invoice_id, status) FROM stdin;
1	f
3	t
\.


--
-- Data for Name: log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.log (log_id, operation_time, table_name, operation_type, old_data, new_data) FROM stdin;
1	2025-03-16 21:53:05.754758	drug	INSERT	\N	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}
2	2025-03-18 16:24:50.562814	employee_info	INSERT	\N	{"login": "moderator", "password": "$2a$06$3xAbwmGR18pdHRaiE6ThFON.ZCLsJQKGcuQfl.XvcfZ8JccIp61ha"}
3	2025-03-18 16:24:50.562814	employee	INSERT	\N	{"login": "moderator", "employee_id": 1}
4	2025-03-18 23:10:13.09906	client_info	INSERT	\N	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}
5	2025-03-18 23:10:13.09906	client	INSERT	\N	{"login": "jack", "client_id": 5}
6	2025-03-18 23:22:59.556374	client_info	INSERT	\N	{"name": "Лада", "login": "lada", "surname": "Комаровская", "password": "$2a$06$oV7uN9YPpHqY/gNauiF4R.t7HS1Ecj2aW6yWsbO36lzuw7nL9RkZi", "birth_date": "1968-08-26", "patronymic": ""}
7	2025-03-18 23:22:59.556374	client	INSERT	\N	{"login": "lada", "client_id": 6}
8	2025-03-19 00:28:46.002393	prescription	INSERT	\N	{"px_id": 2, "status": false, "client_id": 5, "drug_name": "Мефедрон", "expiry_date": "2025-05-29", "drug_quantity": 5}
9	2025-03-19 00:54:20.534539	prescription	DELETE	{"px_id": 2, "status": false, "client_id": 5, "drug_name": "Мефедрон", "expiry_date": "2025-05-29", "drug_quantity": 5}	\N
10	2025-03-19 01:01:11.588774	prescription	INSERT	\N	{"px_id": 3, "status": false, "client_id": 5, "drug_name": "амоксиклав", "expiry_date": "2025-09-25", "drug_quantity": 2}
11	2025-03-19 01:20:56.865029	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}
32	2025-03-23 11:32:48.094851	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
33	2025-03-23 11:32:48.094851	shoppingcart	INSERT	\N	{"bill_id": 11, "drug_id": 1}
34	2025-03-23 11:32:48.094851	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 350, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
35	2025-03-23 11:32:48.094851	bill	UPDATE	{"amount": 350, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 700, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
36	2025-03-23 11:36:32.500444	shoppingcart	INSERT	\N	{"bill_id": 11, "drug_id": 2}
37	2025-03-23 11:36:32.500444	bill	UPDATE	{"amount": 700, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 850, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
38	2025-03-23 11:36:32.500444	bill	UPDATE	{"amount": 850, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 1000, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
39	2025-03-23 11:52:13.076993	shoppingcart	INSERT	\N	{"bill_id": 11, "drug_id": 7}
40	2025-03-23 11:52:13.076993	bill	UPDATE	{"amount": 1000, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 1220, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
41	2025-03-23 11:57:10.218622	shoppingcart	DELETE	{"bill_id": 11, "drug_id": 1}	\N
42	2025-03-23 11:57:10.218622	bill	UPDATE	{"amount": 1220, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 870, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
43	2025-03-23 11:58:15.541751	shoppingcart	DELETE	{"bill_id": 11, "drug_id": 2}	\N
44	2025-03-23 11:58:15.541751	bill	UPDATE	{"amount": 870, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 720, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
45	2025-03-23 11:58:18.879951	shoppingcart	DELETE	{"bill_id": 11, "drug_id": 7}	\N
46	2025-03-23 11:58:18.879951	bill	UPDATE	{"amount": 720, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	{"amount": 500, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}
47	2025-03-23 12:00:23.678816	bill	DELETE	{"amount": 500, "status": false, "bill_id": 11, "client_id": 5, "date_time": "2025-03-23T11:32:48.094851"}	\N
48	2025-03-23 12:02:06.602483	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}
49	2025-03-23 12:02:06.602483	shoppingcart	INSERT	\N	{"bill_id": 12, "drug_id": 7}
50	2025-03-23 12:02:06.602483	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}	{"amount": 220, "status": false, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}
51	2025-03-23 12:03:26.997132	shoppingcart	INSERT	\N	{"bill_id": 12, "drug_id": 8}
52	2025-03-23 12:03:26.997132	bill	UPDATE	{"amount": 220, "status": false, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}	{"amount": 470, "status": false, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}
53	2025-03-23 12:04:40.428282	bill	UPDATE	{"amount": 470, "status": false, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}	{"amount": 470, "status": true, "bill_id": 12, "client_id": 5, "date_time": "2025-03-23T12:02:06.602483"}
54	2025-03-23 12:07:28.107727	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}
55	2025-03-23 12:07:28.107727	shoppingcart	INSERT	\N	{"bill_id": 13, "drug_id": 8}
56	2025-03-23 12:07:28.107727	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}	{"amount": 250, "status": false, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}
57	2025-03-23 12:08:29.456569	shoppingcart	INSERT	\N	{"bill_id": 13, "drug_id": 1}
58	2025-03-23 12:08:29.456569	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}	{"amount": 600, "status": false, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}
59	2025-03-23 12:10:26.154255	bill	UPDATE	{"amount": 600, "status": false, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}	{"amount": 600, "status": true, "bill_id": 13, "client_id": 5, "date_time": "2025-03-23T12:07:28.107727"}
60	2025-03-23 14:00:06.198539	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
61	2025-03-23 14:00:06.198539	shoppingcart	INSERT	\N	{"bill_id": 14, "drug_id": 1}
62	2025-03-23 14:00:06.198539	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}	{"amount": 350, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
63	2025-03-23 14:08:50.833762	shoppingcart	INSERT	\N	{"bill_id": 14, "drug_id": 4}
64	2025-03-23 14:08:50.833762	bill	UPDATE	{"amount": 350, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}	{"amount": 750, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
65	2025-03-23 14:16:32.178749	shoppingcart	INSERT	\N	{"bill_id": 14, "drug_id": 2}
66	2025-03-23 14:16:32.178749	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}	{"amount": 900, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
67	2025-03-23 16:36:03.957122	shoppingcart	DELETE	{"bill_id": 14, "drug_id": 1}	\N
68	2025-03-23 16:36:03.957122	bill	UPDATE	{"amount": 900, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}	{"amount": 550, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
69	2025-03-23 16:36:08.072435	shoppingcart	DELETE	{"bill_id": 14, "drug_id": 4}	\N
70	2025-03-23 16:36:08.072435	bill	UPDATE	{"amount": 550, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}	{"amount": 150, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
71	2025-03-23 16:37:13.771609	bill	UPDATE	{"amount": 150, "status": false, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}	{"amount": 150, "status": true, "bill_id": 14, "client_id": 5, "date_time": "2025-03-23T14:00:06.198539"}
72	2025-03-23 16:55:55.554246	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 15, "client_id": 5, "date_time": "2025-03-23T16:55:55.554246"}
73	2025-03-23 16:55:55.554246	shoppingcart	INSERT	\N	{"bill_id": 15, "drug_id": 6}
74	2025-03-23 16:55:55.554246	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 15, "client_id": 5, "date_time": "2025-03-23T16:55:55.554246"}	{"amount": 120, "status": false, "bill_id": 15, "client_id": 5, "date_time": "2025-03-23T16:55:55.554246"}
75	2025-03-23 16:56:06.558085	bill	UPDATE	{"amount": 120, "status": false, "bill_id": 15, "client_id": 5, "date_time": "2025-03-23T16:55:55.554246"}	{"amount": 120, "status": true, "bill_id": 15, "client_id": 5, "date_time": "2025-03-23T16:55:55.554246"}
76	2025-03-23 17:08:07.062498	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}
77	2025-03-23 17:08:07.062498	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}
78	2025-03-23 17:08:07.062498	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-10", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-13", "patronymic": ""}
79	2025-03-23 17:09:00.653135	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-13", "patronymic": ""}
268	2025-03-25 23:22:30.928032	bill	DELETE	{"amount": 800, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}	\N
80	2025-03-23 17:09:00.653135	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-13", "patronymic": ""}
81	2025-03-23 17:09:00.653135	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$KERFcb56t42ghqgSrsi7dOEsXN6Z6EpumfGZwlxJnx7qP/d6cSeN.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
220	2025-03-24 17:32:00.351468	accessrights	INSERT	\N	{"description": "drugs_b", "accessrights_id": 7}
82	2025-03-23 17:09:00.653135	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
92	2025-03-23 18:35:37.55283	client_info	UPDATE	{"name": "Jackson", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
93	2025-03-23 18:35:37.55283	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
94	2025-03-23 18:35:37.55283	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
95	2025-03-23 20:23:01.234357	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}
96	2025-03-23 20:23:01.234357	shoppingcart	INSERT	\N	{"bill_id": 16, "drug_id": 8}
97	2025-03-23 20:23:01.234357	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}	{"amount": 250, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}
98	2025-03-23 20:23:23.039301	shoppingcart	INSERT	\N	{"bill_id": 16, "drug_id": 6}
99	2025-03-23 20:23:23.039301	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}	{"amount": 370, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}
100	2025-03-23 20:39:56.588986	shoppingcart	INSERT	\N	{"bill_id": 16, "drug_id": 1}
101	2025-03-23 20:39:56.588986	bill	UPDATE	{"amount": 370, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}	{"amount": 720, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}
102	2025-03-23 20:41:09.592297	bill	UPDATE	{"amount": 720, "status": false, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}	{"amount": 720, "status": true, "bill_id": 16, "client_id": 5, "date_time": "2025-03-23T20:23:01.234357"}
103	2025-03-23 20:41:37.84196	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
104	2025-03-23 20:41:37.84196	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 3}
105	2025-03-23 20:41:37.84196	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 250, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
106	2025-03-23 20:41:46.909216	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 1}
107	2025-03-23 20:41:46.909216	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 600, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
108	2025-03-23 20:41:53.724568	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 2}
109	2025-03-23 20:41:53.724568	bill	UPDATE	{"amount": 600, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 750, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
110	2025-03-23 20:41:55.950011	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 4}
111	2025-03-23 20:41:55.950011	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 1150, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
112	2025-03-23 20:56:25.411687	prescription	UPDATE	{"px_id": 3, "status": false, "client_id": 5, "drug_name": "амоксиклав", "expiry_date": "2025-09-25", "drug_quantity": 2}	{"px_id": 3, "status": true, "client_id": 5, "drug_name": "амоксиклав", "expiry_date": "2025-09-25", "drug_quantity": 2}
113	2025-03-23 21:58:45.528716	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 18, "client_id": 4, "date_time": "2025-03-23T21:58:45.528716"}
114	2025-03-23 21:58:45.528716	shoppingcart	INSERT	\N	{"bill_id": 18, "drug_id": 1}
115	2025-03-23 21:58:45.528716	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 18, "client_id": 4, "date_time": "2025-03-23T21:58:45.528716"}	{"amount": 350, "status": false, "bill_id": 18, "client_id": 4, "date_time": "2025-03-23T21:58:45.528716"}
116	2025-03-23 21:59:12.438091	prescription	INSERT	\N	{"px_id": 4, "status": false, "client_id": 4, "drug_name": "ибупрофен", "expiry_date": "2026-07-29", "drug_quantity": 1}
117	2025-03-23 21:59:41.025713	prescription	INSERT	\N	{"px_id": 5, "status": false, "client_id": 4, "drug_name": "парацетамол", "expiry_date": "2027-01-29", "drug_quantity": 1}
118	2025-03-23 23:32:15.093285	prescription	UPDATE	{"px_id": 1, "status": false, "client_id": 1, "drug_name": "парацетамол", "expiry_date": "2026-12-31", "drug_quantity": 5}	{"px_id": 1, "status": true, "client_id": 1, "drug_name": "парацетамол", "expiry_date": "2026-12-31", "drug_quantity": 5}
119	2025-03-23 23:32:18.497496	prescription	UPDATE	{"px_id": 4, "status": false, "client_id": 4, "drug_name": "ибупрофен", "expiry_date": "2026-07-29", "drug_quantity": 1}	{"px_id": 4, "status": true, "client_id": 4, "drug_name": "ибупрофен", "expiry_date": "2026-07-29", "drug_quantity": 1}
120	2025-03-23 23:32:19.84606	prescription	UPDATE	{"px_id": 5, "status": false, "client_id": 4, "drug_name": "парацетамол", "expiry_date": "2027-01-29", "drug_quantity": 1}	{"px_id": 5, "status": true, "client_id": 4, "drug_name": "парацетамол", "expiry_date": "2027-01-29", "drug_quantity": 1}
121	2025-03-24 00:17:12.517623	activesub_info	INSERT	\N	{"name": "Тест", "active": true, "description": "Desc"}
122	2025-03-24 00:17:12.517623	activesub	INSERT	\N	{"name": "Тест", "activesub_id": 37}
123	2025-03-24 00:31:24.966305	activesub_info	DELETE	{"name": "Тест", "active": true, "description": "Desc"}	\N
124	2025-03-24 00:31:24.966305	activesub	DELETE	{"name": "Тест", "activesub_id": 37}	\N
125	2025-03-24 00:40:56.919608	activesub_info	UPDATE	{"name": "Вода", "active": false, "description": "Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления активных веществ."}	{"name": "Вода", "active": true, "description": "Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления активных веществ."}
126	2025-03-24 00:41:11.050757	activesub_info	UPDATE	{"name": "Вода", "active": true, "description": "Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления активных веществ."}	{"name": "Вода", "active": false, "description": "Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления активных веществ."}
127	2025-03-24 00:49:21.817402	activesub_info	UPDATE	{"name": "Вода", "active": false, "description": "Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления активных веществ."}	{"name": "Вода", "active": false, "description": "Растворитель, используемый в большинстве лекарственных форм для растворения или разбавления веществ."}
128	2025-03-24 07:37:55.232681	farmgroup_info	UPDATE	{"name": "Антибиотики", "description": "Группа лекарств, используемых для лечения бактериальных инфекций."}	{"name": "Антибиотики", "description": "Группа лекарств, используемых для лечения бактериальных."}
269	2025-03-25 23:22:30.928032	shoppingcart	DELETE	{"bill_id": 20, "drug_id": 3, "quantity": 2}	\N
129	2025-03-24 07:38:13.791893	farmgroup_info	UPDATE	{"name": "Антибиотики", "description": "Группа лекарств, используемых для лечения бактериальных."}	{"name": "Антибиотики", "description": "Группа лекарств, используемых для лечения бактериальных инфекций."}
130	2025-03-24 07:38:57.97367	farmgroup_info	INSERT	\N	{"name": "Тест", "description": "группы"}
131	2025-03-24 07:38:57.97367	farmgroup	INSERT	\N	{"name": "Тест", "farmgroup_id": 21}
132	2025-03-24 07:39:01.127876	farmgroup_info	DELETE	{"name": "Тест", "description": "группы"}	\N
133	2025-03-24 07:39:01.127876	farmgroup	DELETE	{"name": "Тест", "farmgroup_id": 21}	\N
134	2025-03-24 08:23:50.630616	drug	INSERT	\N	{"pi": "инс", "name": "тест", "price": 5, "amount": 1, "drug_id": 9, "description": "препарата", "expiry_date": "2025-05-05", "prescription": false}
135	2025-03-24 08:26:51.513427	drug	UPDATE	{"pi": "инс", "name": "тест", "price": 5, "amount": 1, "drug_id": 9, "description": "препарата", "expiry_date": "2025-05-05", "prescription": false}	{"pi": "инс", "name": "тест", "price": 5, "amount": 10, "drug_id": 9, "description": "препарата", "expiry_date": "2025-05-05", "prescription": false}
136	2025-03-24 08:26:56.056037	drug	DELETE	{"pi": "инс", "name": "тест", "price": 5, "amount": 10, "drug_id": 9, "description": "препарата", "expiry_date": "2025-05-05", "prescription": false}	\N
137	2025-03-24 08:56:37.330619	drug	UPDATE	{"pi": "Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.", "name": "Ибупрофен", "price": 350, "amount": 64, "drug_id": 1, "description": "Обезболивающее средство, уменьшает воспаление.", "expiry_date": "2026-05-15", "prescription": true}	{"pi": "Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.", "name": "Ибупрофен", "price": 350, "amount": 64, "drug_id": 1, "description": "Обезболивающее средство, уменьшает воспаление.", "expiry_date": "2026-05-15", "prescription": true}
138	2025-03-24 08:56:37.330619	farmgrouplist	DELETE	{"drug_id": 1, "farmgroup_id": 4}	\N
139	2025-03-24 08:56:37.330619	farmgrouplist	DELETE	{"drug_id": 1, "farmgroup_id": 5}	\N
140	2025-03-24 08:56:37.330619	farmgrouplist	INSERT	\N	{"drug_id": 1, "farmgroup_id": 4}
141	2025-03-24 08:56:37.330619	farmgrouplist	INSERT	\N	{"drug_id": 1, "farmgroup_id": 5}
142	2025-03-24 08:56:37.330619	activesublist	DELETE	{"drug_id": 1, "quantity": 200, "activesub_id": 3}	\N
143	2025-03-24 08:56:37.330619	activesublist	DELETE	{"drug_id": 1, "quantity": 100, "activesub_id": 1}	\N
144	2025-03-24 08:56:37.330619	activesublist	INSERT	\N	{"drug_id": 1, "quantity": 1, "activesub_id": 3}
145	2025-03-24 09:04:58.634481	drug	UPDATE	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}
146	2025-03-24 09:04:58.634481	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 7}
147	2025-03-24 09:04:58.634481	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 8}
148	2025-03-24 09:05:56.471765	drug	UPDATE	{"pi": "Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.", "name": "Ибупрофен", "price": 350, "amount": 64, "drug_id": 1, "description": "Обезболивающее средство, уменьшает воспаление.", "expiry_date": "2026-05-15", "prescription": true}	{"pi": "Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.", "name": "Ибупрофен", "price": 350, "amount": 64, "drug_id": 1, "description": "Обезболивающее средство, уменьшает воспаление.", "expiry_date": "2026-05-15", "prescription": true}
149	2025-03-24 09:05:56.471765	farmgrouplist	DELETE	{"drug_id": 1, "farmgroup_id": 4}	\N
150	2025-03-24 09:05:56.471765	farmgrouplist	DELETE	{"drug_id": 1, "farmgroup_id": 5}	\N
151	2025-03-24 09:05:56.471765	farmgrouplist	INSERT	\N	{"drug_id": 1, "farmgroup_id": 4}
152	2025-03-24 09:05:56.471765	farmgrouplist	INSERT	\N	{"drug_id": 1, "farmgroup_id": 5}
153	2025-03-24 09:05:56.471765	activesublist	DELETE	{"drug_id": 1, "quantity": 1, "activesub_id": 3}	\N
154	2025-03-24 09:06:07.614688	drug	UPDATE	{"pi": "Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.", "name": "Ибупрофен", "price": 350, "amount": 64, "drug_id": 1, "description": "Обезболивающее средство, уменьшает воспаление.", "expiry_date": "2026-05-15", "prescription": true}	{"pi": "Применяется при головной боли, мышечных болях и воспалениях. Не превышать дозировку.", "name": "Ибупрофен", "price": 350, "amount": 64, "drug_id": 1, "description": "Обезболивающее средство, уменьшает воспаление.", "expiry_date": "2026-05-15", "prescription": true}
155	2025-03-24 09:06:07.614688	farmgrouplist	DELETE	{"drug_id": 1, "farmgroup_id": 4}	\N
156	2025-03-24 09:06:07.614688	farmgrouplist	DELETE	{"drug_id": 1, "farmgroup_id": 5}	\N
157	2025-03-24 09:06:07.614688	farmgrouplist	INSERT	\N	{"drug_id": 1, "farmgroup_id": 4}
158	2025-03-24 09:06:07.614688	farmgrouplist	INSERT	\N	{"drug_id": 1, "farmgroup_id": 5}
159	2025-03-24 09:06:07.614688	activesublist	INSERT	\N	{"drug_id": 1, "quantity": 1, "activesub_id": 3}
270	2025-03-25 23:22:55.938965	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}
160	2025-03-24 09:06:44.030746	drug	UPDATE	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}
161	2025-03-24 09:06:44.030746	farmgrouplist	DELETE	{"drug_id": 8, "farmgroup_id": 7}	\N
162	2025-03-24 09:06:44.030746	farmgrouplist	DELETE	{"drug_id": 8, "farmgroup_id": 8}	\N
163	2025-03-24 09:06:44.030746	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 7}
164	2025-03-24 09:06:44.030746	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 8}
165	2025-03-24 09:06:44.030746	activesublist	INSERT	\N	{"drug_id": 8, "quantity": 1, "activesub_id": 12}
166	2025-03-24 09:07:02.453581	drug	UPDATE	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}
167	2025-03-24 09:07:02.453581	farmgrouplist	DELETE	{"drug_id": 8, "farmgroup_id": 7}	\N
168	2025-03-24 09:07:02.453581	farmgrouplist	DELETE	{"drug_id": 8, "farmgroup_id": 8}	\N
169	2025-03-24 09:07:02.453581	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 7}
170	2025-03-24 09:07:02.453581	activesublist	DELETE	{"drug_id": 8, "quantity": 1, "activesub_id": 12}	\N
171	2025-03-24 09:07:02.453581	activesublist	INSERT	\N	{"drug_id": 8, "quantity": 1, "activesub_id": 12}
172	2025-03-24 09:08:21.89048	drug	UPDATE	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}	{"pi": "Содержит цетиризина гидрохлорид, применяется при аллергическом рините и крапивнице", "name": "Цетрин", "price": 250, "amount": 100, "drug_id": 8, "description": "Противоаллергическое средство", "expiry_date": "2026-12-31", "prescription": false}
173	2025-03-24 09:08:21.89048	farmgrouplist	DELETE	{"drug_id": 8, "farmgroup_id": 7}	\N
174	2025-03-24 09:08:21.89048	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 7}
175	2025-03-24 09:08:21.89048	farmgrouplist	INSERT	\N	{"drug_id": 8, "farmgroup_id": 8}
176	2025-03-24 09:08:21.89048	activesublist	DELETE	{"drug_id": 8, "quantity": 1, "activesub_id": 12}	\N
177	2025-03-24 09:08:21.89048	activesublist	INSERT	\N	{"drug_id": 8, "quantity": 1, "activesub_id": 12}
178	2025-03-24 09:52:26.226286	bill	UPDATE	{"amount": 350, "status": false, "bill_id": 18, "client_id": 4, "date_time": "2025-03-23T21:58:45.528716"}	{"amount": 350, "status": true, "bill_id": 18, "client_id": 4, "date_time": "2025-03-23T21:58:45.528716"}
179	2025-03-24 09:57:22.711576	employee_info	INSERT	\N	{"login": "siteAdmin", "password": "$2a$06$NexmkNw92JyiSwzwgSQFiunwxuUG832/jEYv9RlWf5DEM7FzmkAE2"}
180	2025-03-24 09:57:22.711576	employee	INSERT	\N	{"login": "siteAdmin", "employee_id": 2}
181	2025-03-24 12:08:41.904365	employee_info	UPDATE	{"login": "moderator", "password": "$2a$06$3xAbwmGR18pdHRaiE6ThFON.ZCLsJQKGcuQfl.XvcfZ8JccIp61ha"}	{"login": "moderator", "password": "$2a$06$0lldMXaWo5cxw8XDHN50BuSuJrBw0vwY0zIxxiXtx3yinfeTiqfye"}
182	2025-03-24 12:10:06.864835	employee_info	UPDATE	{"login": "moderator", "password": "$2a$06$0lldMXaWo5cxw8XDHN50BuSuJrBw0vwY0zIxxiXtx3yinfeTiqfye"}	{"login": "moderator", "password": "$2a$06$1Q8VFftniNRYHwcwWbfgv.1HWuKAz7KuL/tZj86vwk62FlGVLlQB."}
183	2025-03-24 12:17:11.923233	employee_info	INSERT	\N	{"login": "test", "password": "$2a$06$ScIQK0RiCMpWH8WvN1kbGOdYd8cBwQ/TIDp3sqHDozeVXnG5Ze5X."}
184	2025-03-24 12:17:11.923233	employee	INSERT	\N	{"login": "test", "employee_id": 3}
185	2025-03-24 12:17:14.469288	employee	DELETE	{"login": "test", "employee_id": 3}	\N
186	2025-03-24 12:34:12.291312	accessrights	INSERT	\N	{"description": "право", "accessrights_id": 1}
187	2025-03-24 12:34:21.272881	accessrights	DELETE	{"description": "право", "accessrights_id": 1}	\N
188	2025-03-24 12:34:30.191574	accessrights	INSERT	\N	{"description": "право", "accessrights_id": 2}
189	2025-03-24 12:34:36.782974	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 2}
190	2025-03-24 13:31:11.947371	invoice	INSERT	\N	{"status": false, "invoice_id": 2}
191	2025-03-24 13:31:11.947371	druglist	INSERT	\N	{"amount": 5, "drug_id": 8, "invoice_id": 2}
192	2025-03-24 13:35:14.828205	druglist	UPDATE	{"amount": 5, "drug_id": 8, "invoice_id": 2}	{"amount": 10, "drug_id": 8, "invoice_id": 2}
193	2025-03-24 13:35:35.578811	druglist	INSERT	\N	{"amount": 5, "drug_id": 7, "invoice_id": 2}
194	2025-03-24 13:40:09.761576	druglist	DELETE	{"amount": 10, "drug_id": 8, "invoice_id": 2}	\N
195	2025-03-24 13:46:49.582548	druglist	UPDATE	{"amount": 5, "drug_id": 7, "invoice_id": 2}	{"amount": 5, "drug_id": 7, "invoice_id": 2}
196	2025-03-24 13:46:49.582548	invoice	UPDATE	{"status": false, "invoice_id": 2}	{"status": true, "invoice_id": 2}
197	2025-03-24 13:46:49.582548	druglist	UPDATE	{"amount": 5, "drug_id": 7, "invoice_id": 2}	{"amount": 5, "drug_id": 7, "invoice_id": 2}
271	2025-03-25 23:22:55.938965	shoppingcart	INSERT	\N	{"bill_id": 22, "drug_id": 4, "quantity": 1}
198	2025-03-24 13:46:49.582548	drug	UPDATE	{"pi": "Рекомендуется для профилактики простудных заболеваний.", "name": "Аскорбиновая кислота (витамин C)", "price": 220, "amount": 100, "drug_id": 7, "description": "Антиоксидант, поддерживает иммунитет и здоровье кожи.", "expiry_date": "2027-11-25", "prescription": false}	{"pi": "Рекомендуется для профилактики простудных заболеваний.", "name": "Аскорбиновая кислота (витамин C)", "price": 220, "amount": 105, "drug_id": 7, "description": "Антиоксидант, поддерживает иммунитет и здоровье кожи.", "expiry_date": "2027-11-25", "prescription": false}
199	2025-03-24 16:11:55.535176	druglist	INSERT	\N	{"amount": 4, "drug_id": 2, "invoice_id": 1}
200	2025-03-24 16:12:10.889467	druglist	DELETE	{"amount": 5, "drug_id": 7, "invoice_id": 2}	\N
201	2025-03-24 16:20:33.451169	invoice	INSERT	\N	{"status": false, "invoice_id": 3}
202	2025-03-24 16:21:22.770995	druglist	INSERT	\N	{"amount": 3, "drug_id": 2, "invoice_id": 3}
203	2025-03-24 16:21:28.952338	druglist	INSERT	\N	{"amount": 2, "drug_id": 1, "invoice_id": 3}
204	2025-03-24 16:22:41.870523	druglist	DELETE	{"amount": 2, "drug_id": 1, "invoice_id": 3}	\N
205	2025-03-24 16:35:31.725377	druglist	UPDATE	{"amount": 3, "drug_id": 2, "invoice_id": 3}	{"amount": 3, "drug_id": 2, "invoice_id": 3}
206	2025-03-24 16:35:31.725377	invoice	UPDATE	{"status": false, "invoice_id": 3}	{"status": true, "invoice_id": 3}
207	2025-03-24 16:35:31.725377	druglist	UPDATE	{"amount": 4, "drug_id": 2, "invoice_id": 1}	{"amount": 4, "drug_id": 2, "invoice_id": 1}
208	2025-03-24 16:35:31.725377	druglist	UPDATE	{"amount": 3, "drug_id": 2, "invoice_id": 3}	{"amount": 3, "drug_id": 2, "invoice_id": 3}
209	2025-03-24 16:35:31.725377	drug	UPDATE	{"pi": "Используется для снятия усталости и повышения концентрации. Не рекомендуется перед сном.", "name": "Кофеин", "price": 150, "amount": 90, "drug_id": 2, "description": "Стимулирует центральную нервную систему, повышает бодрость.", "expiry_date": "2027-08-20", "prescription": false}	{"pi": "Используется для снятия усталости и повышения концентрации. Не рекомендуется перед сном.", "name": "Кофеин", "price": 150, "amount": 93, "drug_id": 2, "description": "Стимулирует центральную нервную систему, повышает бодрость.", "expiry_date": "2027-08-20", "prescription": false}
210	2025-03-24 16:37:00.652392	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 2}	\N
211	2025-03-24 16:37:04.101161	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 2}
212	2025-03-24 16:58:07.765698	accessrights	INSERT	\N	{"description": "unvpx_b", "accessrights_id": 3}
213	2025-03-24 16:58:24.22585	accessrights	INSERT	\N	{"description": "unvbills_b", "accessrights_id": 4}
214	2025-03-24 16:58:32.726432	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 2}	\N
215	2025-03-24 16:58:32.726432	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 2}
216	2025-03-24 16:58:32.726432	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 3}
217	2025-03-24 16:58:32.726432	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 4}
218	2025-03-24 17:31:43.231074	accessrights	INSERT	\N	{"description": "activesubs_b", "accessrights_id": 5}
219	2025-03-24 17:31:52.703212	accessrights	INSERT	\N	{"description": "farmgroups_b", "accessrights_id": 6}
221	2025-03-24 17:32:19.377352	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 2}	\N
222	2025-03-24 17:32:19.377352	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 3}	\N
223	2025-03-24 17:32:19.377352	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 4}	\N
224	2025-03-24 17:32:19.377352	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 3}
225	2025-03-24 17:32:19.377352	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 4}
226	2025-03-24 17:32:19.377352	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 5}
227	2025-03-24 17:32:19.377352	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 6}
228	2025-03-24 17:32:19.377352	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 7}
229	2025-03-24 17:32:26.535595	accessrights	DELETE	{"description": "право", "accessrights_id": 2}	\N
230	2025-03-24 18:23:16.033334	invoice	DELETE	{"status": true, "invoice_id": 2}	\N
231	2025-03-24 18:42:40.492692	shoppingcart	DELETE	{"bill_id": 17, "drug_id": 3}	\N
232	2025-03-24 18:42:40.492692	bill	UPDATE	{"amount": 1150, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 900, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
233	2025-03-24 18:53:08.433298	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 6}
234	2025-03-24 18:53:08.433298	bill	UPDATE	{"amount": 900, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 1020, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
235	2025-03-24 18:53:23.060857	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 8}
236	2025-03-24 18:53:23.060857	bill	UPDATE	{"amount": 1020, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 1270, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
237	2025-03-24 19:07:02.393543	prescription	INSERT	\N	{"px_id": 6, "status": false, "client_id": 5, "drug_name": "парацетамол", "expiry_date": "2026-04-19", "drug_quantity": 1}
238	2025-03-24 19:39:46.446601	shoppingcart	INSERT	\N	{"bill_id": 17, "drug_id": 7}
239	2025-03-24 19:39:46.446601	bill	UPDATE	{"amount": 1270, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 1490, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
240	2025-03-24 19:40:43.712759	shoppingcart	DELETE	{"bill_id": 17, "drug_id": 4}	\N
241	2025-03-24 19:40:43.712759	bill	UPDATE	{"amount": 1490, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 1090, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
242	2025-03-24 19:40:46.298616	shoppingcart	DELETE	{"bill_id": 17, "drug_id": 1}	\N
243	2025-03-24 19:40:46.298616	bill	UPDATE	{"amount": 1090, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 740, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
244	2025-03-24 19:40:48.060379	bill	UPDATE	{"amount": 740, "status": false, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}	{"amount": 740, "status": true, "bill_id": 17, "client_id": 5, "date_time": "2025-03-23T20:41:37.84196"}
245	2025-03-24 19:41:52.276435	prescription	INSERT	\N	{"px_id": 8, "status": false, "client_id": 5, "drug_name": "sdada", "expiry_date": "2025-03-29", "drug_quantity": 7}
246	2025-03-24 19:42:19.070438	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
247	2025-03-24 19:42:19.070438	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
248	2025-03-24 19:42:19.070438	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
249	2025-03-24 19:43:05.390737	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 19, "client_id": 5, "date_time": "2025-03-24T19:43:05.390737"}
250	2025-03-24 19:43:05.390737	shoppingcart	INSERT	\N	{"bill_id": 19, "drug_id": 8}
251	2025-03-24 19:43:05.390737	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 19, "client_id": 5, "date_time": "2025-03-24T19:43:05.390737"}	{"amount": 250, "status": false, "bill_id": 19, "client_id": 5, "date_time": "2025-03-24T19:43:05.390737"}
252	2025-03-24 19:43:40.42912	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 19, "client_id": 5, "date_time": "2025-03-24T19:43:05.390737"}	{"amount": 250, "status": true, "bill_id": 19, "client_id": 5, "date_time": "2025-03-24T19:43:05.390737"}
253	2025-03-25 16:55:13.64487	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}
254	2025-03-25 16:55:13.64487	shoppingcart	INSERT	\N	{"bill_id": 20, "drug_id": 3}
255	2025-03-25 16:55:13.64487	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}	{"amount": 250, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}
256	2025-03-25 23:04:46.348455	shoppingcart	UPDATE	{"bill_id": 20, "drug_id": 3, "quantity": 1}	{"bill_id": 20, "drug_id": 3, "quantity": 2}
257	2025-03-25 23:04:46.348455	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}	{"amount": 500, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}
258	2025-03-25 23:04:46.348455	bill	UPDATE	{"amount": 500, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}	{"amount": 750, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}
259	2025-03-25 23:06:30.875842	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}	{"amount": 750, "status": true, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}
260	2025-03-25 23:07:07.28091	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}
261	2025-03-25 23:07:07.28091	shoppingcart	INSERT	\N	{"bill_id": 21, "drug_id": 4, "quantity": 1}
262	2025-03-25 23:07:07.28091	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}	{"amount": 400, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}
263	2025-03-25 23:07:07.28091	bill	UPDATE	{"amount": 400, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}	{"amount": 800, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}
264	2025-03-25 23:07:07.28091	bill	UPDATE	{"amount": 800, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}	{"amount": 1200, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}
265	2025-03-25 23:18:20.559058	shoppingcart	DELETE	{"bill_id": 21, "drug_id": 4, "quantity": 1}	\N
266	2025-03-25 23:18:20.559058	bill	UPDATE	{"amount": 1200, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}	{"amount": 800, "status": false, "bill_id": 21, "client_id": 5, "date_time": "2025-03-25T23:07:07.28091"}
267	2025-03-25 23:22:30.928032	bill	DELETE	{"amount": 750, "status": true, "bill_id": 20, "client_id": 5, "date_time": "2025-03-25T16:55:13.64487"}	\N
272	2025-03-25 23:22:55.938965	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}	{"amount": 400, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}
273	2025-03-25 23:24:02.857264	shoppingcart	UPDATE	{"bill_id": 22, "drug_id": 4, "quantity": 1}	{"bill_id": 22, "drug_id": 4, "quantity": 2}
274	2025-03-25 23:24:02.857264	bill	UPDATE	{"amount": 400, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}	{"amount": 800, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}
275	2025-03-25 23:44:25.999759	shoppingcart	DELETE	{"bill_id": 22, "drug_id": 4, "quantity": 2}	\N
276	2025-03-25 23:44:25.999759	bill	UPDATE	{"amount": 800, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}	{"amount": 0, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}
277	2025-03-25 23:45:43.404827	shoppingcart	INSERT	\N	{"bill_id": 22, "drug_id": 8, "quantity": 1}
278	2025-03-25 23:45:43.404827	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}	{"amount": 250, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}
279	2025-03-25 23:45:54.454121	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}	{"amount": 250, "status": true, "bill_id": 22, "client_id": 5, "date_time": "2025-03-25T23:22:55.938965"}
280	2025-03-25 23:48:47.759621	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 23, "client_id": 5, "date_time": "2025-03-25T23:48:47.759621"}
281	2025-03-25 23:48:47.759621	shoppingcart	INSERT	\N	{"bill_id": 23, "drug_id": 2, "quantity": 1}
282	2025-03-25 23:48:47.759621	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 23, "client_id": 5, "date_time": "2025-03-25T23:48:47.759621"}	{"amount": 150, "status": false, "bill_id": 23, "client_id": 5, "date_time": "2025-03-25T23:48:47.759621"}
283	2025-03-25 23:49:10.427641	bill	UPDATE	{"amount": 150, "status": false, "bill_id": 23, "client_id": 5, "date_time": "2025-03-25T23:48:47.759621"}	{"amount": 150, "status": true, "bill_id": 23, "client_id": 5, "date_time": "2025-03-25T23:48:47.759621"}
284	2025-03-25 23:57:37.174254	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
285	2025-03-25 23:57:37.174254	shoppingcart	INSERT	\N	{"bill_id": 24, "drug_id": 7, "quantity": 1}
286	2025-03-25 23:57:37.174254	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 220, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
287	2025-03-25 23:58:50.7328	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 1}	{"bill_id": 24, "drug_id": 7, "quantity": 3}
288	2025-03-25 23:58:50.7328	bill	UPDATE	{"amount": 220, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
289	2025-03-26 00:17:49.101021	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 3}	{"bill_id": 24, "drug_id": 7, "quantity": 5}
290	2025-03-26 00:17:49.101021	bill	UPDATE	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 1100, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
291	2025-03-26 00:17:49.966664	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 5}	{"bill_id": 24, "drug_id": 7, "quantity": 4}
292	2025-03-26 00:17:49.966664	bill	UPDATE	{"amount": 1100, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 880, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
293	2025-03-26 00:18:00.543042	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 4}	{"bill_id": 24, "drug_id": 7, "quantity": 3}
294	2025-03-26 00:18:00.543042	bill	UPDATE	{"amount": 880, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
295	2025-03-26 00:18:05.09609	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 3}	{"bill_id": 24, "drug_id": 7, "quantity": 4}
296	2025-03-26 00:18:05.09609	bill	UPDATE	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 880, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
297	2025-03-26 00:18:09.255134	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 4}	{"bill_id": 24, "drug_id": 7, "quantity": 3}
298	2025-03-26 00:18:09.255134	bill	UPDATE	{"amount": 880, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
299	2025-03-26 00:18:11.805455	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 3}	{"bill_id": 24, "drug_id": 7, "quantity": 2}
300	2025-03-26 00:18:11.805455	bill	UPDATE	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 440, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
301	2025-03-26 00:20:07.994972	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 2}	{"bill_id": 24, "drug_id": 7, "quantity": 3}
302	2025-03-26 00:20:07.994972	bill	UPDATE	{"amount": 440, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
303	2025-03-26 00:20:48.853655	shoppingcart	UPDATE	{"bill_id": 24, "drug_id": 7, "quantity": 3}	{"bill_id": 24, "drug_id": 7, "quantity": 2}
304	2025-03-26 00:20:48.853655	bill	UPDATE	{"amount": 660, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 440, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
305	2025-03-26 00:20:52.730391	bill	UPDATE	{"amount": 440, "status": false, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}	{"amount": 440, "status": true, "bill_id": 24, "client_id": 5, "date_time": "2025-03-25T23:57:37.174254"}
306	2025-03-26 00:28:17.823792	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
307	2025-03-26 00:28:17.823792	shoppingcart	INSERT	\N	{"bill_id": 25, "drug_id": 6, "quantity": 1}
308	2025-03-26 00:28:17.823792	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}	{"amount": 120, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
309	2025-03-26 00:28:26.547131	shoppingcart	UPDATE	{"bill_id": 25, "drug_id": 6, "quantity": 1}	{"bill_id": 25, "drug_id": 6, "quantity": 2}
310	2025-03-26 00:28:26.547131	bill	UPDATE	{"amount": 120, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}	{"amount": 240, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
311	2025-03-26 00:28:26.863347	shoppingcart	UPDATE	{"bill_id": 25, "drug_id": 6, "quantity": 2}	{"bill_id": 25, "drug_id": 6, "quantity": 3}
312	2025-03-26 00:28:26.863347	bill	UPDATE	{"amount": 240, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}	{"amount": 360, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
313	2025-03-26 00:28:27.227241	shoppingcart	UPDATE	{"bill_id": 25, "drug_id": 6, "quantity": 3}	{"bill_id": 25, "drug_id": 6, "quantity": 4}
314	2025-03-26 00:28:27.227241	bill	UPDATE	{"amount": 360, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}	{"amount": 480, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
315	2025-03-26 00:28:35.964065	shoppingcart	INSERT	\N	{"bill_id": 25, "drug_id": 8, "quantity": 1}
316	2025-03-26 00:28:35.964065	bill	UPDATE	{"amount": 480, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}	{"amount": 730, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
317	2025-03-26 00:28:45.660476	bill	UPDATE	{"amount": 730, "status": false, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}	{"amount": 730, "status": true, "bill_id": 25, "client_id": 5, "date_time": "2025-03-26T00:28:17.823792"}
318	2025-03-26 15:00:48.623014	druglist	INSERT	\N	{"amount": 1, "drug_id": 8, "invoice_id": 1}
319	2025-03-26 16:22:15.372189	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
320	2025-03-26 16:22:15.372189	shoppingcart	INSERT	\N	{"bill_id": 26, "drug_id": 3, "quantity": 1}
388	2025-03-29 18:38:19.908565	shoppingcart	INSERT	\N	{"bill_id": 27, "drug_id": 8, "quantity": 1}
321	2025-03-26 16:22:15.372189	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 250, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
322	2025-03-26 19:05:59.055208	prescription	INSERT	\N	{"px_id": 9, "status": false, "client_id": 4, "drug_name": "препарат", "expiry_date": "2025-09-29", "drug_quantity": 1}
323	2025-03-26 19:06:07.550806	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}
324	2025-03-26 19:06:07.550806	shoppingcart	INSERT	\N	{"bill_id": 27, "drug_id": 1, "quantity": 1}
325	2025-03-26 19:06:07.550806	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}	{"amount": 350, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}
326	2025-03-26 19:06:11.749022	shoppingcart	INSERT	\N	{"bill_id": 27, "drug_id": 4, "quantity": 1}
327	2025-03-26 19:06:11.749022	bill	UPDATE	{"amount": 350, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}	{"amount": 750, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}
328	2025-03-26 19:08:13.015685	druglist	DELETE	{"amount": 5, "drug_id": 3, "invoice_id": 1}	\N
329	2025-03-26 19:08:18.730819	druglist	INSERT	\N	{"amount": 5, "drug_id": 3, "invoice_id": 1}
330	2025-03-26 19:08:37.14699	employee_info	INSERT	\N	{"login": "mod", "password": "$2a$06$5W4EEGrSZUz/rSu/IXWshuFsJySECDyJB2MWtiX8k/V4/xNvD2Iva"}
331	2025-03-26 19:08:37.14699	employee	INSERT	\N	{"login": "mod", "employee_id": 4}
332	2025-03-26 19:08:42.426051	employeerights	INSERT	\N	{"employee_id": 4, "accessrights_id": 3}
333	2025-03-26 19:11:09.823817	shoppingcart	INSERT	\N	{"bill_id": 26, "drug_id": 8, "quantity": 1}
334	2025-03-26 19:11:09.823817	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 500, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
335	2025-03-26 19:11:14.819144	shoppingcart	UPDATE	{"bill_id": 26, "drug_id": 8, "quantity": 1}	{"bill_id": 26, "drug_id": 8, "quantity": 2}
336	2025-03-26 19:11:14.819144	bill	UPDATE	{"amount": 500, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 750, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
337	2025-03-26 19:11:19.734242	shoppingcart	UPDATE	{"bill_id": 26, "drug_id": 8, "quantity": 2}	{"bill_id": 26, "drug_id": 8, "quantity": 1}
338	2025-03-26 19:11:19.734242	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 500, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
339	2025-03-26 19:14:58.127403	shoppingcart	UPDATE	{"bill_id": 26, "drug_id": 8, "quantity": 1}	{"bill_id": 26, "drug_id": 8, "quantity": 2}
340	2025-03-26 19:14:58.127403	bill	UPDATE	{"amount": 500, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 750, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
341	2025-03-26 19:15:02.920477	shoppingcart	UPDATE	{"bill_id": 26, "drug_id": 8, "quantity": 2}	{"bill_id": 26, "drug_id": 8, "quantity": 1}
342	2025-03-26 19:15:02.920477	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 500, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
343	2025-03-26 19:18:56.479113	shoppingcart	UPDATE	{"bill_id": 26, "drug_id": 8, "quantity": 1}	{"bill_id": 26, "drug_id": 8, "quantity": 2}
344	2025-03-26 19:18:56.479113	bill	UPDATE	{"amount": 500, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 750, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
345	2025-03-26 19:18:56.767163	shoppingcart	UPDATE	{"bill_id": 26, "drug_id": 8, "quantity": 2}	{"bill_id": 26, "drug_id": 8, "quantity": 3}
346	2025-03-26 19:18:56.767163	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}	{"amount": 1000, "status": false, "bill_id": 26, "client_id": 5, "date_time": "2025-03-26T16:22:15.372189"}
347	2025-03-29 15:30:05.265337	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
348	2025-03-29 15:30:05.265337	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White ", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
349	2025-03-29 15:30:05.265337	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White ", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White ", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
350	2025-03-29 15:30:11.13527	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White ", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White ", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
351	2025-03-29 15:30:11.13527	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White ", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
352	2025-03-29 15:30:11.13527	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
353	2025-03-29 15:31:49.800476	client_info	UPDATE	{"name": "Jack", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Джек", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
354	2025-03-29 15:31:49.800476	client_info	UPDATE	{"name": "Джек", "login": "jack", "surname": "White", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Джек", "login": "jack", "surname": "Уайт", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
355	2025-03-29 15:31:49.800476	client_info	UPDATE	{"name": "Джек", "login": "jack", "surname": "Уайт", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}	{"name": "Джек", "login": "jack", "surname": "Уайт", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": ""}
356	2025-03-29 15:46:39.432748	client_info	INSERT	\N	{"name": "Jordan", "login": "jojo33", "surname": "Joseph", "password": "$2a$06$05KvX235Cn0IB7bZgZF22eKGeNxh4w08292u9b4v7lMQr0fuY91R6", "birth_date": "2002-06-29", "patronymic": ""}
357	2025-03-29 15:46:39.432748	client	INSERT	\N	{"login": "jojo33", "client_id": 7}
358	2025-03-29 16:17:06.460284	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 3}	\N
359	2025-03-29 16:17:06.460284	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 4}	\N
360	2025-03-29 16:17:06.460284	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 5}	\N
361	2025-03-29 16:17:06.460284	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 6}	\N
362	2025-03-29 16:17:06.460284	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 7}	\N
363	2025-03-29 16:17:06.460284	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 4}
364	2025-03-29 16:17:06.460284	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 5}
365	2025-03-29 16:17:06.460284	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 6}
366	2025-03-29 16:17:06.460284	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 7}
367	2025-03-29 16:17:11.559646	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 4}	\N
368	2025-03-29 16:17:11.559646	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 5}	\N
369	2025-03-29 16:17:11.559646	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 6}	\N
370	2025-03-29 16:17:11.559646	employeerights	DELETE	{"employee_id": 1, "accessrights_id": 7}	\N
371	2025-03-29 16:17:11.559646	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 3}
372	2025-03-29 16:17:11.559646	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 4}
373	2025-03-29 16:17:11.559646	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 5}
374	2025-03-29 16:17:11.559646	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 6}
375	2025-03-29 16:17:11.559646	employeerights	INSERT	\N	{"employee_id": 1, "accessrights_id": 7}
376	2025-03-29 18:22:08.395835	client_info	UPDATE	{"name": "Джек", "login": "jack", "surname": "Уайт", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": "", "phone_number": null}	{"name": "Джек", "login": "jack", "surname": "Уайт", "password": "$2a$06$Faw4vE3mHc280HInGb3HoOso7XqYplZzk69/wUY6Deq4Kw2YnFeI.", "birth_date": "1995-02-13", "patronymic": "", "phone_number": "798319103"}
377	2025-03-29 18:31:13.134931	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 28, "client_id": 7, "date_time": "2025-03-29T18:31:13.134931"}
378	2025-03-29 18:31:13.134931	shoppingcart	INSERT	\N	{"bill_id": 28, "drug_id": 7, "quantity": 1}
379	2025-03-29 18:31:13.134931	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 28, "client_id": 7, "date_time": "2025-03-29T18:31:13.134931"}	{"amount": 220, "status": false, "bill_id": 28, "client_id": 7, "date_time": "2025-03-29T18:31:13.134931"}
380	2025-03-29 18:31:18.605574	bill	UPDATE	{"amount": 220, "status": false, "bill_id": 28, "client_id": 7, "date_time": "2025-03-29T18:31:13.134931"}	{"amount": 220, "status": true, "bill_id": 28, "client_id": 7, "date_time": "2025-03-29T18:31:13.134931"}
381	2025-03-29 18:32:33.379392	bill	INSERT	\N	{"amount": 0, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}
382	2025-03-29 18:32:33.379392	shoppingcart	INSERT	\N	{"bill_id": 29, "drug_id": 8, "quantity": 1}
383	2025-03-29 18:32:33.379392	bill	UPDATE	{"amount": 0, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}	{"amount": 250, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}
384	2025-03-29 18:36:57.351808	shoppingcart	INSERT	\N	{"bill_id": 29, "drug_id": 5, "quantity": 1}
385	2025-03-29 18:36:57.351808	bill	UPDATE	{"amount": 250, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}	{"amount": 430, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}
386	2025-03-29 18:36:59.701197	shoppingcart	INSERT	\N	{"bill_id": 29, "drug_id": 6, "quantity": 1}
387	2025-03-29 18:36:59.701197	bill	UPDATE	{"amount": 430, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}	{"amount": 550, "status": false, "bill_id": 29, "client_id": 7, "date_time": "2025-03-29T18:32:33.379392"}
389	2025-03-29 18:38:19.908565	bill	UPDATE	{"amount": 750, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}	{"amount": 1000, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}
390	2025-03-29 18:38:23.240449	shoppingcart	INSERT	\N	{"bill_id": 27, "drug_id": 2, "quantity": 1}
391	2025-03-29 18:38:23.240449	bill	UPDATE	{"amount": 1000, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}	{"amount": 1150, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}
392	2025-03-29 18:38:25.234302	shoppingcart	INSERT	\N	{"bill_id": 27, "drug_id": 3, "quantity": 1}
393	2025-03-29 18:38:25.234302	bill	UPDATE	{"amount": 1150, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}	{"amount": 1400, "status": false, "bill_id": 27, "client_id": 4, "date_time": "2025-03-26T19:06:07.550806"}
\.


--
-- Data for Name: prescription; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.prescription (px_id, client_id, status, expiry_date, drug_name, drug_quantity) FROM stdin;
3	5	t	2025-09-25	амоксиклав	2
1	1	t	2026-12-31	парацетамол	5
4	4	t	2026-07-29	ибупрофен	1
5	4	t	2027-01-29	парацетамол	1
6	5	f	2026-04-19	парацетамол	1
8	5	f	2025-03-29	sdada	7
9	4	f	2025-09-29	препарат	1
\.


--
-- Data for Name: shoppingcart; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.shoppingcart (bill_id, drug_id, quantity) FROM stdin;
12	7	1
12	8	1
13	8	1
13	1	1
14	2	1
15	6	1
16	8	1
16	6	1
16	1	1
17	2	1
18	1	1
17	6	1
17	8	1
17	7	1
19	8	1
22	8	1
23	2	1
24	7	2
25	6	4
25	8	1
26	3	1
27	1	1
27	4	1
26	8	3
28	7	1
29	8	1
29	5	1
29	6	1
27	8	1
27	2	1
27	3	1
\.


--
-- Name: accessrights_accessrights_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.accessrights_accessrights_id_seq', 7, true);


--
-- Name: activesub_activesub_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.activesub_activesub_id_seq', 37, true);


--
-- Name: activesublist_activesub_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.activesublist_activesub_id_seq', 1, false);


--
-- Name: activesublist_drug_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.activesublist_drug_id_seq', 1, false);


--
-- Name: bill_bill_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bill_bill_id_seq', 29, true);


--
-- Name: bill_client_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bill_client_id_seq', 1, false);


--
-- Name: client_client_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.client_client_id_seq', 7, true);


--
-- Name: drug_drug_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.drug_drug_id_seq', 9, true);


--
-- Name: employee_employee_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employee_employee_id_seq', 4, true);


--
-- Name: employeerights_accessrights_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employeerights_accessrights_id_seq', 1, false);


--
-- Name: employeerights_employee_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employeerights_employee_id_seq', 1, false);


--
-- Name: farmgroup_farmgroup_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.farmgroup_farmgroup_id_seq', 21, true);


--
-- Name: farmgrouplist_drug_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.farmgrouplist_drug_id_seq', 1, false);


--
-- Name: farmgrouplist_farmgroup_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.farmgrouplist_farmgroup_id_seq', 1, false);


--
-- Name: invoice_invoice_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.invoice_invoice_id_seq', 3, true);


--
-- Name: log_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.log_log_id_seq', 393, true);


--
-- Name: prescription_client_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.prescription_client_id_seq', 1, false);


--
-- Name: prescription_px_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.prescription_px_id_seq', 9, true);


--
-- Name: shoppingcart_bill_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.shoppingcart_bill_id_seq', 1, false);


--
-- Name: shoppingcart_drug_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.shoppingcart_drug_id_seq', 1, false);


--
-- Name: accessrights accessrights_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accessrights
    ADD CONSTRAINT accessrights_pkey PRIMARY KEY (accessrights_id);


--
-- Name: activesub_info activesub_info_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesub_info
    ADD CONSTRAINT activesub_info_pkey PRIMARY KEY (name);


--
-- Name: activesub activesub_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesub
    ADD CONSTRAINT activesub_pkey PRIMARY KEY (activesub_id);


--
-- Name: bill bill_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_pkey PRIMARY KEY (bill_id);


--
-- Name: client_info client_info_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_info
    ADD CONSTRAINT client_info_phone_number_key UNIQUE (phone_number);


--
-- Name: client_info client_info_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_info
    ADD CONSTRAINT client_info_pkey PRIMARY KEY (login);


--
-- Name: client client_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_pkey PRIMARY KEY (client_id);


--
-- Name: drug drug_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.drug
    ADD CONSTRAINT drug_pkey PRIMARY KEY (drug_id);


--
-- Name: druglist druglist_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.druglist
    ADD CONSTRAINT druglist_pkey PRIMARY KEY (invoice_id, drug_id);


--
-- Name: employee_info employee_info_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_info
    ADD CONSTRAINT employee_info_pkey PRIMARY KEY (login);


--
-- Name: employee employee_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT employee_pkey PRIMARY KEY (employee_id);


--
-- Name: farmgroup_info farmgroup_info_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgroup_info
    ADD CONSTRAINT farmgroup_info_pkey PRIMARY KEY (name);


--
-- Name: farmgroup farmgroup_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgroup
    ADD CONSTRAINT farmgroup_pkey PRIMARY KEY (farmgroup_id);


--
-- Name: invoice invoice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (invoice_id);


--
-- Name: log log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log
    ADD CONSTRAINT log_pkey PRIMARY KEY (log_id);


--
-- Name: prescription prescription_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription
    ADD CONSTRAINT prescription_pkey PRIMARY KEY (px_id);


--
-- Name: shoppingcart check_drug_exists_before_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_drug_exists_before_insert BEFORE INSERT ON public.shoppingcart FOR EACH ROW EXECUTE FUNCTION public.check_drug_exists();


--
-- Name: client_info client_info_delete_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER client_info_delete_trigger AFTER DELETE ON public.client_info FOR EACH ROW EXECUTE FUNCTION public.delete_client_prescriptions();


--
-- Name: client_info client_info_update_password_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER client_info_update_password_trigger BEFORE UPDATE OF password ON public.client_info FOR EACH ROW EXECUTE FUNCTION public.update_password();


--
-- Name: prescription delete_expired_prescription_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER delete_expired_prescription_trigger BEFORE INSERT OR UPDATE ON public.prescription FOR EACH ROW EXECUTE FUNCTION public.delete_expired_prescription();


--
-- Name: drug druglist_delete_on_drug_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER druglist_delete_on_drug_delete AFTER DELETE ON public.drug FOR EACH ROW EXECUTE FUNCTION public.delete_druglist_on_drug_delete();


--
-- Name: invoice druglist_delete_on_invoice_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER druglist_delete_on_invoice_delete AFTER DELETE ON public.invoice FOR EACH ROW EXECUTE FUNCTION public.delete_druglist_on_invoice_delete();


--
-- Name: drug druglist_update_on_drug_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER druglist_update_on_drug_update AFTER UPDATE ON public.drug FOR EACH ROW EXECUTE FUNCTION public.update_druglist_on_drug_update();


--
-- Name: invoice druglist_update_on_invoice_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER druglist_update_on_invoice_update AFTER UPDATE ON public.invoice FOR EACH ROW EXECUTE FUNCTION public.update_druglist_on_invoice_update();


--
-- Name: accessrights trg_accessrights_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_accessrights_log AFTER INSERT OR DELETE OR UPDATE ON public.accessrights FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: activesub_info trg_activesub_info_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_activesub_info_log AFTER INSERT OR DELETE OR UPDATE ON public.activesub_info FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: activesub trg_activesub_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_activesub_log AFTER INSERT OR DELETE OR UPDATE ON public.activesub FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: activesublist trg_activesublist_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_activesublist_log AFTER INSERT OR DELETE OR UPDATE ON public.activesublist FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: bill trg_bill_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_bill_log AFTER INSERT OR DELETE OR UPDATE ON public.bill FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: client_info trg_client_info_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_client_info_log AFTER INSERT OR DELETE OR UPDATE ON public.client_info FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: client trg_client_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_client_log AFTER INSERT OR DELETE OR UPDATE ON public.client FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: drug trg_drug_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_drug_log AFTER INSERT OR DELETE OR UPDATE ON public.drug FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: druglist trg_druglist_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_druglist_log AFTER INSERT OR DELETE OR UPDATE ON public.druglist FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: employee_info trg_employee_info_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_employee_info_log AFTER INSERT OR DELETE OR UPDATE ON public.employee_info FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: employee trg_employee_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_employee_log AFTER INSERT OR DELETE OR UPDATE ON public.employee FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: employeerights trg_employeerights_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_employeerights_log AFTER INSERT OR DELETE OR UPDATE ON public.employeerights FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: farmgroup_info trg_farmgroup_info_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_farmgroup_info_log AFTER INSERT OR DELETE OR UPDATE ON public.farmgroup_info FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: farmgroup trg_farmgroup_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_farmgroup_log AFTER INSERT OR DELETE OR UPDATE ON public.farmgroup FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: farmgrouplist trg_farmgrouplist_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_farmgrouplist_log AFTER INSERT OR DELETE OR UPDATE ON public.farmgrouplist FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: invoice trg_invoice_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_invoice_log AFTER INSERT OR DELETE OR UPDATE ON public.invoice FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: prescription trg_prescription_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_prescription_log AFTER INSERT OR DELETE OR UPDATE ON public.prescription FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: shoppingcart trg_shoppingcart_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_shoppingcart_log AFTER INSERT OR DELETE OR UPDATE ON public.shoppingcart FOR EACH ROW EXECUTE FUNCTION public.log_trigger_function();


--
-- Name: activesub trigger_delete_activesublist_activesub; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_delete_activesublist_activesub AFTER DELETE ON public.activesub FOR EACH ROW EXECUTE FUNCTION public.delete_from_activesublist_activesub();


--
-- Name: drug trigger_delete_activesublist_drug; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_delete_activesublist_drug AFTER DELETE ON public.drug FOR EACH ROW EXECUTE FUNCTION public.delete_from_activesublist_drug();


--
-- Name: drug trigger_delete_farmgrouplist_drug; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_delete_farmgrouplist_drug AFTER DELETE ON public.drug FOR EACH ROW EXECUTE FUNCTION public.delete_from_farmgrouplist_drug();


--
-- Name: farmgroup trigger_delete_farmgrouplist_farmgroup; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_delete_farmgrouplist_farmgroup AFTER DELETE ON public.farmgroup FOR EACH ROW EXECUTE FUNCTION public.delete_from_farmgrouplist_farmgroup();


--
-- Name: activesub_info trigger_insert_activesub; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_insert_activesub AFTER INSERT ON public.activesub_info FOR EACH ROW EXECUTE FUNCTION public.insert_into_activesub();


--
-- Name: farmgroup_info trigger_insert_farmgroup; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_insert_farmgroup AFTER INSERT ON public.farmgroup_info FOR EACH ROW EXECUTE FUNCTION public.insert_into_farmgroup();


--
-- Name: shoppingcart update_bill_amount_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_bill_amount_trigger AFTER INSERT OR DELETE OR UPDATE ON public.shoppingcart FOR EACH ROW EXECUTE FUNCTION public.update_bill_amount();


--
-- Name: activesub activesub_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesub
    ADD CONSTRAINT activesub_name_fkey FOREIGN KEY (name) REFERENCES public.activesub_info(name) ON DELETE CASCADE;


--
-- Name: activesublist activesublist_activesub_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesublist
    ADD CONSTRAINT activesublist_activesub_id_fkey FOREIGN KEY (activesub_id) REFERENCES public.activesub(activesub_id);


--
-- Name: activesublist activesublist_drug_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activesublist
    ADD CONSTRAINT activesublist_drug_id_fkey FOREIGN KEY (drug_id) REFERENCES public.drug(drug_id);


--
-- Name: bill bill_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.client(client_id);


--
-- Name: client client_login_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_login_fkey FOREIGN KEY (login) REFERENCES public.client_info(login);


--
-- Name: druglist druglist_drug_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.druglist
    ADD CONSTRAINT druglist_drug_id_fkey FOREIGN KEY (drug_id) REFERENCES public.drug(drug_id);


--
-- Name: druglist druglist_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.druglist
    ADD CONSTRAINT druglist_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoice(invoice_id);


--
-- Name: employee employee_login_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT employee_login_fkey FOREIGN KEY (login) REFERENCES public.employee_info(login) ON DELETE CASCADE;


--
-- Name: employeerights employeerights_accessrights_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employeerights
    ADD CONSTRAINT employeerights_accessrights_id_fkey FOREIGN KEY (accessrights_id) REFERENCES public.accessrights(accessrights_id);


--
-- Name: employeerights employeerights_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employeerights
    ADD CONSTRAINT employeerights_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee(employee_id);


--
-- Name: farmgroup farmgroup_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgroup
    ADD CONSTRAINT farmgroup_name_fkey FOREIGN KEY (name) REFERENCES public.farmgroup_info(name) ON DELETE CASCADE;


--
-- Name: farmgrouplist farmgrouplist_drug_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgrouplist
    ADD CONSTRAINT farmgrouplist_drug_id_fkey FOREIGN KEY (drug_id) REFERENCES public.drug(drug_id);


--
-- Name: farmgrouplist farmgrouplist_farmgroup_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.farmgrouplist
    ADD CONSTRAINT farmgrouplist_farmgroup_id_fkey FOREIGN KEY (farmgroup_id) REFERENCES public.farmgroup(farmgroup_id);


--
-- Name: prescription prescription_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prescription
    ADD CONSTRAINT prescription_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.client(client_id);


--
-- Name: shoppingcart shoppingcart_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shoppingcart
    ADD CONSTRAINT shoppingcart_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(bill_id) ON DELETE CASCADE;


--
-- Name: shoppingcart shoppingcart_drug_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shoppingcart
    ADD CONSTRAINT shoppingcart_drug_id_fkey FOREIGN KEY (drug_id) REFERENCES public.drug(drug_id);


--
-- PostgreSQL database dump complete
--

