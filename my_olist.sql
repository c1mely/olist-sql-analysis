--импортирую данные olist, которые хотела бы проанализировать 
CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(50),
    customer_city VARCHAR(50),
    customer_state VARCHAR(50)
);

SELECT * FROM customers c LIMIT 10;

CREATE TABLE orders(
order_id VARCHAR(50) PRIMARY KEY,
customer_id VARCHAR(50) REFERENCES customers(customer_id),
order_status VARCHAR(20),
order_purchase_timestamp DATE,
order_approved_at DATE,
order_delivered_carrier_date DATE,
order_delivered_customer_date DATE,
order_estimated_delivery_date DATE
);

SELECT * FROM orders LIMIT 10;

CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name VARCHAR(50),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
    );

SELECT * FROM products pr LIMIT 10;

CREATE TABLE order_items(
    order_id VARCHAR(50) REFERENCES orders(order_id),
    order_item_id VARCHAR(50),
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date DATE,
    price NUMERIC(10,2),
    freight_value NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

SELECT * FROM order_items oi LIMIT 10;

CREATE TABLE payments(
order_id VARCHAR(50) REFERENCES orders(order_id),
payment_sequential INT,
payment_type VARCHAR(50),
payment_installments INT,
payment_value NUMERIC(10,2)
);

SELECT * FROM payments p LIMIT 10;

--есть ли пропуски в orders
SELECT
    COUNT(*) AS total_o,
    COUNT(*) - COUNT(order_id) AS missing_order_id,
    COUNT(*) - COUNT(customer_id) AS missing_customer_id,
    COUNT(*) - COUNT(order_status) AS missing_status,
    COUNT(*) - COUNT(order_purchase_timestamp) AS missing_purchase,
    COUNT(*) - COUNT(order_approved_at) AS missing_approved,
    COUNT(*) - COUNT(order_delivered_carrier_date) AS missing_carrier,
    COUNT(*) - COUNT(order_delivered_customer_date) AS missing_delivered,
    COUNT(*) - COUNT(order_estimated_delivery_date) AS missing_estimated
FROM orders;
--получилось много пропусков по датам, хочу посмотреть связано ли это с тем, что заказы не доставили

SELECT
    order_status,
    COUNT(*) AS total,
    COUNT(*) - COUNT(order_delivered_customer_date) AS missing_delivered
FROM orders
GROUP BY order_status
ORDER BY total DESC;
--получилось, что даты не имеют заказы, которые еще в процессе(созданы,в пути и др), с ними все нормально
--1) проблема с доставленным заказами (delivered) - 8 пропусков, даты нет, хотя должна быть
--2) проблема с отмененными (cancelled) у 619 заказов даты нет, что логично, но у шести заказов есть

--проверю доставленные заказы
SELECT order_status,
       order_purchase_timestamp,
       order_approved_at,
       order_delivered_carrier_date,
       order_delivered_customer_date,
       order_estimated_delivery_date
FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;
-- У 7 заказов дата получения не зафиксирована: вероятно, ошибка финального статуса. 
--У 1 заказа отсутствуют обе даты (ни передачи перевозчику, ни доставки)


--теперь посмотрю на cancelled
SELECT order_status,
       order_purchase_timestamp,
       order_approved_at,
       order_delivered_carrier_date,
       order_delivered_customer_date,
       order_estimated_delivery_date
FROM orders
WHERE order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL;
--я заметила, что 5 заказов были доставлены сильно раньше срока, а один с задержкой, возможно это причины отмены

--дальше хочу посмотреть на order_items
SELECT
    COUNT(*) AS total_oi,
    COUNT(DISTINCT order_id) AS unique_order_id,
    COUNT(*) - COUNT(product_id) AS missing_product,
    COUNT(*) - COUNT(seller_id) AS missing_seller,
    COUNT(*) - COUNT(price) AS missing_price,
    AVG(price) AS avg_price,
    MIN(price) AS min_price,
    MAX(price) AS max_price
FROM order_items;
--пропусков нет, сильных аномалий тоже

--посмотрим на таблицу payments
SELECT
    COUNT(*) AS total_p,
    COUNT(DISTINCT order_id) AS unique_order_id,
    COUNT(*) - COUNT(payment_type) AS missing_payment_type,
    COUNT(*) - COUNT(payment_value) AS missing_payment_value,
    AVG(payment_value) AS avg_value,
    MIN(payment_value) AS min_value,
    MAX(payment_value) AS max_value
FROM payments;
-- все нормально, кроме минимального платежа 0

SELECT *
FROM payments p
WHERE payment_value = 0;
--это платежи по купонам и с неопределенным типом оплаты

