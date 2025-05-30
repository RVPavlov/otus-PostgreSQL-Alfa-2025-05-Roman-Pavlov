--1.Выполнить pgbench -c8 -P 6 -T 60 -U postgres test.

postgres@HNBA114133:/home/romario$ pgbench -c8 -P 6 -T 60 -U postgres test
pgbench (16.9 (Ubuntu 16.9-0ubuntu0.24.04.1))
starting vacuum...end.
progress: 6.0 s, 310.5 tps, lat 25.610 ms stddev 23.083, 0 failed
progress: 12.0 s, 320.0 tps, lat 24.991 ms stddev 24.548, 0 failed
progress: 18.0 s, 342.7 tps, lat 23.322 ms stddev 17.921, 0 failed
progress: 24.0 s, 338.7 tps, lat 23.611 ms stddev 17.248, 0 failed
progress: 30.0 s, 322.5 tps, lat 24.827 ms stddev 25.245, 0 failed
progress: 36.0 s, 345.0 tps, lat 23.176 ms stddev 16.090, 0 failed
progress: 42.0 s, 341.7 tps, lat 23.385 ms stddev 16.195, 0 failed
progress: 48.0 s, 315.8 tps, lat 25.339 ms stddev 23.900, 0 failed
progress: 54.0 s, 344.7 tps, lat 23.182 ms stddev 16.373, 0 failed
progress: 60.0 s, 345.0 tps, lat 23.186 ms stddev 16.622, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 19967
number of failed transactions: 0 (0.000%)
latency average = 24.027 ms
latency stddev = 19.953 ms
initial connection time = 17.773 ms
tps = 332.766867 (without initial connection time)

--2.Настроить параметры vacuum/autovacuum.

alter system set log_autovacuum_min_duration= 0;
alter system set autovacuum_max_workers= 10;
alter system set autovacuum_naptime= '15s';
alter system set autovacuum_vacuum_threshold= 25;
alter system set autovacuum_vacuum_scale_factor= 0.05;
alter system set autovacuum_vacuum_cost_delay= 10;
alter system set autovacuum_vacuum_cost_limit= 1000;

select pg_reload_conf();

romario@HNBA114133:~$ sudo pg_ctlcluster 16 main restart

--3.Заново протестировать: pgbench -c8 -P 6 -T 60 -U postgres test и сравнить результаты.

postgres@HNBA114133:/home/romario$ pgbench -c8 -P 6 -T 60 -U postgres test
pgbench (16.9 (Ubuntu 16.9-0ubuntu0.24.04.1))
starting vacuum...end.
progress: 6.0 s, 311.5 tps, lat 25.537 ms stddev 22.452, 0 failed
progress: 12.0 s, 310.7 tps, lat 25.704 ms stddev 25.052, 0 failed
progress: 18.0 s, 308.2 tps, lat 25.963 ms stddev 26.683, 0 failed
progress: 24.0 s, 344.7 tps, lat 23.204 ms stddev 16.599, 0 failed
progress: 30.0 s, 353.7 tps, lat 22.599 ms stddev 15.288, 0 failed
progress: 36.0 s, 346.7 tps, lat 23.063 ms stddev 16.245, 0 failed
progress: 42.0 s, 336.2 tps, lat 23.791 ms stddev 21.829, 0 failed
progress: 48.0 s, 341.8 tps, lat 23.436 ms stddev 18.638, 0 failed
progress: 54.0 s, 356.5 tps, lat 22.427 ms stddev 15.934, 0 failed
progress: 60.0 s, 350.3 tps, lat 22.813 ms stddev 16.099, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 20169
number of failed transactions: 0 (0.000%)
latency average = 23.788 ms
latency stddev = 19.714 ms
initial connection time = 18.827 ms
tps = 336.107606 (without initial connection time)

-- Сравнение: Результаты почти такие же, следовательно новые настройки автовакуума не влияют на нагрузку

--4.Создать таблицу с текстовым полем и заполнить случайными или сгенерированными данным в размере 1млн строк.

-- создаем
create table public.test(str text);
-- заполняем
INSERT INTO public.test (str)
SELECT md5(random()::text)
FROM generate_series(1, 1000000);


--5.Посмотреть размер файла с таблицей.

SELECT pg_size_pretty(pg_total_relation_size('test')); -- 65 MB


--6.Обновить все строчки 5 раз добавив к каждой строчке любой символ.

-- обновляем
update test set str = str || '1';
update test set str = str || '2';
update test set str = str || '3';
update test set str = str || '4';
update test set str = str || '5';
-- снова смотрим размер таблицы, он увеличился в 5 раз
SELECT pg_size_pretty(pg_total_relation_size('test')); -- 326 MB

--7.Посмотреть количество мертвых строчек в таблице и когда последний раз приходил автовакуум.

SELECT relname, n_dead_tup, last_autovacuum 
-- 		"test"	0			"2025-05-30 16:54:49.744903+03"
FROM pg_stat_user_TABLEs 
WHERE relname = 'test'; 

--8.Отключить Автовакуум на таблице и опять 5 раз обновить все строки.

-- отключаем
ALTER TABLE test SET (autovacuum_enabled = off);
-- убеждаемся, что отключили
SELECT reloptions FROM pg_class WHERE relname = 'test';
-- обновляем строки
update test set str = str || '1';
update test set str = str || '2';
update test set str = str || '3';
update test set str = str || '4';
update test set str = str || '5';

-- смотрим мертвые строки
SELECT relname, n_dead_tup, last_autovacuum 
-- 		"test"	4999688		"2025-05-30 16:54:49.744903+03"
FROM pg_stat_user_TABLEs 
WHERE relname = 'test'; 

-- смотрим размер таблицы
SELECT pg_size_pretty(pg_total_relation_size('test')); -- 415 MB


--9.Объяснить полученные результаты:

-- 9.1 Размер таблицы после autovacuum не уменьшился, т.к. место из под удаленных строк осталось под новые строки
-- 9.2 Сократить размер таблицы можно с помощью vacuum full
-- 9.3 При включенном autovacuum он почти сразу удаляет мертвые строки после update поэтому количество мертвых строк было 0
-- 9.4 При выключенном autovacuum мертвые строки остаются

