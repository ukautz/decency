-- 2011-05-15

-- For: Archive
-- TABLE: archive_index (SQLITE):
CREATE TABLE ARCHIVE_INDEX ("search" text, "from_domain" varchar(255), "subject" varchar(255), "from_prefix" varchar(255), "created" int, "to_domain" varchar(255), "to_prefix" varchar(255), "filename" text, "md5" varchar(32), id INTEGER PRIMARY KEY);
CREATE INDEX ARCHIVE_INDEX_CREATED ON ARCHIVE_INDEX ("created");
CREATE INDEX ARCHIVE_INDEX_SUBJECT ON ARCHIVE_INDEX ("subject");
CREATE INDEX ARCHIVE_INDEX_FROM_DOMAIN_FROM_PREFIX ON ARCHIVE_INDEX ("from_domain", "from_prefix");
CREATE INDEX ARCHIVE_INDEX_TO_DOMAIN_TO_PREFIX ON ARCHIVE_INDEX ("to_domain", "to_prefix");


-- For: Mail::Decency::Detective=HASH(0x2ac1d28)
-- TABLE: stats_detective_results (SQLITE):
CREATE TABLE STATS_DETECTIVE_RESULTS ("calls" integer, "period" varchar(10), "last_update" integer, "status" varchar(32), "module" varchar(32), "start" integer, id INTEGER PRIMARY KEY);
CREATE INDEX STATS_DETECTIVE_RESULTS_START ON STATS_DETECTIVE_RESULTS ("start");
CREATE UNIQUE INDEX STATS_DETECTIVE_RESULTS_MODULE_PERIOD_STATUS_START ON STATS_DETECTIVE_RESULTS ("module", "period", "status", "start");

-- TABLE: stats_detective_performance (SQLITE):
CREATE TABLE STATS_DETECTIVE_PERFORMANCE ("calls" integer, "period" varchar(10), "last_update" integer, "score" integer, "runtime" real, "module" varchar(32), "start" integer, id INTEGER PRIMARY KEY);
CREATE INDEX STATS_DETECTIVE_PERFORMANCE_START ON STATS_DETECTIVE_PERFORMANCE ("start");
CREATE UNIQUE INDEX STATS_DETECTIVE_PERFORMANCE_MODULE_PERIOD_START ON STATS_DETECTIVE_PERFORMANCE ("module", "period", "start");

-- TABLE: stats_detective_final_state (SQLITE):
CREATE TABLE STATS_DETECTIVE_FINAL_STATE ("amount" integer, "period" varchar(25), "status" varchar(10), "start" integer, id INTEGER PRIMARY KEY);
CREATE INDEX STATS_DETECTIVE_FINAL_STATE_START ON STATS_DETECTIVE_FINAL_STATE ("start");
CREATE UNIQUE INDEX STATS_DETECTIVE_FINAL_STATE_PERIOD_STATUS_START ON STATS_DETECTIVE_FINAL_STATE ("period", "status", "start");