SELECT
    COUNT(*) AS total_p,
    COUNT(DISTINCT product_id) AS unique_products,
    COUNT(*) - COUNT(product_category_name) AS missing_category,
    COUNT(*) - COUNT(product_weight_g) AS missing_weight
FROM products pr; 
--получилось два значения без веса товара

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS unique_customer_id,
    COUNT(DISTINCT customer_unique_id) AS unique_customer_unique_id,
    COUNT(*) - COUNT(customer_state) AS missing_state,
    COUNT(*) - COUNT(customer_city) AS missing_city
FROM customers;
--тоже все хорошо

--после того как проверила данные, хочу проанализировать

--Как менялись метрики продаж во времени?
SELECT 
       SUM(p.payment_value) AS revenue,
       DATE_TRUNC('month', o.order_purchase_timestamp) AS month
FROM orders o
LEFT JOIN payments p ON p.order_id = o.order_id
GROUP BY month
ORDER BY month;
-- можно заметить, что данные в начале (сентябрь-декабрь 2016) и в конце(сентябрь-октябрь 2018) аномальные
-- их не будем учитывать при анализе

--cделаю cte чтобы было удобно работать с этой информацией
WITH monthly_revenue AS (
SELECT
      SUM(p.payment_value) AS revenue,
      DATE_TRUNC('month', o.order_purchase_timestamp) AS month
FROM orders o
LEFT JOIN payments p ON p.order_id = o.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01' AND o.order_purchase_timestamp < '2018-09-01'
GROUP BY month
)
SELECT 
      month,
      revenue,
      LAG(revenue) OVER(ORDER BY month) AS previous_month,
      revenue - LAG(revenue) OVER(ORDER BY month) AS difference
FROM monthly_revenue
ORDER BY month;
--в 2017 году выручка растет на протяжении всего года, но есть просадки в апреле, июне, декабре
--пик пришеося на ноябрь, минимальная выручка была в январе (вероятно это начало работы)

--в 2018 году выручка растет, есть небольшие провалы в феврале, июне, августе
--пик пришелся на апрель


--Какие топ 3 товара по выручке за каждый год?
SELECT
      SUM(oi.price) AS total_sum,
      pr.product_category_name
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
LEFT JOIN products pr ON oi.product_id = pr.product_id
WHERE oi.price IS NOT NULL
GROUP BY pr.product_category_name
ORDER BY total_sum DESC
LIMIT 3;
-- получились такие категории товаров beleza_saude, relogios_presentes, cama_mesa_banho  
     

-- В какие месяцы чаще всего оплачивают по купонам?

SELECT 
      DATE_TRUNC('month', o.order_purchase_timestamp) AS MONTH,
      COUNT(o.order_id) AS voucher_payments
FROM orders o
JOIN payments p ON o.order_id = p.order_id
WHERE p.payment_type = 'voucher'
GROUP BY month
ORDER BY COUNT(o.order_id) DESC;
-- в 2018 году в январе
-- в 2017 году в ноябре

--Клиенты, совершающие повторые покупки

WITH first_last_dates AS(
SELECT DISTINCT
      c.customer_unique_id,
      MIN(DATE_TRUNC('month', o.order_purchase_timestamp)) OVER(PARTITION BY c.customer_unique_id) AS first_date,
      MAX(DATE_TRUNC('month', o.order_purchase_timestamp)) OVER(PARTITION BY c.customer_unique_id) AS last_date
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
)
SELECT 
      customer_unique_id,
      TO_CHAR(first_date, 'Month YYYY') AS first_date,
      TO_CHAR(last_date, 'Month YYYY') AS last_date
FROM first_last_dates
WHERE first_date != last_date;

--Какой процент от выручки приносит каждый тип оплаты?

WITH types_values AS(
SELECT 
      p.payment_type,
      SUM(p.payment_value) AS sum_total
FROM payments p 
GROUP BY p.payment_type
)
SELECT
      payment_type,
      ROUND(sum_total / SUM(sum_total) OVER() * 100, 2) AS percentage
FROM types_values
ORDER BY percentage DESC
--видно, что оплата кредитной картой приносит большую часть прибыли 78,34%
--меньше всего приносят прибыль оплаты с дебетовой карты
--у неопределенного типа оплат нет, как уже выяснилось при профилировке данных
      
--Так как при профилировке данных выяснилось, что у меня 2 значения без веса товара,
--я хочу добавить средний вес товаров вместо NULL значений. На практике я бы 
--создала копию таблицы, чтобы не испортить данные, но сейчас сделаю прямо тут

UPDATE products 
SET product_weight_g = (SELECT AVG(product_weight_g) FROM products)
WHERE product_weight_g IS NULL;