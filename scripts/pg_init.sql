-- Выполняется один раз при первой инициализации кластера PG (docker-entrypoint-initdb.d).
-- Роль только-чтение для JDBC-каталога StarRocks и БД Lakekeeper.

CREATE ROLE lakekeeper LOGIN PASSWORD 'lakekeeper';
CREATE DATABASE lakekeeper_meta OWNER lakekeeper;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'retailco_ro') THEN
    CREATE ROLE retailco_ro LOGIN PASSWORD 'retailco_ro';
  END IF;
END
$$;
