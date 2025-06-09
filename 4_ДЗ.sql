-- 1. Настройте сервер так, чтобы в журнал сообщений сбрасывалась информация о блокировках, удерживаемых более 200 миллисекунд.
alter system set log_lock_waits = on;
alter system set log_min_duration_statement = '200ms';
 
-- рестартуем кластер: sudo pg_ctlcluster 16 main restart 

-- 2.Воспроизведите ситуацию, при которой в журнале появятся такие сообщения.
-- в 1-й сессии запускаем
begin;
update test2 set
	amount = 200
where i = 1;

-- во 2-й сессии запускаем
begin;
SELECT i, amount
	FROM public.test2;

-- 3.Смоделируйте ситуацию обновления одной и той же строки тремя командами UPDATE в разных сеансах.
-- 1-й сеанс
begin;
update test2 set
	amount = 210
where i = 1;

-- 2-й сеанс (заблокировано)
begin;
update test2 set
	amount = 220
where i = 1;

-- 3-й сеанс (заблокировано)
begin;
update test2 set
	amount = 230
where i = 1;

commit;
-- 4.Изучите возникшие блокировки в представлении pg_locks и убедитесь, что все они понятны.
Каждая из транзакций создала блокировку уровня RowExclusiveLock

-- 5.Воспроизведите взаимоблокировку трех транзакций.

-- I-й шаг:

-- 1-й сеанс
begin;
update test2 set
	amount = 210
where i = 1;

-- 2-й сеанс
begin;
update test2 set
	amount = 220
where i = 2;

-- 3-й сеанс
begin;
update test2 set
	amount = 550
where i = 3;

-- II-й шаг:

-- 1-й сеанс (заблокировано)
update test2 set
	amount = 550
where i = 3;

-- 2-й сеанс (заблокировано)
update test2 set
	amount = 220
where i = 1;

-- 3-й сеанс (заблокировано)
update test2 set
	amount = 550
where i = 2;

-- в результате имеем ошибку
ERROR:  deadlock detected
Process 2435 waits for ShareLock on transaction 309703; blocked by process 11798.
Process 11798 waits for ShareLock on transaction 309702; blocked by process 4512.
Process 4512 waits for ShareLock on transaction 309701; blocked by process 2435. 

-- 6.Можно ли разобраться в ситуации постфактум, изучая журнал сообщений?

-- Ответ: изучая сообщения об ошибках можно понять кто кого блокировал, но журнал блокировок после коммита не содержит информации о блокировках

SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid in (11798, 4512, 2435);


