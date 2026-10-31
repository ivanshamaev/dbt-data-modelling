-- PREFIX заменяется проверенным префиксом сценария. Повторное использование пространства запрещено.
SET CATALOG default_catalog;
CREATE DATABASE PREFIXanalytics;
SET CATALOG iceberg;
CREATE DATABASE PREFIXbronze;
CREATE DATABASE PREFIXinmon_stage;
CREATE DATABASE PREFIXinmon_core;
CREATE DATABASE PREFIXinmon_marts;
CREATE DATABASE PREFIXkimball_stage;
CREATE DATABASE PREFIXvault_stage;
CREATE DATABASE PREFIXvault_core;
CREATE DATABASE PREFIXvault_marts;
CREATE DATABASE PREFIXanchor_stage;
CREATE DATABASE PREFIXanchor_core;
CREATE DATABASE PREFIXanchor_marts;
CREATE DATABASE PREFIXmed_bronze;
CREATE DATABASE PREFIXmed_silver;
CREATE DATABASE PREFIXmed_gold;