-- For: SenderPermit
-- TABLE: sender_permit (SQLITE):
CREATE TABLE SENDER_PERMIT ("to_domain" varchar(255), "from_domain" varchar(255), "ip" varchar(39), "subject" varchar(255), "fingerprint" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX SENDER_PERMIT_FROM_DOMAIN_TO_DOMAIN_FINGERPRINT_SUBJECT_IP ON SENDER_PERMIT ("from_domain", "to_domain", "fingerprint", "subject", "ip");


-- For: CWL
-- TABLE: cwl_domains (SQLITE):
CREATE TABLE CWL_DOMAINS ("from_domain" varchar(255), "to_domain" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CWL_DOMAINS_TO_DOMAIN_FROM_DOMAIN ON CWL_DOMAINS ("to_domain", "from_domain");

-- TABLE: cwl_addresses (SQLITE):
CREATE TABLE CWL_ADDRESSES ("from_address" varchar(255), "to_domain" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CWL_ADDRESSES_TO_DOMAIN_FROM_ADDRESS ON CWL_ADDRESSES ("to_domain", "from_address");

-- TABLE: cwl_ips (SQLITE):
CREATE TABLE CWL_IPS ("to_domain" varchar(255), "ip" varchar(39), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CWL_IPS_TO_DOMAIN_IP ON CWL_IPS ("to_domain", "ip");


-- For: CBL
-- TABLE: cbl_domains (SQLITE):
CREATE TABLE CBL_DOMAINS ("from_domain" varchar(255), "to_domain" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CBL_DOMAINS_TO_DOMAIN_FROM_DOMAIN ON CBL_DOMAINS ("to_domain", "from_domain");

-- TABLE: cbl_addresses (SQLITE):
CREATE TABLE CBL_ADDRESSES ("from_address" varchar(255), "to_domain" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CBL_ADDRESSES_TO_DOMAIN_FROM_ADDRESS ON CBL_ADDRESSES ("to_domain", "from_address");

-- TABLE: cbl_ips (SQLITE):
CREATE TABLE CBL_IPS ("to_domain" varchar(255), "ip" varchar(39), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CBL_IPS_TO_DOMAIN_IP ON CBL_IPS ("to_domain", "ip");


-- For: GeoWeight
-- TABLE: geo_stats (SQLITE):
CREATE TABLE GEO_STATS ("country" varchar(2), "counter" integer, "interval" varchar(25), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX GEO_STATS_COUNTRY_INTERVAL ON GEO_STATS ("country", "interval");


-- For: Honeypot
-- TABLE: honeypot_ips (SQLITE):
CREATE TABLE HONEYPOT_IPS ("created" integer, "ip" varchar(39), id INTEGER PRIMARY KEY);
CREATE INDEX HONEYPOT_IPS_CREATED ON HONEYPOT_IPS ("created");
CREATE UNIQUE INDEX HONEYPOT_IPS_IP ON HONEYPOT_IPS ("ip");


-- For: Greylist
-- TABLE: greylist_recipient (SQLITE):
CREATE TABLE GREYLIST_RECIPIENT ("to_domain" varchar(255), "from_address" varchar(255), "last_update" integer, "ip" varchar(39), "data" integer, id INTEGER PRIMARY KEY);
CREATE INDEX GREYLIST_RECIPIENT_LAST_UPDATE ON GREYLIST_RECIPIENT ("last_update");
CREATE UNIQUE INDEX GREYLIST_RECIPIENT_FROM_ADDRESS_IP_TO_DOMAIN ON GREYLIST_RECIPIENT ("from_address", "ip", "to_domain");

-- TABLE: greylist_sender (SQLITE):
CREATE TABLE GREYLIST_SENDER ("to_domain" varchar(255), "from_domain" varchar(255), "last_update" integer, "ip" varchar(39), "data" integer, id INTEGER PRIMARY KEY);
CREATE INDEX GREYLIST_SENDER_LAST_UPDATE ON GREYLIST_SENDER ("last_update");
CREATE UNIQUE INDEX GREYLIST_SENDER_FROM_DOMAIN_IP_TO_DOMAIN ON GREYLIST_SENDER ("from_domain", "ip", "to_domain");

-- TABLE: greylist_address (SQLITE):
CREATE TABLE GREYLIST_ADDRESS ("from_address" varchar(255), "last_update" integer, "ip" varchar(39), "data" integer, "to_address" varchar(255), id INTEGER PRIMARY KEY);
CREATE INDEX GREYLIST_ADDRESS_LAST_UPDATE ON GREYLIST_ADDRESS ("last_update");
CREATE UNIQUE INDEX GREYLIST_ADDRESS_FROM_ADDRESS_IP_TO_ADDRESS ON GREYLIST_ADDRESS ("from_address", "ip", "to_address");


-- For: Throttle
-- TABLE: throttle_sender_address (SQLITE):
CREATE TABLE THROTTLE_SENDER_ADDRESS ("sender_address" varchar(255), "maximum" integer, "account" varchar(100), "interval" integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_SENDER_ADDRESS_SENDER_ADDRESS_INTERVAL ON THROTTLE_SENDER_ADDRESS ("sender_address", "interval");

-- TABLE: throttle_sasl_username (SQLITE):
CREATE TABLE THROTTLE_SASL_USERNAME ("maximum" integer, "sasl_username" varchar(255), "account" varchar(100), "interval" integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_SASL_USERNAME_SASL_USERNAME_INTERVAL ON THROTTLE_SASL_USERNAME ("sasl_username", "interval");

-- TABLE: throttle_account (SQLITE):
CREATE TABLE THROTTLE_ACCOUNT ("maximum" integer, "account" varchar(100), "interval" integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_ACCOUNT_ACCOUNT_INTERVAL ON THROTTLE_ACCOUNT ("account", "interval");

-- TABLE: throttle_sender_domain (SQLITE):
CREATE TABLE THROTTLE_SENDER_DOMAIN ("maximum" integer, "account" varchar(100), "sender_domain" varchar(255), "interval" integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_SENDER_DOMAIN_SENDER_DOMAIN_INTERVAL ON THROTTLE_SENDER_DOMAIN ("sender_domain", "interval");

-- TABLE: throttle_client_address (SQLITE):
CREATE TABLE THROTTLE_CLIENT_ADDRESS ("maximum" integer, "account" varchar(100), "client_address" varchar(39), "interval" integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_CLIENT_ADDRESS_CLIENT_ADDRESS_INTERVAL ON THROTTLE_CLIENT_ADDRESS ("client_address", "interval");

-- TABLE: throttle_recipient_domain (SQLITE):
CREATE TABLE THROTTLE_RECIPIENT_DOMAIN ("maximum" integer, "account" varchar(100), "interval" integer, "recipient_domain" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_RECIPIENT_DOMAIN_RECIPIENT_DOMAIN_INTERVAL ON THROTTLE_RECIPIENT_DOMAIN ("recipient_domain", "interval");

-- TABLE: throttle_recipient_address (SQLITE):
CREATE TABLE THROTTLE_RECIPIENT_ADDRESS ("maximum" integer, "account" varchar(100), "interval" integer, "recipient_address" varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_RECIPIENT_ADDRESS_RECIPIENT_ADDRESS_INTERVAL ON THROTTLE_RECIPIENT_ADDRESS ("recipient_address", "interval");


-- For: Mail::Decency::Doorman=HASH(0x2a5b5d8)
-- TABLE: stats_doorman_results (SQLITE):
CREATE TABLE STATS_DOORMAN_RESULTS ("calls" integer, "period" varchar(10), "last_update" integer, "status" varchar(32), "module" varchar(32), "start" integer, id INTEGER PRIMARY KEY);
CREATE INDEX STATS_DOORMAN_RESULTS_START ON STATS_DOORMAN_RESULTS ("start");
CREATE UNIQUE INDEX STATS_DOORMAN_RESULTS_MODULE_PERIOD_STATUS_START ON STATS_DOORMAN_RESULTS ("module", "period", "status", "start");

-- TABLE: stats_doorman_performance (SQLITE):
CREATE TABLE STATS_DOORMAN_PERFORMANCE ("calls" integer, "period" varchar(10), "last_update" integer, "score" integer, "runtime" real, "module" varchar(32), "start" integer, id INTEGER PRIMARY KEY);
CREATE INDEX STATS_DOORMAN_PERFORMANCE_START ON STATS_DOORMAN_PERFORMANCE ("start");
CREATE UNIQUE INDEX STATS_DOORMAN_PERFORMANCE_MODULE_PERIOD_START ON STATS_DOORMAN_PERFORMANCE ("module", "period", "start");

-- TABLE: stats_doorman_final_state (SQLITE):
CREATE TABLE STATS_DOORMAN_FINAL_STATE ("amount" integer, "period" varchar(25), "status" varchar(10), "start" integer, id INTEGER PRIMARY KEY);
CREATE INDEX STATS_DOORMAN_FINAL_STATE_START ON STATS_DOORMAN_FINAL_STATE ("start");
CREATE UNIQUE INDEX STATS_DOORMAN_FINAL_STATE_PERIOD_STATUS_START ON STATS_DOORMAN_FINAL_STATE ("period", "status", "start");


